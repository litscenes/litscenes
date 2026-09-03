import AppKit
import Foundation
import SwiftUI

private struct BufferedCapture: Hashable {
    var record: CaptureRecord
    var fileURL: URL
    var imageData: Data
    var signature: FrameSignature
    var capturedAt: Date
    var releaseAt: Date
}

@MainActor
final class RecorderEngine: ObservableObject {
    @Published var config = SessionConfig()
    @Published private(set) var projects: [ProjectRecord] = []
    @Published private(set) var currentProject: ProjectRecord?
    @Published private(set) var isStarting = false
    @Published private(set) var isRecording = false
    @Published private(set) var isPaused = false
    @Published private(set) var isStopping = false
    @Published private(set) var sessionId = ""
    @Published private(set) var sessionDirectory = ""
    @Published private(set) var captures: [CaptureRecord] = []
    @Published private(set) var analyses: [AnalysisEnvelope] = []
    @Published private(set) var summaries: [SummaryRecord] = []
    @Published private(set) var totals = SessionTotals()
    @Published private(set) var statusLine = "Idle"
    @Published private(set) var lastError = ""
    @Published private(set) var screenPermissionNotice = ""

    private let captureService = ScreenCaptureService()
    private let diffEngine = DiffEngine()
    private let projectLibrary = ProjectLibrary()
    private var pricingManifest: PricingManifest
    private var estimator: CostEstimator
    private var store: ArtifactStore?
    private var openAIClient: OpenAIClient?
    private var captureTask: Task<Void, Never>?
    private var processorTask: Task<Void, Never>?
    private var buffered: [BufferedCapture] = []
    private var analysisQueue: [BufferedCapture] = []
    private var activeAnalysisCapture: BufferedCapture?
    private var isAnalyzing = false
    private var previousAnalyzedSignature: FrameSignature?
    private var lastAnalysisDate: Date?
    private var lastSummaryDate: Date?

    init() {
        let manifest = (try? PricingManifest.load()) ?? PricingManifest(
            schemaVersion: "screen_graph.openai_pricing.v0.1",
            updatedAt: "2026-05-30",
            source: "fallback",
            models: [
                ModelPricing(model: "gpt-5.5", inputPerMillion: 1.25, cachedInputPerMillion: 0.125, outputPerMillion: 10.0)
            ]
        )
        pricingManifest = manifest
        estimator = CostEstimator(manifest: manifest)
        reloadProjects()
    }

    var hasPendingWork: Bool {
        isRecording || isStarting || isStopping || isAnalyzing || !buffered.isEmpty || !analysisQueue.isEmpty
    }

    var canSwitchProject: Bool {
        !hasPendingWork
    }

