import Foundation
import SwiftUI

@MainActor
final class ProjectWorkspaceCoordinator: ObservableObject {
    struct Session: Identifiable {
        let id: String
        let engine: LibraryEngine
    }
    @Published private(set) var sessions: [Session] = []
    @Published private(set) var selectedProjectId = ""
    private let projectLibrary: ProjectLibrary

    init(projectLibrary: ProjectLibrary = ProjectLibrary()) {
        self.projectLibrary = projectLibrary
        let engine = LibraryEngine(projectLibrary: projectLibrary)
        attach(engine)
        selectedProjectId = engine.currentProject?.projectId ?? ""
    }

    var current: LibraryEngine { sessions.first { $0.id == selectedProjectId }?.engine ?? sessions[0].engine }
    var projects: [ProjectRecord] { current.projects }

    private func attach(_ engine: LibraryEngine) {
        engine.retainsProjectRuntime = true
        engine.projectSelectionHandler = { [weak self] project in self?.select(project) }
        sessions.append(Session(id: engine.currentProject?.projectId ?? "", engine: engine))
    }

    func select(_ project: ProjectRecord) {
        guard selectedProjectId != project.projectId else { return }
        current.stopPlaybackForWorkspaceSwitch()
        if !sessions.contains(where: { $0.id == project.projectId }) {
            attach(LibraryEngine(projectLibrary: projectLibrary, project: project))
        }
        selectedProjectId = project.projectId
        for session in sessions { session.engine.refreshProjectRegistry() }
    }

    func open(_ job: WorkflowJob) {
        guard let project = projects.first(where: { $0.projectId == job.projectId }) else { return }
        select(project)
        WorkflowCoordinator.shared.pendingOpenJob = job
        WorkflowCoordinator.shared.showingLogs = false
    }

    func engine(for job: WorkflowJob) -> LibraryEngine? {
        sessions.first { $0.id == job.projectId }?.engine
    }

    func artifactLabel(for job: WorkflowJob) -> String {
        if let label = job.artifactLabel, !label.isEmpty { return label }
        guard let engine = engine(for: job) else { return job.artifactType.capitalized }
        if let shot = engine.shotTimeline.shots.first(where: { $0.shotId == job.artifactId }) {
            return shot.name.trimmed.nilIfEmpty ?? "Untitled Shot"
        }
        if let frame = engine.projectWideFrameLookup[job.artifactId] { return frame.label.trimmed.nilIfEmpty ?? "Frame" }
        return engine.items.first { $0.mediaId == job.artifactId }?.filename ?? job.artifactType.capitalized
    }

    func versions(projectId: String) -> [ProjectLensBodyVersion] {
        guard let project = projects.first(where: { $0.projectId == projectId }) else { return [] }
        let lenses = sessions.first(where: { $0.id == projectId })?.engine.projectLenses
            ?? ProjectContextStore(projectLibrary: projectLibrary).loadProjectLenses(for: project)
        return lenses.lenses.flatMap { lenses.bodyVersions(for: $0.lensId) }.sorted { $0.createdAt > $1.createdAt }
    }

    func prepareToQuit() async {
        await WorkflowCoordinator.shared.checkpointForTermination()
        for session in sessions { await session.engine.flushOperationalWrites() }
    }
}

struct WorkspaceNavigationBoundsKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

struct ProjectWorkspaceHost: View {
    @ObservedObject var workspace: ProjectWorkspaceCoordinator
    @ObservedObject var recorder: RecorderEngine
    @ObservedObject var sessionRecorder: SessionRecorder
    @ObservedObject private var workflows = WorkflowCoordinator.shared

    var body: some View {
        ZStack {
            // Stable identities retain drafts, modal state and selections for every visited project.
            ForEach(workspace.sessions) { session in
                LibraryRootView(library: session.engine, recorder: recorder, sessionRecorder: sessionRecorder)
                    .opacity(session.id == workspace.selectedProjectId ? 1 : 0)
                    .allowsHitTesting(session.id == workspace.selectedProjectId)
                    .accessibilityHidden(session.id != workspace.selectedProjectId)
            }
        }
        .overlayPreferenceValue(WorkspaceNavigationBoundsKey.self) { anchors in
            GeometryReader { geometry in
                if workflows.showingLogs {
                    let top = anchors[workspace.selectedProjectId].map { geometry[$0].maxY } ?? 0
                    let available = max(0, geometry.size.height - top - 12)
                    WorkflowLogsPanel(workspace: workspace)
                        .frame(width: geometry.size.width * 0.60, height: available * 0.90)
                        .shadow(color: .black.opacity(0.28), radius: 18, x: -4, y: 5)
                        .padding(.top, top)
                        .padding(.trailing, 12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .animation(.easeOut(duration: 0.18), value: workflows.showingLogs)
        .task { await workflows.bootstrap() }
    }
}
