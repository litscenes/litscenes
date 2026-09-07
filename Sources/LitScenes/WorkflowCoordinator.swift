import Foundation
import SwiftUI

@MainActor
final class WorkflowCoordinator: ObservableObject {
    static let shared = WorkflowCoordinator()
    @Published private(set) var jobs: [WorkflowJob] = []
    @Published private(set) var historyError = ""
    @Published var showingLogs = false
    @Published var projectFilter = ""
    @Published var search = ""
    @Published var statusFilter = ""
    @Published var providerFilter = ""
    @Published var workflowFilter = ""
    @Published var selectedLogId: String?
    @Published private(set) var eventRevision = 0
    private var historyLimit = 100
    @Published var pendingOpenJob: WorkflowJob?
    private var initialized = false
    private var initializing: Task<Void, Never>?
    private var waiting: [String: [CheckedContinuation<Bool, Never>]] = [:]
    private var admitted: Set<String> = []
    private var live: Set<String> = []
    private var queueOrder: [String] = []
    private var stopped: Set<String> = []
    private var failures: Set<String> = []
    private var vendorHolds: [String: String] = [:]
    private var cancelTasks: [String: () -> Void] = [:]
    private var terminating = false

    var activeJobs: [WorkflowJob] { jobs.filter { !$0.state.isTerminal } }
    var needsAttention: Bool { jobs.contains { $0.state == .pausedAutomatically || $0.state == .failed } }
    var runningCount: Int { jobs.filter { [.running, .stopping].contains($0.state) }.count }

    func bootstrap() async {
        if initialized { return }
        if let initializing { await initializing.value; return }
        let task = Task { @MainActor in
            do {
                var stored = try await InferenceTraceStore.shared.workflows(limit: 100)
                let unfinished = try await InferenceTraceStore.shared.workflows(limit: 100_000, unfinishedOnly: true)
                for var job in unfinished {
                    job.state = .pausedAutomatically
                    job.phase = "Session interrupted"
                    if job.reason.isEmpty { job.reason = "The app closed before this work finished. Review its saved request before continuing." }
                    job.requiresReview = true
                    job.updatedAt = DateFormats.now()
                    try await InferenceTraceStore.shared.saveWorkflow(job, event: WorkflowEvent(jobId: job.id, state: job.state, phase: job.phase, message: job.reason))
                    stored.removeAll { $0.id == job.id }; stored.append(job)
                }
                self.jobs = stored.sorted { $0.updatedAt > $1.updatedAt }
                self.initialized = true
            } catch { self.historyError = WorkflowPrivacy.text(error.localizedDescription) }
        }
        initializing = task
        await task.value
        initializing = nil
    }