    func reloadProjects(selecting projectId: String? = nil) {
        do {
            let loaded = try projectLibrary.listProjects()
            projects = loaded
            let selectedId = projectId ?? currentProject?.projectId
            if let selectedId, let selected = loaded.first(where: { $0.projectId == selectedId }) {
                currentProject = selected
            } else {
                currentProject = loaded.first
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    @discardableResult
    func createProject(named name: String) -> Bool {
        guard canSwitchProject else {
            statusLine = "Stop current session before creating a project"
            return false
        }
        do {
            let project = try projectLibrary.createProject(named: name)
            currentProject = project
            reloadProjects(selecting: project.projectId)
            resetSessionView()
            statusLine = "Project: \(project.name)"
            return true
        } catch {
            lastError = error.localizedDescription
            statusLine = "Could not create project"
            return false
        }
    }

    func selectProject(_ project: ProjectRecord) {
        guard canSwitchProject else {
            statusLine = "Stop current session before switching projects"
            return
        }
        currentProject = project
        resetSessionView()
        statusLine = "Project: \(project.name)"
    }

    func start() {
        guard !isRecording, !isStarting, !isStopping, !isAnalyzing else { return }
        guard currentProject != nil else {
            statusLine = "Create a project first"
            return
        }
        isStarting = true
        lastError = ""
        statusLine = "Checking screen access"

        Task { [weak self] in
            guard let self else { return }
            await self.startAfterScreenAccessCheck()
        }
    }

    private func startAfterScreenAccessCheck() async {
        defer { isStarting = false }
        guard let project = currentProject else {
            statusLine = "Create a project first"
            return
        }

        do {
            _ = try await captureService.captureFullDisplay(excludingOwnWindows: config.excludeOwnWindows)
        } catch {
            screenPermissionNotice = """
            LitScenes could not capture a test frame.

            macOS reported: \(error.localizedDescription)

            If LitScenes is enabled in System Settings, quit and reopen LitScenes. If that still fails, remove LitScenes from the permission list and add this exact app bundle again.
            """
            statusLine = "Screen capture unavailable"
            return
        }

        screenPermissionNotice = ""
        do {
            openAIClient = try OpenAIClient.fromEnvironment()
        } catch {
            lastError = error.localizedDescription
            statusLine = "Missing OpenAI key"
            return
        }

        sessionId = "session_\(Self.fileTimestamp())_\(UUID().uuidString.prefix(8).lowercased())"
        let newStore = ArtifactStore(project: project, sessionId: sessionId, library: projectLibrary)
        do {
            try newStore.prepare(config: config)
            let updatedProject = try projectLibrary.recordSessionStarted(project: project, sessionId: sessionId)
            currentProject = updatedProject
            reloadProjects(selecting: updatedProject.projectId)
            try newStore.appendEvent(kind: "session_started", message: "Started screen graph recording.")
        } catch {
            lastError = error.localizedDescription
            statusLine = "Could not prepare session"
            return
        }

        store = newStore
        sessionDirectory = newStore.sessionDir.path
        captures.removeAll()
        analyses.removeAll()
        summaries.removeAll()
        buffered.removeAll()
        analysisQueue.removeAll()
        totals = SessionTotals()
        previousAnalyzedSignature = nil
        lastAnalysisDate = nil
        lastSummaryDate = Date()
        isRecording = true
        isPaused = false
        isStopping = false
        lastError = ""
        statusLine = "Recording"

        captureTask = Task { [weak self] in
            guard let self else { return }
            await self.captureLoop()
        }
        processorTask = Task { [weak self] in
            guard let self else { return }
            await self.processorLoop()
        }
    }

    func pause() {
        guard isRecording else { return }
        isPaused = true
        statusLine = "Paused"
        try? store?.appendEvent(kind: "paused", message: "Capture paused.")
    }

    func resume() {
        guard isRecording else { return }
        isPaused = false
        statusLine = "Recording"
        try? store?.appendEvent(kind: "resumed", message: "Capture resumed.")
    }

    func eraseLastBufferWindow() {
        guard let store else { return }
        let cutoff = Date().addingTimeInterval(-config.bufferDelaySeconds)
        var erased: [BufferedCapture] = []
        buffered.removeAll { item in
            if item.capturedAt >= cutoff {
                erased.append(item)
                return true
            }
            return false
        }
        analysisQueue.removeAll { item in
            if item.capturedAt >= cutoff {
                erased.append(item)
                return true
            }
            return false
        }

        for item in erased {
            try? FileManager.default.removeItem(at: item.fileURL)
            var record = item.record
            record.status = .erased
            record.message = "erased before upload"
            replaceCapture(record)
            try? store.appendCapture(record)
            totals.erased += 1
        }
        try? store.appendEvent(kind: "erase_last", message: "Erased \(erased.count) captures from the \(Int(config.bufferDelaySeconds)) second pre-upload window.")
        statusLine = erased.isEmpty ? "Nothing buffered to erase" : "Erased \(erased.count) buffered captures"
    }

    func finishQueuedAndStop() {
        guard isRecording || isStopping || isAnalyzing || !buffered.isEmpty || !analysisQueue.isEmpty else { return }
        let wasStopping = isStopping
        isRecording = false
        isPaused = false
        isStopping = true
        captureTask?.cancel()
        captureTask = nil
        if !wasStopping {
            try? store?.appendEvent(kind: "session_stopping", message: "Capture stopped; finishing released analysis queue.")
        }
        statusLine = "Stopping"
    }

    func stop() {
        finishQueuedAndStop()
    }

    func stopNow() {
        guard hasPendingWork else { return }
        var discardedItems = buffered + analysisQueue
        if let activeAnalysisCapture {
            discardedItems.append(activeAnalysisCapture)
        }
        var seenCaptureIds = Set<String>()
        discardedItems = discardedItems.filter { item in
            seenCaptureIds.insert(item.record.captureId).inserted
        }
        let discardedCount = discardedItems.count
        captureTask?.cancel()
        processorTask?.cancel()
        captureTask = nil
        processorTask = nil

        if let store {
            for item in discardedItems {
                try? FileManager.default.removeItem(at: item.fileURL)
                var record = item.record
                record.status = .erased
                record.message = "discarded by Stop Now"
                replaceCapture(record)
                try? store.appendCapture(record)
            }
            try? store.appendEvent(kind: "session_interrupted", message: "Stopped immediately; discarded \(discardedCount) buffered, queued, or active captures.")
        }

        buffered.removeAll()
        analysisQueue.removeAll()
        activeAnalysisCapture = nil
        isRecording = false
        isPaused = false
        isStopping = false
        isAnalyzing = false
        totals.analyzing = 0
        totals.erased += discardedCount
        statusLine = "Stopped"
    }

    func clearError() {
        lastError = ""
    }

    func clearScreenPermissionNotice() {
        screenPermissionNotice = ""
    }

    func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private func captureLoop() async {
        while isRecording && !Task.isCancelled {
            if !isPaused {
                await captureOnce()
            }
            let ns = UInt64(max(0.25, config.captureIntervalSeconds) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: ns)
        }
    }

    private func processorLoop() async {
        while !Task.isCancelled {
            releaseDueBufferedCaptures()
            if !isAnalyzing, !analysisQueue.isEmpty {
                let next = analysisQueue.removeFirst()
                await analyze(next)
            }
            if isStopping && buffered.isEmpty && analysisQueue.isEmpty && !isAnalyzing {
                writeSummary(kind: "final_summary")
                try? store?.appendEvent(kind: "session_stopped", message: "Session stopped.")
                isStopping = false
                statusLine = "Stopped"
                return
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    private func captureOnce() async {
        guard let store else { return }
        do {
            let frame = try await captureService.captureFullDisplay(excludingOwnWindows: config.excludeOwnWindows)
            let captureId = "cap_\(Self.fileTimestamp())_\(UUID().uuidString.prefix(8).lowercased())"
            let bufferURL = store.bufferURL(captureId: captureId)
            let data = try writePNG(frame.image, to: bufferURL)
            let signature = diffEngine.signature(image: frame.image, data: data)
            let capturedAt = frame.capturedAt
            let estimate = estimator.estimateRequestCost(
                model: config.model,
                width: frame.image.width,
                height: frame.image.height,
                detail: config.detail
            )
            let record = CaptureRecord(
                captureId: captureId,
                sessionId: sessionId,
                capturedAt: DateFormats.string(from: capturedAt),
                status: .buffered,
                path: bufferURL.path,
                relPath: bufferURL.relativePath(from: store.sessionDir),
                width: frame.image.width,
                height: frame.image.height,
                byteCount: data.count,
                sha256: signature.sha256,
                perceptualHash: signature.perceptualHash,
                ocrFingerprint: signature.ocrFingerprint,
                diffDecision: .firstFrame,
                diffScore: 0,
                estimatedCostUsd: estimate,
                message: "waiting \(Int(config.bufferDelaySeconds))s before inference"
            )
            captures.insert(record, at: 0)
            totals.captured += 1
            try store.appendCapture(record)
            buffered.append(
                BufferedCapture(
                    record: record,
                    fileURL: bufferURL,
                    imageData: data,
                    signature: signature,
                    capturedAt: capturedAt,
                    releaseAt: capturedAt.addingTimeInterval(config.bufferDelaySeconds)
                )
            )
            statusLine = "Buffered \(buffered.count), queued \(analysisQueue.count)"
        } catch {
            handleCaptureFailure(error)
        }
    }

    private func handleCaptureFailure(_ error: Error) {
        let message = error.localizedDescription
        captureTask?.cancel()
        processorTask?.cancel()
        captureTask = nil
        processorTask = nil
        isRecording = false
        isPaused = false
        isStopping = false
        isAnalyzing = false
        activeAnalysisCapture = nil
        totals.analyzing = 0
        buffered.removeAll()
        analysisQueue.removeAll()
        lastError = """
        \(message)

        Recording has stopped so this does not retry in a loop. Grant Screen Recording permission in System Settings, then start again.
        """
        statusLine = "Capture stopped"
        try? store?.appendEvent(kind: "capture_error_stopped", message: message)
    }

    private func releaseDueBufferedCaptures() {
        guard let store else { return }
        let now = Date()
        var due: [BufferedCapture] = []
        buffered.removeAll { item in
            if item.releaseAt <= now {
                due.append(item)
                return true
            }
            return false
        }

        for item in due {
            let secondsSinceLast = lastAnalysisDate.map { now.timeIntervalSince($0) } ?? .greatestFiniteMagnitude
            let decision = diffEngine.decide(
                current: item.signature,
                previousAnalyzed: previousAnalyzedSignature,
                secondsSinceLastAnalysis: secondsSinceLast,
                heartbeatSeconds: config.heartbeatSeconds
            )
            do {
                let retainedURL = try store.retainBufferedCapture(item.fileURL, captureId: item.record.captureId)
                var record = item.record
                record.status = decision.shouldAnalyze ? .queued : .skipped
                record.path = retainedURL.path
                record.relPath = retainedURL.relativePath(from: store.sessionDir)
                record.diffDecision = decision.kind
                record.diffScore = decision.score
                record.message = decision.reason
                replaceCapture(record)
                try store.appendCapture(record)
                let updated = BufferedCapture(
                    record: record,
                    fileURL: retainedURL,
                    imageData: item.imageData,
                    signature: item.signature,
                    capturedAt: item.capturedAt,
                    releaseAt: item.releaseAt
                )
                if decision.shouldAnalyze {
                    analysisQueue.append(updated)
                    totals.queued += 1
                } else {
                    totals.skipped += 1
                }
            } catch {
                lastError = error.localizedDescription
                try? store.appendEvent(kind: "buffer_release_error", message: error.localizedDescription)
            }
        }
    }

    private func analyze(_ item: BufferedCapture) async {
        guard let store, let client = openAIClient else { return }
        isAnalyzing = true
        activeAnalysisCapture = item
        totals.analyzing += 1
        defer {
            totals.analyzing = max(0, totals.analyzing - 1)
            isAnalyzing = false
            activeAnalysisCapture = nil
        }
        var analyzingRecord = item.record
        analyzingRecord.status = .analyzing
        analyzingRecord.message = "OpenAI analysis in progress"
        replaceCapture(analyzingRecord)
        try? store.appendCapture(analyzingRecord)

        do {
            let result = try await client.analyze(
                imageData: item.imageData,
                capture: analyzingRecord,
                config: config,
                rollingContext: rollingContext()
            )
            let observedAt = DateFormats.now()
            let normalizer = ScreenGraphNormalizer(
                sessionId: sessionId,
                captureId: item.record.captureId,
                captureRef: analyzingRecord.relPath,
                observedAt: observedAt,
                model: result.model
            )
            let context = normalizer.normalize(result.draft)
            let actualCost = estimator.actualCost(model: result.model, usage: result.usage)
            let usage = UsageRecord(
                recordId: context.recordId ?? "analysis_\(UUID().uuidString.lowercased())",
                sessionId: sessionId,
                captureId: item.record.captureId,
                model: result.model,
                detail: config.detail.rawValue,
                inputTokens: result.usage.inputTokens,
                cachedInputTokens: result.usage.cachedInputTokens,
                outputTokens: result.usage.outputTokens,
                totalTokens: result.usage.totalTokens,
                estimatedCostUsd: analyzingRecord.estimatedCostUsd,
                actualCostUsd: actualCost,
                createdAt: observedAt
            )
            let envelope = AnalysisEnvelope(
                recordId: usage.recordId,
                recordKind: "screen_graph_hydration",
                sessionId: sessionId,
                captureId: item.record.captureId,
                createdAt: observedAt,
                captureRef: analyzingRecord.relPath,
                imageSha256: item.signature.sha256,
                model: result.model,
                promptVersion: ScreenGraphConstants.promptVersion,
                usage: usage,
                payload: context
            )

            try store.appendUsage(usage)
            try store.appendAnalysis(envelope)
            analyses.insert(envelope, at: 0)
            totals.hydrated += 1
            totals.actualCostUsd += actualCost
            totals.estimatedCostUsd += analyzingRecord.estimatedCostUsd
            previousAnalyzedSignature = item.signature
            lastAnalysisDate = Date()

            var hydratedRecord = analyzingRecord
            hydratedRecord.status = .hydrated
            hydratedRecord.message = context.operatorSummary.isEmpty ? "hydrated" : context.operatorSummary
            replaceCapture(hydratedRecord)
            try store.appendCapture(hydratedRecord)
            maybeWritePeriodicSummary()
            statusLine = "Hydrated \(totals.hydrated), skipped \(totals.skipped)"
        } catch {
            if Task.isCancelled {
                try? store.appendEvent(kind: "analysis_cancelled", message: "Cancelled analysis for \(item.record.captureId).")
                return
            }
            var failedRecord = analyzingRecord
            failedRecord.status = .failed
            failedRecord.message = error.localizedDescription
            replaceCapture(failedRecord)
            try? store.appendCapture(failedRecord)
            try? store.appendEvent(kind: "analysis_error", message: error.localizedDescription)
            totals.failed += 1
            lastError = error.localizedDescription
            statusLine = "Analysis failed"
        }
    }

    private func maybeWritePeriodicSummary() {
        let now = Date()
        guard let last = lastSummaryDate else {
            lastSummaryDate = now
            return
        }
        if now.timeIntervalSince(last) >= 60 {
            writeSummary(kind: "periodic_summary")
            lastSummaryDate = now
        }
    }

    private func writeSummary(kind: String) {
        guard let store else { return }
        let summaryLines = analyses.prefix(12).reversed().map { envelope in
            "- \(envelope.payload.operatorSummary)"
        }
        let summaryText = summaryLines.isEmpty ? "No analyzed frames yet." : summaryLines.joined(separator: "\n")
        let record = SummaryRecord(
            summaryId: "\(kind)_\(UUID().uuidString.lowercased())",
            sessionId: sessionId,
            kind: kind,
            createdAt: DateFormats.now(),
            analyzedCaptureCount: analyses.count,
            summary: summaryText
        )
        summaries.insert(record, at: 0)
        try? store.appendSummary(record)
    }

    private func rollingContext() -> String {
        analyses.prefix(8).reversed().map { envelope in
            let payload = envelope.payload
            let subject = payload.subject.canonicalName.isEmpty ? payload.subject.oneLineIdentity : payload.subject.canonicalName
            let claims = payload.claims.prefix(3).map(\.claim).joined(separator: "; ")
            return """
            Capture \(envelope.captureId):
            summary: \(payload.operatorSummary)
            subject: \(subject)
            claims: \(claims)
            """
        }.joined(separator: "\n\n")
    }

    private func replaceCapture(_ record: CaptureRecord) {
        if let index = captures.firstIndex(where: { $0.captureId == record.captureId }) {
            captures[index] = record
        } else {
            captures.insert(record, at: 0)
        }
    }

    private func resetSessionView() {
        sessionId = ""
        sessionDirectory = ""
        captures.removeAll()
        analyses.removeAll()
        summaries.removeAll()
        buffered.removeAll()
        analysisQueue.removeAll()
        activeAnalysisCapture = nil
        totals = SessionTotals()
        previousAnalyzedSignature = nil
        lastAnalysisDate = nil
        lastSummaryDate = nil
        store = nil
        openAIClient = nil
        isRecording = false
        isPaused = false
        isStopping = false
        isAnalyzing = false
    }

    private static func fileTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: Date())
    }
}
