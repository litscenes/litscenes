import SwiftUI

struct WorkflowLogsPanel: View {
    @ObservedObject var workspace: ProjectWorkspaceCoordinator
    @ObservedObject private var workflows = WorkflowCoordinator.shared
    @State private var events: [WorkflowEvent] = []
    @State private var traceDetails = ""
    @State private var showVersions = false
    @State private var reviewingId: String?

    private var filteredJobs: [WorkflowJob] {
        workflows.jobs.filter { job in
            (workflows.projectFilter.isEmpty || job.projectId == workflows.projectFilter)
                && (workflows.statusFilter.isEmpty || job.state.rawValue == workflows.statusFilter)
                && (workflows.providerFilter.isEmpty || job.provider == workflows.providerFilter)
                && (workflows.workflowFilter.isEmpty || job.workflow == workflows.workflowFilter)
                && (workflows.search.isEmpty || "\(job.label) \(job.projectName) \(job.artifactId) \(job.reason) \(job.model)".localizedCaseInsensitiveContains(workflows.search))
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
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if filteredJobs.isEmpty {
                        Text("No activity matches these filters.").font(CanonType.editorial(14))
                            .foregroundStyle(CanonColor.ink.opacity(0.55)).padding(.vertical, 24)
                    }
                    ForEach(filteredJobs) { job in
                        jobRow(job)
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
        }
        .foregroundStyle(CanonColor.ink)
        .background(CanonColor.paper)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(CanonColor.brass.opacity(0.35)))
        .onExitCommand { workflows.showingLogs = false }
        .task(id: [workflows.projectFilter, workflows.statusFilter, workflows.providerFilter, workflows.workflowFilter, workflows.search]) {
            await workflows.refreshHistory()
        }
        .task(id: "\(workflows.selectedLogId ?? ""):\(workflows.eventRevision)") {
            events = []; traceDetails = ""
            guard let id = workflows.selectedLogId, let job = workflows.jobs.first(where: { $0.id == id }) else { return }
            let loaded = (try? await InferenceTraceStore.shared.workflowEvents(jobId: id)) ?? []
            let details = (try? await InferenceTraceStore.shared.workflowTraceDetails(ids: job.traceIds)) ?? ""
            guard !Task.isCancelled, workflows.selectedLogId == id else { return }
            events = loaded; traceDetails = details
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
        VStack(alignment: .leading, spacing: 8) {
            Button {
                workflows.selectedLogId = workflows.selectedLogId == job.id ? nil : job.id
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(color(job.state)).frame(width: 7, height: 7).padding(.top, 5)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(job.label).font(CanonType.interface(12, weight: .semibold))
                            Spacer()
                            Text(job.state.label).font(CanonType.archive(10)).foregroundStyle(color(job.state))
                        }
                        Text("\(job.projectName) · \(job.phase)").font(CanonType.interface(11))
                            .foregroundStyle(CanonColor.ink.opacity(0.65))
                        if !job.reason.isEmpty {
                            Text(WorkflowPrivacy.text(job.reason)).font(CanonType.interface(11))
                                .foregroundStyle(CanonColor.ink.opacity(0.65)).lineLimit(workflows.selectedLogId == job.id ? nil : 2)
                        }
                        Text(job.updatedAt).font(CanonType.archive(9)).foregroundStyle(CanonColor.ink.opacity(0.4))
                    }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            if workflows.selectedLogId == job.id {
                Divider()
                if !job.provider.isEmpty { Text("\(job.provider) · \(job.model)").font(CanonType.interface(11)) }
                if !job.providerRequestId.isEmpty {
                    Text("Provider request: " + job.providerRequestId).font(CanonType.archive(10)).textSelection(.enabled)
                }
                ForEach(job.spendEntries ?? []) { entry in
                    Text(entry.estimatedUSD.map { String(format: "Estimated $%.4f", $0) } ?? "Cost unavailable")
                        .font(CanonType.archive(10))
                    if !entry.pricingNote.isEmpty { Text(entry.pricingNote).font(CanonType.archive(10)) }
                }
                HStack(spacing: 14) {
                    if workspace.current.canCheckWorkflowJob(job) {
                        Button("Check existing job") { workspace.current.checkWorkflowJob(job) }
                    }
                    if !job.projectId.isEmpty { Button("Open item") { workspace.open(job) } }
                    if job.state == .queued || job.state == .pausedAutomatically {
                        Button("Cancel") { Task { await workflows.cancel(job.id) } }
                    }
                    if job.state == .running { Button("Stop after this step") { Task { await workflows.cancel(job.id) } } }
                    if job.state == .pausedAutomatically {
                        Button(workflows.canContinue(job) ? "Continue vendor queue" : "Review request") {
                            if workflows.canContinue(job) { Task { await workflows.continueJob(job) } }
                            else { reviewingId = job.id }
                        }
                    }
                }.buttonStyle(.plain).font(CanonType.interface(11, weight: .semibold)).foregroundStyle(CanonColor.brass)
                ForEach(events) { event in
                    Text("\(event.timestamp)  \(event.phase)\(event.message.isEmpty ? "" : " — \(WorkflowPrivacy.text(event.message))")")
                        .font(CanonType.archive(10)).textSelection(.enabled)
                }
                if !job.recipeJSON.isEmpty {
                    DisclosureGroup("Saved request", isExpanded: Binding(
                        get: { reviewingId == job.id }, set: { reviewingId = $0 ? job.id : nil }
                    )) {
                        if job.requiresReview {
                            Text("Open the item to review its current inputs and price before another paid attempt. Unknown provider acceptance must be checked first.")
                                .font(CanonType.interface(11))
                        }
                        Text(WorkflowPrivacy.json(job.recipeJSON)).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    }
                }
                if !traceDetails.isEmpty {
                    DisclosureGroup("Prompts and trace details") { Text(traceDetails).font(.system(size: 11, design: .monospaced)).textSelection(.enabled) }
                }
            }
        }
        .padding(12)
        .background(CanonColor.paperInset.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
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
