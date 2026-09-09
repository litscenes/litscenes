import SwiftUI
import AppKit

struct WorkflowLogsPanel: View {
    @ObservedObject var workspace: ProjectWorkspaceCoordinator
    @ObservedObject private var workflows = WorkflowCoordinator.shared
    @State private var events: [WorkflowEvent] = []
    @State private var traceDetails = ""
    @State private var traces: [WorkflowTraceRecord] = []
    @State private var summaries: [WorkflowLogEvidence] = []
    @State private var showVersions = false
    @State private var reviewingId: String?

    private var filteredJobs: [WorkflowJob] {
        workflows.jobs.filter { job in
            (workflows.projectFilter.isEmpty || job.projectId == workflows.projectFilter)
                && (workflows.statusFilter.isEmpty || job.state.rawValue == workflows.statusFilter)
                && (workflows.providerFilter.isEmpty || job.provider == workflows.providerFilter)
                && (workflows.workflowFilter.isEmpty || job.workflow == workflows.workflowFilter)
                && workflowMatchesSearch(job, query: workflows.search)
        }.sorted {
            if $0.state.isTerminal != $1.state.isTerminal { return !$0.state.isTerminal }
            return $0.createdAt > $1.createdAt
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("LOGS").font(CanonType.interface(14, weight: .semibold)).tracking(1.8)
                Text("\(workflows.runningCount) running · \(workflows.jobs.filter { $0.state == .queued }.count) queued")
                    .font(CanonType.interface(11)).foregroundStyle(CanonColor.ink.opacity(0.55))
                Spacer()
                Button { workflows.showingLogs = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).help("Close Logs")
            }.padding(16)
            filters.padding(.horizontal, 16).padding(.bottom, 12)
            Divider()
            if !workflows.historyError.isEmpty {
                Text(workflows.historyError).font(CanonType.interface(12)).foregroundStyle(CanonColor.rust).padding(12)
            }
            ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if filteredJobs.isEmpty {
                        Text("No activity matches these filters.").font(CanonType.editorial(14))
                            .foregroundStyle(CanonColor.ink.opacity(0.55)).padding(.vertical, 24)
                    }
                    ForEach(filteredJobs) { job in
                        jobRow(job).id(job.id)
                    }
                    Button("Load more history") { Task { await workflows.loadMore() } }
                        .buttonStyle(.plain).font(CanonType.interface(11)).padding(.vertical, 12)
                    if !workflows.projectFilter.isEmpty {
                        DisclosureGroup("Scene Plan versions", isExpanded: $showVersions) {
                            ForEach(workspace.versions(projectId: workflows.projectFilter), id: \.versionId) { version in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(version.changeSummary.isEmpty ? "Saved Scene Plan" : version.changeSummary)
                                    Text("\(version.createdAt) · \(version.model)")
                                        .font(CanonType.archive(10)).foregroundStyle(CanonColor.ink.opacity(0.5))
                                }.font(CanonType.interface(12)).padding(.vertical, 5)
                            }
                        }.font(CanonType.interface(12, weight: .semibold)).padding(.top, 10)
                    }
                    Text("History starts with recorded work. Older memory-only logs are unavailable.")
                        .font(CanonType.interface(10)).foregroundStyle(CanonColor.ink.opacity(0.4)).padding(.top, 12)
                }.padding(16)
            }
            .onChange(of: workflows.selectedLogId, initial: true) { _, id in
                if let id { proxy.scrollTo(id, anchor: .top) }
            }
            .onChange(of: filteredJobs.map(\.id)) { _, _ in
                if let id = workflows.selectedLogId { proxy.scrollTo(id, anchor: .top) }
            }
            }
        }
        .foregroundStyle(CanonColor.ink)
        .background(CanonColor.paper)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(CanonColor.brass.opacity(0.35)))
        .onExitCommand { workflows.showingLogs = false }
        .task(id: [workflows.projectFilter, workflows.statusFilter, workflows.providerFilter, workflows.workflowFilter, workflows.search]) {
            await workflows.refreshHistory()
        }
        .task(id: "\(filteredJobs.map(\.id).joined(separator: ",")):\(workflows.eventRevision)") {
            let values = (try? await InferenceTraceStore.shared.workflowLogSummaries(jobIds: filteredJobs.map(\.id))) ?? []
            if !Task.isCancelled { summaries = values }
        }
        .task(id: "\(workflows.selectedLogId ?? ""):\(workflows.eventRevision)") {
            events = []; traceDetails = ""; traces = []
            guard let id = workflows.selectedLogId, let job = workflows.jobs.first(where: { $0.id == id }) else { return }
            let loaded = (try? await InferenceTraceStore.shared.workflowEvents(jobId: id)) ?? []
            let ids = Array(Set(job.traceIds + loaded.map(\.traceId).filter { !$0.isEmpty }))
            let records = ((try? await InferenceTraceStore.shared.workflowTraceRecords(ids: ids)) ?? []).sorted { $0.createdAt < $1.createdAt }
            let details = records.map(\.rawJSON).joined(separator: "\n\n")
            guard !Task.isCancelled, workflows.selectedLogId == id else { return }
            events = loaded; traceDetails = details; traces = records
        }
    }

    private var filters: some View {
        VStack(spacing: 8) {
            TextField("Search activity", text: $workflows.search).textFieldStyle(.roundedBorder)
            HStack(spacing: 8) {
                Picker("Project", selection: $workflows.projectFilter) {
                    Text("All projects").tag("")
                    ForEach(workspace.projects) { project in Text(project.name).tag(project.projectId) }
                }
                Picker("Status", selection: $workflows.statusFilter) {
                    Text("All states").tag("")
                    ForEach(WorkflowState.allCases, id: \.self) { Text($0.label).tag($0.rawValue) }
                }
                Picker("Provider", selection: $workflows.providerFilter) {
                    Text("All providers").tag("")
                    ForEach(Array(Set(workflows.jobs.map(\.provider).filter { !$0.isEmpty })).sorted(), id: \.self) { Text($0).tag($0) }
                }
                Picker("Workflow", selection: $workflows.workflowFilter) {
                    Text("All workflows").tag("")
                    ForEach(Array(Set(workflows.jobs.map(\.workflow))).sorted(), id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ")).tag($0) }
                }
            }.labelsHidden().font(CanonType.interface(11))
        }
    }

    private func jobRow(_ job: WorkflowJob) -> some View {
        let expanded = workflows.selectedLogId == job.id
        let outcome = workflowOutcomeLabel(job, evidence: summaries.first { $0.jobId == job.id })
        let artifact = workspace.artifactLabel(for: job)
        return VStack(alignment: .leading, spacing: 8) {
            Button { workflows.selectedLogId = expanded ? nil : job.id } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold)).frame(width: 10).padding(.top, 4)
                    Circle().fill(color(job.state)).frame(width: 7, height: 7).padding(.top, 5)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(job.label + (artifact.isEmpty ? "" : " · " + artifact))
                                .font(CanonType.interface(12, weight: .semibold))
                            Spacer()
                            Text(job.state.label).font(CanonType.archive(10)).foregroundStyle(color(job.state))
                        }
                        Text(outcome).font(CanonType.interface(11)).lineLimit(expanded ? nil : 2)
                        if !summarySettings(job).isEmpty {
                            Text(summarySettings(job)).font(CanonType.interface(10)).foregroundStyle(CanonColor.ink.opacity(0.65))
                        }
                        Text("\(job.projectName) · \(workflowLocalDate(job.createdAt)) · \(workflowElapsed(job)) elapsed")
                            .font(CanonType.archive(9)).foregroundStyle(CanonColor.ink.opacity(0.5))
                    }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            if expanded {
                Divider()
                detailActions(job, outcome: outcome)
                logFields("Inputs", fields: uniqueFields(workflowLogFields(job.recipeJSON, output: false) + traces.flatMap(\.inputFields)))
                if job.workflow == "shot_prompt_assistance" {
                    Text("Generated direction is recorded here. Applying it is a separate editor action.")
                        .font(CanonType.interface(10)).foregroundStyle(CanonColor.ink.opacity(0.6))
                }
                logFields(job.state == .failed ? "Failure" : "Result", fields:
                    [WorkflowLogField(label: job.state.label, value: outcome)] + uniqueFields(traces.flatMap(\.outputFields)))
                artifactPreviews(job)
                DisclosureGroup("Activity (\(events.count) events · \(traces.count) requests)") {
                    ForEach(activityRows) { field in
                        Text(field.value).font(CanonType.interface(10)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 2)
                    }
                }.font(CanonType.interface(11, weight: .semibold))
                DisclosureGroup("Technical details", isExpanded: Binding(
                    get: { reviewingId == job.id }, set: { reviewingId = $0 ? job.id : nil })) {
                    Text("Job: \(job.id)\nArtifact: \(job.artifactId)\nProvider request: \(job.providerRequestId.nilIfEmpty ?? "Not recorded")")
                        .font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                    if !job.recipeJSON.isEmpty {
                        DisclosureGroup("Saved request") { technicalText(job.recipeJSON) }
                    }
                    ForEach(traces) { trace in
                        DisclosureGroup("\(trace.operation) · HTTP \(trace.status) · \(trace.milliseconds)ms") {
                            technicalText(trace.rawJSON)
                        }
                    }
                    DisclosureGroup("All events") {
                        ForEach(events) { event in
                            technicalText("\(event.timestamp) · \(event.phase) · \(event.message)")
                        }
                    }
                }.font(CanonType.interface(11))
            }
        }
        .padding(12)
        .background(CanonColor.paperInset.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }

    private func summarySettings(_ job: WorkflowJob) -> String {
        let seconds = job.segmentProgress?.filter(\.isGeneration).map(\.durationSeconds)
            ?? (job.spendEntries ?? []).filter { $0.unit == "seconds" }.map(\.unitCount)
        let duration = seconds.isEmpty ? "" : seconds.map { "\(Int($0.rounded()))s" }.joined(separator: " + ") + " requested"
        return [workflowProviderLabel(job.provider), workflowModelLabel(job), duration, workflowCostLabel(job)]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func detailActions(_ job: WorkflowJob, outcome: String) -> some View {
        ShotEditorFlow(spacing: 14) {
            Button("Copy details") {
                let details = "\(job.label) · \(workspace.artifactLabel(for: job))\n\(outcome)\n\(summarySettings(job))\n\(workflowLocalDate(job.createdAt)) · \(workflowElapsed(job)) elapsed\n\n\(WorkflowPrivacy.json(job.recipeJSON))\n\n\(traceDetails)\n\n"
                    + events.map { "\($0.timestamp) · \($0.phase) · \($0.message)" }.joined(separator: "\n")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(WorkflowPrivacy.text(details), forType: .string)
            }
            if let owner = workspace.engine(for: job), owner.canCheckWorkflowJob(job) {
                Button("Check existing job") { owner.checkWorkflowJob(job) }
            }
            if workspace.projects.contains(where: { $0.projectId == job.projectId }) {
                Button(job.artifactType == "shot" ? "Open Shot" : "Open item") { workspace.open(job) }
            }
            if job.state == .queued || job.state == .pausedAutomatically {
                Button("Cancel") { Task { await workflows.cancel(job.id) } }
            }
            if job.state == .running {
                Button("Stop after this step") { Task { await workflows.cancel(job.id) } }
            }
            if job.state == .pausedAutomatically {
                Button(workflows.canContinue(job) ? "Continue vendor queue" : "Review request") {
                    if workflows.canContinue(job) { Task { await workflows.continueJob(job) } }
                    else { reviewingId = job.id }
                }
            }
        }.buttonStyle(.plain).font(CanonType.interface(11, weight: .semibold)).foregroundStyle(CanonColor.brass)
    }

    private func technicalText(_ text: String) -> some View {
        Text(WorkflowPrivacy.text(text)).font(.system(size: 10, design: .monospaced))
            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func uniqueFields(_ fields: [WorkflowLogField]) -> [WorkflowLogField] {
        var seen: Set<String> = []
        return fields.filter { seen.insert($0.id).inserted }
    }

    @ViewBuilder
    private func logFields(_ title: String, fields: [WorkflowLogField]) -> some View {
        if !fields.isEmpty {
            DisclosureGroup(title) {
                ForEach(fields) { field in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(field.label).font(CanonType.interface(10, weight: .semibold))
                        Text(field.value).font(CanonType.interface(11)).textSelection(.enabled)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                }
            }.font(CanonType.interface(11, weight: .semibold))
        }
    }

    private var activityRows: [WorkflowLogField] {
        var fields: [WorkflowLogField] = []
        var responseCount = 0
        for event in events {
            if event.message == "Provider response received" { responseCount += 1; continue }
            if event.message.isEmpty && event.segment == nil { continue }
            fields.append(WorkflowLogField(label: event.id, value:
                "\(workflowLocalDate(event.timestamp)) · \(event.segment?.label ?? event.message)"))
        }
        if responseCount > 0 { fields.append(WorkflowLogField(label: "responses", value: "\(responseCount) provider responses; individual requests are in Technical details.")) }
        return fields
    }

    @ViewBuilder
    private func artifactPreviews(_ job: WorkflowJob) -> some View {
        if let engine = workspace.engine(for: job),
           let shot = engine.shotTimeline.shots.first(where: { $0.shotId == job.artifactId }) {
            let takes = shot.continuationRecords.flatMap(\.takes).filter { take in
                job.segmentProgress?.contains(where: { $0.takeId == take.takeId }) == true
            }
            let frameIds = (job.segmentProgress ?? []).flatMap { $0.inputFrameIds ?? [] }
            let sourcePaths = frameIds.compactMap { engine.projectWideFrameLookup[$0]?.imagePath }
                + takes.flatMap { [$0.anchor.framePath, $0.targetFrame?.imagePath ?? ""] }
            let paths = NSOrderedSet(array: sourcePaths.filter { !$0.isEmpty }).array.compactMap { $0 as? String }
            if !paths.isEmpty {
                DisclosureGroup("Input Frames") {
                    ShotEditorFlow {
                        ForEach(paths, id: \.self) { path in
                            if let image = StripThumbnailCache.shared.image(path: path) {
                                Image(nsImage: image).resizable().scaledToFit().frame(width: 128, height: 72)
                            }
                        }
                    }
                }.font(CanonType.interface(11, weight: .semibold))
            }
            let versionIds = Set((job.segmentProgress ?? []).map(\.versionId).filter { !$0.isEmpty })
            let clips = shot.renderVersions.filter { versionIds.contains($0.versionId) }.flatMap(\.segmentClips)
                + takes.compactMap(\.segmentClip)
            if !clips.isEmpty {
                DisclosureGroup("Saved video") {
                    ShotEditorFlow {
                        ForEach(Array(clips.enumerated()), id: \.offset) { _, clip in
                            ShotSegmentVideoThumbnail(preview: ShotSegmentPreview(clip: clip))
                        }
                    }
                }.font(CanonType.interface(11, weight: .semibold))
            }
        }
    }

    private func color(_ state: WorkflowState) -> Color {
        switch state {
        case .failed: return CanonColor.rust
        case .pausedAutomatically, .stopping: return CanonColor.brass
        case .succeeded: return CanonColor.olive
        default: return CanonColor.ink.opacity(0.5)
        }
    }
}