    func run<Value: Sendable>(project: ProjectRecord?, workflow: String, artifactType: String = "", artifactId: String = "", lane: WorkflowLane,
                    recipeJSON: String = "", failure: Value, onAccepted: (() -> Void)? = nil, operation: @escaping @MainActor () async -> Value) async -> Value {
        if let inherited = WorkflowContext.current, inherited.projectId == project?.projectId {
            if stopped.contains(inherited.jobId) { return failure }
            return await operation()
        }
        await bootstrap()
        guard initialized, !terminating else { return failure }
        var job = WorkflowJob(projectId: project?.projectId ?? "", projectName: project?.name ?? "App",
            workflow: workflow, artifactType: artifactType, artifactId: artifactId, lane: lane)
        job.recipeJSON = WorkflowPrivacy.json(recipeJSON)
        job.submissionKey = sha256Hex(Data("\(job.projectId):\(workflow):\(artifactId):\(job.recipeJSON)".utf8))
        // Repeated clicks on an in-flight request do not create a second paid run.
        guard !jobs.contains(where: { live.contains($0.id) && !$0.state.isTerminal
            && $0.submissionKey == job.submissionKey }) else { return failure }
        guard await save(job, message: "Request accepted") else { return failure }
        onAccepted?()
        let id = job.id
        live.insert(id)
        queueOrder.append(id)
        let context = WorkflowContext(jobId: id, projectId: job.projectId, workflow: workflow,
            artifactType: artifactType, artifactId: artifactId, lane: lane)
        let task = Task { @MainActor in
            if lane == .local {
                let allowed = await self.waitForAdmission(id)
                guard allowed else { return failure }
            }
            let result = await WorkflowContext.$current.withValue(context) { await operation() }
            let success: Bool
            if let value = result as? any WorkflowOutcomeReporting { success = value.workflowSucceeded }
            else if let value = result as? Bool { success = value }
            else if let value = result as? ShotContinuationOutcome { if case .ready = value { success = true } else { success = false } }
            else if Mirror(reflecting: result).displayStyle == .optional && Mirror(reflecting: result).children.isEmpty { success = false }
            else { success = !self.jobs.contains { $0.id == id && $0.state == .failed } }
            await self.finish(id, succeeded: success && !self.failures.contains(id))
            return result
        }
        cancelTasks[id] = { task.cancel() }
        let result = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
            Task { @MainActor in await self.cancel(id) }
        }
        cancelTasks.removeValue(forKey: id)
        live.remove(id)
        queueOrder.removeAll { $0 == id }
        return result
    }

    private func waitForAdmission(_ id: String) async -> Bool {
        guard !terminating, !stopped.contains(id), !Task.isCancelled else { return false }
        if admitted.contains(id) { return true }
        return await withCheckedContinuation { continuation in
            waiting[id, default: []].append(continuation)
            drain()
        }
    }

    private func drain() {
        guard !terminating else { return }
        let candidates = queueOrder.compactMap { id in jobs.first { $0.id == id } }
            .filter { waiting[$0.id] != nil && !admitted.contains($0.id) && $0.state == .queued }
        for job in candidates {
            let running = jobs.filter { admitted.contains($0.id) }
            guard running.filter({ $0.lane == job.lane }).count < job.lane.capacity else { continue }
            guard job.conflictKey.isEmpty || !running.contains(where: { $0.conflictKey == job.conflictKey }) else { continue }
            guard job.provider.isEmpty || vendorHolds[job.provider] == nil else { continue }
            admitted.insert(job.id)
            Task { @MainActor in
                guard !stopped.contains(job.id), !terminating else { return }
                await transition(job.id, state: .running, phase: "Starting")
                let allowed = historyError.isEmpty && !stopped.contains(job.id) && !terminating
                waiting.removeValue(forKey: job.id)?.forEach { $0.resume(returning: allowed) }
            }
        }
    }

    private func finish(_ id: String, succeeded: Bool) async {
        admitted.remove(id)
        if !terminating, let job = jobs.first(where: { $0.id == id }), job.state != .pausedAutomatically {
            await transition(id, state: stopped.contains(id) ? .canceled : succeeded ? .succeeded : .failed,
                phase: stopped.contains(id) ? "Stopped; completed outputs kept" : succeeded ? "Completed" : "Failed")
        }
        stopped.remove(id)
        failures.remove(id)
        drain()
    }

    func transition(_ id: String, state: WorkflowState? = nil, phase: String, message: String = "", traceId: String = "") async {
        guard var job = jobs.first(where: { $0.id == id }), !terminating else { return }
        if job.state == .pausedAutomatically, let state, state != .queued && state != .canceled {
            _ = await save(job, message: message, traceId: traceId)
            return
        }
        if let state, !job.state.isTerminal, job.state != .pausedAutomatically || state == .queued || state == .canceled {
            job.state = state
        }
        // Late status messages must not erase the recovery action or terminal outcome.
        if (job.state == .pausedAutomatically || job.state.isTerminal) && state == nil {
            _ = await save(job, message: message, traceId: traceId)
            return
        }
        job.phase = phase
        if !message.isEmpty { job.reason = WorkflowPrivacy.text(message) }
        if !traceId.isEmpty, !job.traceIds.contains(traceId) { job.traceIds.append(traceId) }
        job.updatedAt = DateFormats.now()
        _ = await save(job, message: message, traceId: traceId)
    }

    @discardableResult
    private func save(_ job: WorkflowJob, message: String = "", traceId: String = "") async -> Bool {
        // Publish before suspension so a sibling completion cannot overwrite a newer record.
        if let index = jobs.firstIndex(where: { $0.id == job.id }) { jobs[index] = job }
        else { jobs.insert(job, at: 0) }
        do {
            try await InferenceTraceStore.shared.saveWorkflow(job, event: WorkflowEvent(jobId: job.id,
                state: job.state, phase: job.phase, message: WorkflowPrivacy.text(message), traceId: traceId))
            historyError = ""
            eventRevision += 1
            return true
        } catch { historyError = WorkflowPrivacy.text(error.localizedDescription); return false }
    }

    func flagFailure() {
        if let context = WorkflowContext.current { failures.insert(context.jobId) }
    }

    func checkStopRequested() throws {
        guard !terminating, !Task.isCancelled,
              WorkflowContext.current.map({ !stopped.contains($0.jobId) }) ?? true else { throw CancellationError() }
    }

    func bindArtifact(type: String, id: String) {
        guard let context = WorkflowContext.current, let index = jobs.firstIndex(where: { $0.id == context.jobId }) else { return }
        jobs[index].artifactType = type
        jobs[index].artifactId = id
    }

    func providerStarted(_ metadata: InferenceTraceRequestMetadata, traceId: String, isSubmission: Bool = true) async throws {
        guard let context = WorkflowContext.current else { return }
        guard !terminating, !(isSubmission && stopped.contains(context.jobId)) else { throw CancellationError() }
        if var job = jobs.first(where: { $0.id == context.jobId }) {
            job.provider = metadata.provider; job.model = metadata.model
            job.phase = metadata.workflowStep.isEmpty ? metadata.operation : metadata.workflowStep
            if !job.traceIds.contains(traceId) { job.traceIds.append(traceId) }
            job.updatedAt = DateFormats.now()
            guard await save(job, traceId: traceId) else { throw ScreenGraphError.capture("Could not persist provider request provenance") }
        }
        if let reason = vendorHolds[metadata.provider], isSubmission {
            try await holdCurrent(provider: metadata.provider, reason: reason)
        } else if !admitted.contains(context.jobId) {
            guard await waitForAdmission(context.jobId) else { throw CancellationError() }
        }
    }

    func providerResponded(_ metadata: InferenceTraceRequestMetadata, data: Data, response: HTTPURLResponse?) async {
        guard let context = WorkflowContext.current,
              var job = jobs.first(where: { $0.id == context.jobId }) else { return }
        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let requestId = root["request_id"] as? String ?? root["job_id"] as? String
            ?? root["id"] as? String ?? response?.value(forHTTPHeaderField: "x-request-id") ?? ""
        if !requestId.isEmpty { job.providerRequestId = WorkflowPrivacy.text(requestId) }
        _ = await save(job, message: "Provider response received")
        if let recovery = jobs.first(where: { $0.id != job.id && $0.state == .pausedAutomatically
            && $0.projectId == job.projectId && $0.provider == job.provider
            && !$0.providerRequestId.isEmpty && $0.providerRequestId == job.providerRequestId }) {
            await transition(recovery.id, phase: recovery.phase, message: "Existing provider request inspected by " + job.id)
        }
    }

    func holdCurrent(provider: String, reason: String) async throws {
        guard let context = WorkflowContext.current else { throw ScreenGraphError.capture(reason) }
        vendorHolds[provider] = reason
        let affected = jobs.filter { !$0.state.isTerminal && $0.provider == provider }
        for job in affected where job.id == context.jobId || !admitted.contains(job.id) {
            await transition(job.id, state: .pausedAutomatically, phase: "Vendor account needs attention", message: reason)
        }
        guard !stopped.contains(context.jobId), !Task.isCancelled, !terminating else { throw CancellationError() }
        // Retain the exact request until Continue; retrieval never creates a new paid run.
        admitted.remove(context.jobId)
        let allowed = await withCheckedContinuation { continuation in
            waiting[context.jobId, default: []].append(continuation)
            drain()
        }
        guard allowed, !terminating else { throw CancellationError() }
    }

    func markUncertain(_ failure: ProviderFailure) async {
        guard let context = WorkflowContext.current,
              var job = jobs.first(where: { $0.id == context.jobId }) else { return }
        job.state = .pausedAutomatically; job.phase = "Review provider acceptance"
        job.reason = failure.message + " Acceptance is unknown; check the existing request before another paid attempt."
        job.submissionUncertain = true; job.requiresReview = true
        _ = await save(job, message: job.reason)
    }

    func cancel(_ id: String) async {
        guard let job = jobs.first(where: { $0.id == id }), !job.state.isTerminal else { return }
        stopped.insert(id)
        if let continuation = waiting.removeValue(forKey: id) {
            await transition(id, state: .canceled, phase: "Canceled before the next submission")
            continuation.forEach { $0.resume(returning: false) }
            admitted.remove(id)
            drain()
        } else if admitted.contains(id) {
            await transition(id, state: .stopping, phase: "Stopping after the current step", message: "The current provider request may still finish and charge; its output will be retained.")
        } else {
            cancelTasks[id]?()
            await transition(id, state: .canceled, phase: "Canceled locally", message: "Previously submitted provider work may still complete.")
        }
    }

    func canContinue(_ job: WorkflowJob) -> Bool { waiting[job.id] != nil && !job.requiresReview }

    func continueJob(_ job: WorkflowJob) async {
        guard canContinue(job) else { pendingOpenJob = job; return }
        let provider = job.provider
        vendorHolds.removeValue(forKey: provider)
        let ids = jobs.filter { $0.state == .pausedAutomatically && $0.provider == provider && waiting[$0.id] != nil && !$0.requiresReview }.map(\.id)
        for id in ids { await transition(id, state: .queued, phase: "Waiting for capacity", message: "Continue requested") }
        drain()
    }

    func refreshHistory() async {
        historyLimit = 0
        await loadMore()
    }

    func loadMore() async {
        do {
            historyLimit += 100
            // Growing the durable prefix avoids skipping rows as active records move.
            let page = try await InferenceTraceStore.shared.workflows(limit: historyLimit,
                projectId: projectFilter, status: statusFilter, provider: providerFilter, workflow: workflowFilter, search: search)
            let existing = Set(jobs.map(\.id)); jobs.append(contentsOf: page.filter { !existing.contains($0.id) })
        } catch { historyError = WorkflowPrivacy.text(error.localizedDescription) }
    }

    func checkpointForTermination() async {
        terminating = true
        for var job in jobs where !job.state.isTerminal {
            job.state = .pausedAutomatically; job.phase = "App closed before completion"
            job.reason = "Review the saved request and any submitted provider job before continuing."
            job.requiresReview = true; job.updatedAt = DateFormats.now()
            _ = await save(job, message: job.reason)
        }
    }

    func recordSpend(_ entry: SpendLedgerEntry, project: ProjectRecord) async {
        await bootstrap()
        let id = WorkflowContext.current?.jobId
            ?? jobs.first(where: { !$0.traceIds.isEmpty && $0.traceIds.contains(entry.traceId) })?.id
        guard let id, var job = jobs.first(where: { $0.id == id }) else { return }
        job.spendEntries = (job.spendEntries ?? []).filter { $0.entryId != entry.entryId } + [entry]
        if !entry.requestId.isEmpty { job.providerRequestId = entry.requestId }
        if !entry.traceId.isEmpty, !job.traceIds.contains(entry.traceId) { job.traceIds.append(entry.traceId) }
        _ = await save(job, message: "Spend recorded: " + entry.status, traceId: entry.traceId)
    }

    func note(project: ProjectRecord?, workflow: String, message: String, failed: Bool = false) async {
        if let context = WorkflowContext.current {
            guard let job = jobs.first(where: { $0.id == context.jobId }) else { return }
            if failed, !job.state.isTerminal { failures.insert(context.jobId) }
            await transition(context.jobId, phase: workflow, message: message)
        } else {
            await bootstrap()
            var job = WorkflowJob(projectId: project?.projectId ?? "", projectName: project?.name ?? "App",
                workflow: workflow, artifactType: "", artifactId: "", lane: .local)
            job.state = failed ? .failed : .succeeded; job.phase = workflow; job.reason = WorkflowPrivacy.text(message)
            _ = await save(job, message: message)
        }
    }
}
