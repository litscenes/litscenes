import AppKit
import Foundation

struct VideoChainLoadIssue: Hashable, Identifiable {
    var id: String { path }
    var path: String
    var message: String
}

struct VideoChainLoadResult: Hashable {
    var chains: [VideoChainDocument]
    var issues: [VideoChainLoadIssue]
}

enum CreativeSchemaCompatibilityState: Hashable {
    case ready
    case needsBootstrap
    case incompatible([String])

    var isIncompatible: Bool {
        if case .incompatible = self { return true }
        return false
    }

    var reasons: [String] {
        if case .incompatible(let reasons) = self { return reasons }
        return []
    }
}

struct CreativeDataResetResult: Hashable {
    var archivedPaths: [String]
    var archiveDirectory: String?
}

struct ProjectContextStore {
    let projectLibrary: ProjectLibrary

    init(projectLibrary: ProjectLibrary = ProjectLibrary()) {
        self.projectLibrary = projectLibrary
    }

    private var storySQLiteStore: ProjectStorySQLiteStore {
        ProjectStorySQLiteStore(projectLibrary: projectLibrary)
    }

    private var documentStore: ProjectSQLiteDocumentStore {
        ProjectSQLiteDocumentStore(projectLibrary: projectLibrary)
    }

    private var mediaSQLiteStore: ProjectMediaSQLiteStore {
        ProjectMediaSQLiteStore(projectLibrary: projectLibrary)
    }

    private var goalSQLiteStore: ProjectGoalSQLiteStore {
        ProjectGoalSQLiteStore(projectLibrary: projectLibrary)
    }

    private var lensSQLiteStore: ProjectLensSQLiteStore {
        ProjectLensSQLiteStore(projectLibrary: projectLibrary)
    }

    private func loadDBDocument<T: Decodable>(
        _ type: T.Type,
        for project: ProjectRecord,
        documentType: String,
        documentId: String = "default"
    ) -> T? {
        try? documentStore.loadDocument(type, for: project, documentType: documentType, documentId: documentId)
    }

    private func loadDBDocuments<T: Decodable>(
        _ type: T.Type,
        for project: ProjectRecord,
        documentType: String
    ) -> [T] {
        (try? documentStore.loadDocuments(type, for: project, documentType: documentType)) ?? []
    }

    private func saveDBDocument<T: Encodable>(
        _ value: T,
        for project: ProjectRecord,
        documentType: String,
        documentId: String = "default"
    ) throws {
        try documentStore.saveDocument(value, for: project, documentType: documentType, documentId: documentId)
    }

    private func loadDBDocumentData(
        for project: ProjectRecord,
        documentType: String,
        documentId: String = "default"
    ) -> Data? {
        try? documentStore.loadDocumentData(for: project, documentType: documentType, documentId: documentId)
    }

    private func saveDBDocumentData(
        _ data: Data,
        for project: ProjectRecord,
        documentType: String,
        documentId: String = "default"
    ) throws {
        try documentStore.saveDocumentData(data, for: project, documentType: documentType, documentId: documentId)
    }

    func storyDirectory(for project: ProjectRecord) -> URL {
        projectLibrary.projectDirectory(for: project).appendingPathComponent("story", isDirectory: true)
    }

    func shotAudioDirectory(for project: ProjectRecord, shotId: String) -> URL {
        storyDirectory(for: project)
            .appendingPathComponent("shot_audio", isDirectory: true)
            .appendingPathComponent(safeIdentifier(shotId), isDirectory: true)
    }

    /// Baked reversed copies of clips, shared across every shot in the project
    /// because they are addressed by source-file identity.
    ///
    /// Project-local rather than temporary: a reverse toggle has to survive
    /// relaunch without re-spending minutes of encode, and these travel with the
    /// project. (Join-bridge preview stills live in the temp directory because
    /// they are two PNGs; these are multi-megabyte encodes.)
    func reverseProxyDirectory(for project: ProjectRecord) -> URL {
        storyDirectory(for: project).appendingPathComponent("reverse_proxies", isDirectory: true)
    }

    /// THE FINALS REEL's per-cut bake cache: `<fingerprint>.mp4` beside a
    /// tolerant `<fingerprint>.json` sidecar. Project-local like the reverse
    /// proxies — derived, sweepable, never source media.
    func reelBakeDirectory(for project: ProjectRecord) -> URL {
        storyDirectory(for: project).appendingPathComponent("reel_bakes", isDirectory: true)
    }

    func storyWorldURL(for project: ProjectRecord) -> URL {
        storyDirectory(for: project).appendingPathComponent("story_world.json")
    }

    func sourceContextURL(for project: ProjectRecord) -> URL {
        storyDirectory(for: project).appendingPathComponent("source_context.json")
    }

    func visionUIPreferencesURL(for project: ProjectRecord) -> URL {
        storyDirectory(for: project).appendingPathComponent("vision_ui.json")
    }

    func projectAestheticURL(for project: ProjectRecord) -> URL {
        storyDirectory(for: project).appendingPathComponent("project_aesthetic.json")
    }

    func aestheticBriefURL(for project: ProjectRecord) -> URL {
        storyDirectory(for: project).appendingPathComponent("aesthetic_brief.json")
    }

    func aestheticWheelURL(for project: ProjectRecord) -> URL {
        storyDirectory(for: project).appendingPathComponent("aesthetic_wheel.json")
    }

    func aestheticProofDirectory(for project: ProjectRecord) -> URL {
        storyDirectory(for: project).appendingPathComponent("aesthetic_proofs", isDirectory: true)
    }

    func aestheticProofSheetURL(for project: ProjectRecord) -> URL {
        storyDirectory(for: project).appendingPathComponent("aesthetic_proof_sheets.json")
    }

    func aestheticDirectionCompositesURL(for project: ProjectRecord) -> URL {
        storyDirectory(for: project).appendingPathComponent("aesthetic_direction_composites.json")
    }

    func aestheticEvidenceProfileURL(for project: ProjectRecord) -> URL {
        storyDirectory(for: project).appendingPathComponent("aesthetic_evidence_profile.json")
    }

    func aestheticDirectionSelectionURL(for project: ProjectRecord) -> URL {
        storyDirectory(for: project).appendingPathComponent("aesthetic_direction_selection.json")
    }

    func projectGoalURL(for project: ProjectRecord) -> URL {
        storyDirectory(for: project).appendingPathComponent("project_goal.json")
    }

    func lensContextURL(for project: ProjectRecord) -> URL {
        storyDirectory(for: project).appendingPathComponent("lens_context.json")
    }

    func projectLensesURL(for project: ProjectRecord) -> URL {
        storyDirectory(for: project).appendingPathComponent("project_lenses.json")
    }

    func sceneStoriesDirectory(for project: ProjectRecord) -> URL {
        storyDirectory(for: project).appendingPathComponent("scene_stories", isDirectory: true)
    }

    func sceneStorySetURL(for project: ProjectRecord, sceneStorySetId: String) -> URL {
        sceneStoriesDirectory(for: project).appendingPathComponent("\(safeIdentifier(sceneStorySetId)).json")
    }

    func storyGenerationSessionsDirectory(for project: ProjectRecord) -> URL {
        storyDirectory(for: project).appendingPathComponent("story_generation_sessions", isDirectory: true)
    }

    func storyGenerationRequestsDirectory(for project: ProjectRecord, generationSessionId: String) -> URL {
        storyDirectory(for: project)
            .appendingPathComponent("story_generation_requests", isDirectory: true)
            .appendingPathComponent(safeIdentifier(generationSessionId), isDirectory: true)
    }

    func storyGenerationSessionURL(for project: ProjectRecord, generationSessionId: String) -> URL {
        storyGenerationSessionsDirectory(for: project).appendingPathComponent("\(safeIdentifier(generationSessionId)).json")
    }

    func storyGenerationRequestURL(for project: ProjectRecord, generationSessionId: String, slotIndex: Int, attemptIndex: Int) -> URL {
        storyGenerationRequestsDirectory(for: project, generationSessionId: generationSessionId)
            .appendingPathComponent("slot_\(max(slotIndex, 1))_attempt_\(max(attemptIndex, 1)).request.json")
    }

    func projectStoryLibraryURL(for project: ProjectRecord) -> URL {
        storyDirectory(for: project).appendingPathComponent("story_library.json")
    }

    func storySignaturesDirectory(for project: ProjectRecord) -> URL {
        storyDirectory(for: project).appendingPathComponent("story_signatures", isDirectory: true)
    }

    func storySignatureURL(for project: ProjectRecord, storySignatureId: String) -> URL {
        storySignaturesDirectory(for: project).appendingPathComponent("\(safeIdentifier(storySignatureId)).json")
    }

    func projectStoriesDirectory(for project: ProjectRecord) -> URL {
        storyDirectory(for: project).appendingPathComponent("stories", isDirectory: true)
    }

    func projectStoryVersionsDirectory(for project: ProjectRecord, projectStoryId: String) -> URL {
        projectStoriesDirectory(for: project)
            .appendingPathComponent(safeIdentifier(projectStoryId), isDirectory: true)
            .appendingPathComponent("versions", isDirectory: true)
    }

    func projectStoryVersionURL(for project: ProjectRecord, projectStoryId: String, storyVersionId: String) -> URL {
        projectStoryVersionsDirectory(for: project, projectStoryId: projectStoryId)
            .appendingPathComponent("\(safeIdentifier(storyVersionId)).json")
    }

    func storyTakesDirectory(for project: ProjectRecord) -> URL {
        storyDirectory(for: project).appendingPathComponent("takes", isDirectory: true)
    }

    func storyTakeURL(for project: ProjectRecord, takeId: String) -> URL {
        storyTakesDirectory(for: project).appendingPathComponent("\(safeIdentifier(takeId)).json")
    }

    func projectOutputContextURL(for project: ProjectRecord) -> URL {
        storyDirectory(for: project).appendingPathComponent("project_output_context.json")
    }

    func projectAestheticInterviewURL(for project: ProjectRecord) -> URL {
        storyDirectory(for: project).appendingPathComponent("project_aesthetic_interview.json")
    }

    func storyWorkspaceURL(for project: ProjectRecord) -> URL {
        storyDirectory(for: project).appendingPathComponent("story_workspace.json")
    }

    func storySetupURL(for project: ProjectRecord) -> URL {
        storyDirectory(for: project).appendingPathComponent("story_setup.json")
    }

    func storylineCreationURL(for project: ProjectRecord) -> URL {
        storyDirectory(for: project).appendingPathComponent("storyline_creation.json")
    }

    func storySignalsURL(for project: ProjectRecord) -> URL {
        storyDirectory(for: project).appendingPathComponent("story_signals.json")
    }

    func storyDirectionsURL(for project: ProjectRecord) -> URL {
        storyDirectory(for: project).appendingPathComponent("story_directions.json")
    }

    func storyBeatBoardsDirectory(for project: ProjectRecord) -> URL {
        storyDirectory(for: project).appendingPathComponent("beat_boards", isDirectory: true)
    }

    func legacyStoryBeatBoardsDirectory(for project: ProjectRecord) -> URL {
        storyDirectory(for: project).appendingPathComponent("story_beat_boards", isDirectory: true)
    }

    func storyBeatBoardURL(for project: ProjectRecord, beatBoardId: String) -> URL {
        storyBeatBoardsDirectory(for: project).appendingPathComponent("\(safeIdentifier(beatBoardId)).json")
    }

    func storySequenceStripsDirectory(for project: ProjectRecord) -> URL {
        storyDirectory(for: project).appendingPathComponent("sequence_strips", isDirectory: true)
    }

    func storySequenceStripURL(for project: ProjectRecord, beatBoardId: String) -> URL {
        storySequenceStripsDirectory(for: project).appendingPathComponent("strip_\(safeIdentifier(beatBoardId)).json")
    }

    func legacyStorySequenceStripURL(for project: ProjectRecord) -> URL {
        storyDirectory(for: project).appendingPathComponent("story_sequence_strip.json")
    }

    func projectStoryURL(for project: ProjectRecord) -> URL {
        storyDirectory(for: project).appendingPathComponent("project_story.json")
    }

    func sceneWorkspacesDirectory(for project: ProjectRecord) -> URL {
        storyDirectory(for: project).appendingPathComponent("scene_workspaces", isDirectory: true)
    }

    func sceneWorkspaceURL(for project: ProjectRecord, sceneWorkspaceId: String) -> URL {
        sceneWorkspacesDirectory(for: project).appendingPathComponent("\(safeIdentifier(sceneWorkspaceId)).json")
    }

    func sceneAssetsDirectory(for project: ProjectRecord) -> URL {
        storyDirectory(for: project).appendingPathComponent("scene_assets", isDirectory: true)
    }

    func sceneAssetURL(for project: ProjectRecord, assetId: String) -> URL {
        sceneAssetsDirectory(for: project).appendingPathComponent("\(safeIdentifier(assetId)).json")
    }

    func sceneExportsDirectory(for project: ProjectRecord) -> URL {
        storyDirectory(for: project).appendingPathComponent("scene_exports", isDirectory: true)
    }

    func scenePromptExportMarkdownURL(for project: ProjectRecord, exportId: String) -> URL {
        sceneExportsDirectory(for: project).appendingPathComponent("\(safeIdentifier(exportId))_scene_prompts.md")
    }

    func scenePromptExportJSONURL(for project: ProjectRecord, exportId: String) -> URL {
        sceneExportsDirectory(for: project).appendingPathComponent("\(safeIdentifier(exportId))_scene_prompts.json")
    }

    func videoChainsDirectory(for project: ProjectRecord) -> URL {
        storyDirectory(for: project).appendingPathComponent("video_chains", isDirectory: true)
    }

    func videoChainURL(for project: ProjectRecord, chainId: String) -> URL {
        videoChainsDirectory(for: project).appendingPathComponent("\(safeIdentifier(chainId)).json")
    }

    func videoChainAssetsDirectory(for project: ProjectRecord, chainId: String) -> URL {
        videoChainsDirectory(for: project)
            .appendingPathComponent("assets", isDirectory: true)
            .appendingPathComponent(safeIdentifier(chainId), isDirectory: true)
    }

    func videoChainKeyframesDirectory(for project: ProjectRecord, chainId: String) -> URL {
        videoChainAssetsDirectory(for: project, chainId: chainId).appendingPathComponent("keyframes", isDirectory: true)
    }

    func videoChainClipsDirectory(for project: ProjectRecord, chainId: String) -> URL {
        videoChainAssetsDirectory(for: project, chainId: chainId).appendingPathComponent("clips", isDirectory: true)
    }

    func videoChainClipVersionsDirectory(for project: ProjectRecord, chainId: String, segmentId: String) -> URL {
        videoChainClipsDirectory(for: project, chainId: chainId)
            .appendingPathComponent(safeIdentifier(segmentId), isDirectory: true)
            .appendingPathComponent("versions", isDirectory: true)
    }

    func videoChainProviderOutputsDirectory(for project: ProjectRecord, chainId: String, segmentId: String) -> URL {
        videoChainAssetsDirectory(for: project, chainId: chainId)
            .appendingPathComponent("provider_outputs", isDirectory: true)
            .appendingPathComponent(safeIdentifier(segmentId), isDirectory: true)
    }

    func videoChainProviderOutputURL(
        for project: ProjectRecord,
        chainId: String,
        segmentId: String,
        versionId: String,
        versionNumber: Int,
        operation: String
    ) -> URL {
        videoChainProviderOutputsDirectory(for: project, chainId: chainId, segmentId: segmentId)
            .appendingPathComponent("v\(String(format: "%02d", versionNumber))_\(safeIdentifier(versionId))_\(safeIdentifier(operation)).mp4")
    }

    func videoChainClipVersionURL(
        for project: ProjectRecord,
        chainId: String,
        segmentId: String,
        versionId: String,
        versionNumber: Int
    ) -> URL {
        videoChainClipVersionsDirectory(for: project, chainId: chainId, segmentId: segmentId)
            .appendingPathComponent("v\(String(format: "%02d", versionNumber))_\(safeIdentifier(versionId)).mp4")
    }

    func videoChainVersionKeyframesDirectory(for project: ProjectRecord, chainId: String, segmentId: String) -> URL {
        videoChainKeyframesDirectory(for: project, chainId: chainId)
            .appendingPathComponent(safeIdentifier(segmentId), isDirectory: true)
            .appendingPathComponent("versions", isDirectory: true)
    }

    func videoChainOpenAIInputsDirectory(for project: ProjectRecord, chainId: String, segmentId: String) -> URL {
        videoChainKeyframesDirectory(for: project, chainId: chainId)
            .appendingPathComponent(safeIdentifier(segmentId), isDirectory: true)
            .appendingPathComponent("openai_inputs", isDirectory: true)
    }

    func videoChainExportsDirectory(for project: ProjectRecord, chainId: String) -> URL {
        videoChainAssetsDirectory(for: project, chainId: chainId).appendingPathComponent("exports", isDirectory: true)
    }

    func videoChainManifestJSONURL(for project: ProjectRecord, chainId: String) -> URL {
        videoChainExportsDirectory(for: project, chainId: chainId).appendingPathComponent("manifest.json")
    }

    func videoChainManifestMarkdownURL(for project: ProjectRecord, chainId: String) -> URL {
        videoChainExportsDirectory(for: project, chainId: chainId).appendingPathComponent("manifest.md")
    }

    func videoChainStitchedOutputURL(for project: ProjectRecord, chainId: String) -> URL {
        videoChainExportsDirectory(for: project, chainId: chainId).appendingPathComponent("story_reel.mp4")
    }

    func storyGenerationRunsDirectory(for project: ProjectRecord) -> URL {
        storyDirectory(for: project).appendingPathComponent("generation_runs", isDirectory: true)
    }

    func storyGenerationRunURL(for project: ProjectRecord, runId: String) -> URL {
        storyGenerationRunsDirectory(for: project).appendingPathComponent("\(safeIdentifier(runId)).json")
    }

    func storyGenerationRunIndexURL(for project: ProjectRecord) -> URL {
        storyDirectory(for: project).appendingPathComponent("story_generation_run_index.json")
    }

    func projectArchiveMeaningURL(for project: ProjectRecord) -> URL {
        storyDirectory(for: project).appendingPathComponent("project_archive_meaning.json")
    }

    func storyBeatSheetURL(for project: ProjectRecord) -> URL {
        storyDirectory(for: project).appendingPathComponent("story_beat_sheet.json")
    }

    func storyAudioTrackURL(for project: ProjectRecord) -> URL {
        storyDirectory(for: project).appendingPathComponent("story_audio_track.json")
    }

    func storyAudioTracksURL(for project: ProjectRecord) -> URL {
        storyDirectory(for: project).appendingPathComponent("story_audio_tracks.json")
    }

    func storyAudioDirectory(for project: ProjectRecord) -> URL {
        storyDirectory(for: project).appendingPathComponent("audio", isDirectory: true)
    }

    func ambientBedDirectory(for project: ProjectRecord) -> URL {
        storyDirectory(for: project).appendingPathComponent("ambient", isDirectory: true)
    }

    func mediaObservationsURL(for project: ProjectRecord) -> URL {
        storyDirectory(for: project).appendingPathComponent("media_observations.json")
    }

    func loadStoryWorld(for project: ProjectRecord) -> StoryWorldDocument {
        guard let document = loadDBDocument(StoryWorldDocument.self, for: project, documentType: "story_world") else {
            return StoryWorldDocument.empty(projectId: project.projectId)
        }
        if document.projectId.isEmpty {
            var upgraded = document
            upgraded.projectId = project.projectId
            return upgraded
        }
        return document
    }

    func saveStoryWorld(_ storyWorld: StoryWorldDocument, for project: ProjectRecord) throws {
        try saveDBDocument(storyWorld, for: project, documentType: "story_world")
    }

    func loadSourceContext(for project: ProjectRecord) -> [SourceContextRecord] {
        guard let document = loadDBDocument(SourceContextDocument.self, for: project, documentType: "source_context") else {
            return []
        }
        return document.records
    }

    func saveSourceContext(_ records: [SourceContextRecord], for project: ProjectRecord) throws {
        try ensureDirectory(storyDirectory(for: project))
        let sortedRecords = records.sorted { lhs, rhs in
            if lhs.kind.rawValue == rhs.kind.rawValue {
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
            return lhs.kind.rawValue < rhs.kind.rawValue
        }
        let document = SourceContextDocument(projectId: project.projectId, records: sortedRecords)
        try saveDBDocument(document, for: project, documentType: "source_context")
    }

    func loadVisionUIPreferences(for project: ProjectRecord) -> VisionUIPreferencesDocument {
        guard var document = loadDBDocument(VisionUIPreferencesDocument.self, for: project, documentType: "vision_ui") else {
            return VisionUIPreferencesDocument.empty(projectId: project.projectId)
        }
        if document.projectId.isEmpty {
            document.projectId = project.projectId
        }
        return document
    }

    func saveVisionUIPreferences(_ preferences: VisionUIPreferencesDocument, for project: ProjectRecord) throws {
        try saveDBDocument(preferences, for: project, documentType: "vision_ui")
    }

    func loadProjectPromptSettings(for project: ProjectRecord) -> ProjectPromptSettingsDocument {
        guard var document = loadDBDocument(ProjectPromptSettingsDocument.self, for: project, documentType: "project_prompt_settings") else {
            return .empty(projectId: project.projectId)
        }
        if document.projectId.isEmpty {
            document.projectId = project.projectId
        }
        return document.normalized(projectId: project.projectId)
    }

    func saveProjectPromptSettings(_ settings: ProjectPromptSettingsDocument, for project: ProjectRecord) throws {
        try saveDBDocument(settings.normalized(projectId: project.projectId), for: project, documentType: "project_prompt_settings")
    }

    func loadProjectAesthetic(for project: ProjectRecord) -> ProjectAestheticDocument {
        guard let document = loadDBDocument(ProjectAestheticDocument.self, for: project, documentType: "project_aesthetic") else {
            return ProjectAestheticDocument.empty(projectId: project.projectId)
        }
        if document.projectId.isEmpty {
            var upgraded = document
            upgraded.projectId = project.projectId
            return upgraded
        }
        return document
    }

    func saveProjectAesthetic(_ aesthetic: ProjectAestheticDocument, for project: ProjectRecord) throws {
        try saveDBDocument(aesthetic, for: project, documentType: "project_aesthetic")
    }

    func loadAestheticBrief(for project: ProjectRecord) -> ProjectAestheticBriefDocument {
        guard var document = loadDBDocument(ProjectAestheticBriefDocument.self, for: project, documentType: "aesthetic_brief") else {
            return ProjectAestheticBriefDocument.empty(projectId: project.projectId)
        }
        if document.projectId.isEmpty {
            document.projectId = project.projectId
        }
        return document
    }

    func saveAestheticBrief(_ brief: ProjectAestheticBriefDocument, for project: ProjectRecord) throws {
        try saveDBDocument(brief, for: project, documentType: "aesthetic_brief")
    }

    func loadAestheticWheel(for project: ProjectRecord) -> AestheticWheelDocument {
        guard var document = loadDBDocument(AestheticWheelDocument.self, for: project, documentType: "aesthetic_wheel") else {
            return AestheticWheelDocument.empty(projectId: project.projectId)
        }
        if document.projectId.isEmpty {
            document.projectId = project.projectId
        }
        return document
    }

    func saveAestheticWheel(_ wheel: AestheticWheelDocument, for project: ProjectRecord) throws {
        try saveDBDocument(wheel, for: project, documentType: "aesthetic_wheel")
    }

    func loadAestheticProofSheets(for project: ProjectRecord) -> [AestheticProofSheetDocument] {
        loadDBDocument([AestheticProofSheetDocument].self, for: project, documentType: "aesthetic_proof_sheets") ?? []
    }

    func saveAestheticProofSheets(_ sheets: [AestheticProofSheetDocument], for project: ProjectRecord) throws {
        try ensureDirectory(aestheticProofDirectory(for: project))
        try saveDBDocument(sheets, for: project, documentType: "aesthetic_proof_sheets")
    }

    func loadAestheticDirectionComposites(for project: ProjectRecord) -> AestheticDirectionCompositeDocument {
        guard var document = loadDBDocument(AestheticDirectionCompositeDocument.self, for: project, documentType: "aesthetic_direction_composites") else {
            return AestheticDirectionCompositeDocument.empty(projectId: project.projectId)
        }
        if document.projectId.isEmpty {
            document.projectId = project.projectId
        }
        return document
    }

    func saveAestheticDirectionComposites(_ document: AestheticDirectionCompositeDocument, for project: ProjectRecord) throws {
        try saveDBDocument(document, for: project, documentType: "aesthetic_direction_composites")
    }

    func loadAestheticEvidenceProfile(for project: ProjectRecord) -> ProjectAestheticEvidenceProfile {
        guard var document = loadDBDocument(ProjectAestheticEvidenceProfile.self, for: project, documentType: "aesthetic_evidence_profile") else {
            return ProjectAestheticEvidenceProfile.empty(projectId: project.projectId)
        }
        if document.projectId.isEmpty {
            document.projectId = project.projectId
        }
        return document
    }

    func saveAestheticEvidenceProfile(_ document: ProjectAestheticEvidenceProfile, for project: ProjectRecord) throws {
        try saveDBDocument(document, for: project, documentType: "aesthetic_evidence_profile")
    }

    func loadAestheticDirectionSelection(for project: ProjectRecord) -> AestheticDirectionSelectionDocument {
        guard var document = loadDBDocument(AestheticDirectionSelectionDocument.self, for: project, documentType: "aesthetic_direction_selection") else {
            return AestheticDirectionSelectionDocument.empty(projectId: project.projectId)
        }
        if document.projectId.isEmpty {
            document.projectId = project.projectId
        }
        return document
    }

    func saveAestheticDirectionSelection(_ document: AestheticDirectionSelectionDocument, for project: ProjectRecord) throws {
        try saveDBDocument(document, for: project, documentType: "aesthetic_direction_selection")
    }

    func loadProjectGoal(for project: ProjectRecord, fallbackAesthetic: ProjectAestheticDocument) -> ProjectGoalDocument {
        if var document = loadDBDocument(ProjectGoalDocument.self, for: project, documentType: "project_goal_v1") {
            if document.projectId.isEmpty {
                document.projectId = project.projectId
            }
            return document
        }
        return ProjectGoalDocument.fromLegacyAesthetic(fallbackAesthetic, projectId: project.projectId)
    }

    func saveProjectGoal(_ goal: ProjectGoalDocument, for project: ProjectRecord) throws {
        try saveDBDocument(goal, for: project, documentType: "project_goal_v1")
    }

    func loadProjectGoalV2(for project: ProjectRecord) -> ProjectGoalDocumentV2 {
        guard var document = try? goalSQLiteStore.loadProjectGoal(for: project) else {
            return ProjectGoalDocumentV2.empty(projectId: project.projectId)
        }
        document.schemaVersion = ProjectGoalDocumentV2.schemaVersion
        if document.projectId.isEmpty {
            document.projectId = project.projectId
        }
        return document
    }

    func saveProjectGoalV2(_ goal: ProjectGoalDocumentV2, for project: ProjectRecord) throws {
        var document = goal
        document.schemaVersion = ProjectGoalDocumentV2.schemaVersion
        try goalSQLiteStore.saveProjectGoal(document, for: project)
    }

    func loadLensContext(for project: ProjectRecord) -> ProjectLensContextDocument {
        guard var document = loadDBDocument(ProjectLensContextDocument.self, for: project, documentType: "lens_context")
            ?? loadDBDocument(ProjectLensContextDocument.self, for: project, documentType: "theme_context")
        else {
            return ProjectLensContextDocument.empty(projectId: project.projectId)
        }
        document.schemaVersion = ProjectLensContextDocument.schemaVersion
        if document.projectId.isEmpty {
            document.projectId = project.projectId
        }
        return document
    }

    func saveLensContext(_ context: ProjectLensContextDocument, for project: ProjectRecord) throws {
        try saveDBDocument(context, for: project, documentType: "lens_context")
    }

    func loadFrameForms(for project: ProjectRecord) -> ProjectFrameFormsDocument {
        guard var document = loadDBDocument(ProjectFrameFormsDocument.self, for: project, documentType: ProjectFrameFormsDocument.documentType) else {
            return ProjectFrameFormsDocument.empty(projectId: project.projectId)
        }
        document.schemaVersion = ProjectFrameFormsDocument.schemaVersion
        if document.projectId.isEmpty {
            document.projectId = project.projectId
        }
        return document
    }

    func saveFrameForms(_ document: ProjectFrameFormsDocument, for project: ProjectRecord) throws {
        try saveDBDocument(document, for: project, documentType: ProjectFrameFormsDocument.documentType)
    }

    func loadProjectLenses(for project: ProjectRecord) -> ProjectLensSetDocument {
        guard var document = try? lensSQLiteStore.loadProjectLenses(for: project),
              document.schemaVersion == ProjectLensSetDocument.schemaVersion else {
            return ProjectLensSetDocument.bootstrap(projectId: project.projectId)
        }
        if document.projectId.isEmpty {
            document.projectId = project.projectId
        }
        return document.canonicalizedToSingleLens()
    }

    func saveProjectLenses(_ lenses: ProjectLensSetDocument, for project: ProjectRecord) throws {
        try lensSQLiteStore.saveProjectLenses(lenses.canonicalizedToSingleLens(), for: project)
    }

    func loadProjectCharacters(for project: ProjectRecord) -> ProjectCharacterSetDocument {
        guard var document = loadDBDocument(ProjectCharacterSetDocument.self, for: project, documentType: ProjectCharacterSetDocument.documentType),
              document.schemaVersion == ProjectCharacterSetDocument.schemaVersion else {
            return ProjectCharacterSetDocument.empty(projectId: project.projectId)
        }
        if document.projectId.isEmpty {
            document.projectId = project.projectId
        }
        return document
    }

    func saveProjectCharacters(_ characters: ProjectCharacterSetDocument, for project: ProjectRecord) throws {
        try guardProjectIdentity(documentProjectId: characters.projectId, project: project, documentType: ProjectCharacterSetDocument.documentType)
        try saveDBDocument(characters.normalized(), for: project, documentType: ProjectCharacterSetDocument.documentType)
    }

    func loadProjectCharacterChats(for project: ProjectRecord) -> ProjectCharacterChatDocument {
        guard var document = loadDBDocument(ProjectCharacterChatDocument.self, for: project, documentType: ProjectCharacterChatDocument.documentType) else {
            return ProjectCharacterChatDocument.empty(projectId: project.projectId)
        }
        document.schemaVersion = ProjectCharacterChatDocument.schemaVersion
        if document.projectId.isEmpty {
            document.projectId = project.projectId
        }
        return document
    }

    func saveProjectCharacterChats(_ chats: ProjectCharacterChatDocument, for project: ProjectRecord) throws {
        try guardProjectIdentity(documentProjectId: chats.projectId, project: project, documentType: ProjectCharacterChatDocument.documentType)
        try saveDBDocument(chats.normalized(), for: project, documentType: ProjectCharacterChatDocument.documentType)
    }

    func loadProjectObjects(for project: ProjectRecord) -> ProjectObjectSetDocument {
        guard var document = loadDBDocument(ProjectObjectSetDocument.self, for: project, documentType: ProjectObjectSetDocument.documentType),
              document.schemaVersion == ProjectObjectSetDocument.schemaVersion else {
            return ProjectObjectSetDocument.empty(projectId: project.projectId)
        }
        if document.projectId.isEmpty {
            document.projectId = project.projectId
        }
        return document
    }

    func saveProjectObjects(_ objects: ProjectObjectSetDocument, for project: ProjectRecord) throws {
        try saveDBDocument(objects.normalized(), for: project, documentType: ProjectObjectSetDocument.documentType)
    }

    func loadProjectPlaces(for project: ProjectRecord) -> ProjectPlaceSetDocument {
        guard var document = loadDBDocument(ProjectPlaceSetDocument.self, for: project, documentType: ProjectPlaceSetDocument.documentType),
              document.schemaVersion == ProjectPlaceSetDocument.schemaVersion else {
            return ProjectPlaceSetDocument.empty(projectId: project.projectId)
        }
        if document.projectId.isEmpty {
            document.projectId = project.projectId
        }
        return document
    }

    func saveProjectPlaces(_ places: ProjectPlaceSetDocument, for project: ProjectRecord) throws {
        try saveDBDocument(places.normalized(), for: project, documentType: ProjectPlaceSetDocument.documentType)
    }

    func loadTerrainMap(for project: ProjectRecord) -> TerrainMapDocument {
        guard var document = loadDBDocument(TerrainMapDocument.self, for: project, documentType: TerrainMapDocument.documentType),
              document.schemaVersion == TerrainMapDocument.schemaVersion else {
            return TerrainMapDocument.empty(projectId: project.projectId)
        }
        if document.projectId.isEmpty {
            document.projectId = project.projectId
        }
        return document
    }

    func saveTerrainMap(_ map: TerrainMapDocument, for project: ProjectRecord) throws {
        try guardProjectIdentity(
            documentProjectId: map.projectId,
            project: project,
            documentType: TerrainMapDocument.documentType
        )
        try saveDBDocument(map.normalized(), for: project, documentType: TerrainMapDocument.documentType)
    }

    /// Scratch home for terrain canvases and region crops before they enter
    /// the media archive.
    func terrainMapDirectory(for project: ProjectRecord) -> URL {
        storyDirectory(for: project).appendingPathComponent("terrain_map", isDirectory: true)
    }

    func loadGoalCast(for project: ProjectRecord) -> GoalCastDocument {
        guard var document = loadDBDocument(GoalCastDocument.self, for: project, documentType: GoalCastDocument.documentType),
              document.schemaVersion == GoalCastDocument.schemaVersion else {
            return GoalCastDocument.empty(projectId: project.projectId)
        }
        if document.projectId.isEmpty {
            document.projectId = project.projectId
        }
        return document
    }

    func saveGoalCast(_ cast: GoalCastDocument, for project: ProjectRecord) throws {
        try saveDBDocument(cast.normalized(), for: project, documentType: GoalCastDocument.documentType)
    }

    func loadShotTimeline(for project: ProjectRecord) -> ProjectShotTimelineDocument {
        guard var document = loadDBDocument(ProjectShotTimelineDocument.self, for: project, documentType: ProjectShotTimelineDocument.documentType) else {
            return ProjectShotTimelineDocument.empty(projectId: project.projectId)
        }
        document.schemaVersion = ProjectShotTimelineDocument.schemaVersion
        if document.projectId.isEmpty {
            document.projectId = project.projectId
        }
        return document
    }

    /// THE PROJECT IDENTITY LAW: a document that names a project may only be
    /// saved into THAT project's store. Every loaded document carries its
    /// project id (loads stamp empty ones), so a mismatch here is always a
    /// cross-project write in flight — a stale in-memory document racing a
    /// project switch. Refusing loses one write; allowing it once replaced a
    /// whole project's timeline with another project's (observed: the
    /// cross-project bleed).
    func guardProjectIdentity(documentProjectId: String, project: ProjectRecord, documentType: String) throws {
        let documentId = documentProjectId.trimmed
        guard documentId.isEmpty || documentId == project.projectId else {
            throw ScreenGraphError.capture(
                "Refused a cross-project write: a \(documentType) document belonging to \(documentId) "
                    + "was about to save into \(project.projectId). Nothing was written."
            )
        }
    }

    func saveShotTimeline(_ timeline: ProjectShotTimelineDocument, for project: ProjectRecord) throws {
        try guardProjectIdentity(
            documentProjectId: timeline.projectId,
            project: project,
            documentType: ProjectShotTimelineDocument.documentType
        )
        try saveDBDocument(timeline.normalized(), for: project, documentType: ProjectShotTimelineDocument.documentType)
    }

    func loadMediaGenerations(for project: ProjectRecord) -> ProjectMediaGenerationsDocument {
        guard var document = loadDBDocument(
            ProjectMediaGenerationsDocument.self,
            for: project,
            documentType: ProjectMediaGenerationsDocument.documentType
        ) else {
            return ProjectMediaGenerationsDocument.empty(projectId: project.projectId)
        }
        document.schemaVersion = ProjectMediaGenerationsDocument.schemaVersion
        if document.projectId.isEmpty {
            document.projectId = project.projectId
        }
        return document
    }

    func saveMediaGenerations(_ document: ProjectMediaGenerationsDocument, for project: ProjectRecord) throws {
        try guardProjectIdentity(
            documentProjectId: document.projectId,
            project: project,
            documentType: ProjectMediaGenerationsDocument.documentType
        )
        try saveDBDocument(document.normalized(), for: project, documentType: ProjectMediaGenerationsDocument.documentType)
    }

    func loadAmbientBedLibrary(for project: ProjectRecord) -> ProjectAmbientBedLibraryDocument {
        guard var document = loadDBDocument(
            ProjectAmbientBedLibraryDocument.self,
            for: project,
            documentType: ProjectAmbientBedLibraryDocument.documentType
        ) else {
            return .empty(projectId: project.projectId)
        }
        document.schemaVersion = ProjectAmbientBedLibraryDocument.currentSchemaVersion
        if document.projectId.isEmpty {
            document.projectId = project.projectId
        }
        return document.normalized()
    }

    func saveAmbientBedLibrary(_ library: ProjectAmbientBedLibraryDocument, for project: ProjectRecord) throws {
        try saveDBDocument(library.normalized(), for: project, documentType: ProjectAmbientBedLibraryDocument.documentType)
    }

    /// Distinguishes a project that has never persisted a stage set (seeding
    /// is the legitimate flat-timeline migration) from one whose persisted
    /// document exists but no longer decodes (seeding would overwrite the
    /// operator's stages/finals/trash with a rebuild). Tolerant decode covers
    /// missing and null fields; a present-but-wrong-typed value throws, and
    /// that difference must reach the caller instead of collapsing to nil.
    enum StageSetLoadResult {
        case absent
        case document(ProjectStageSetDocument)
        case unreadable(String)
    }

    func loadStageSet(for project: ProjectRecord) -> StageSetLoadResult {
        let data: Data?
        do {
            data = try documentStore.loadDocumentData(for: project, documentType: ProjectStageSetDocument.documentType)
        } catch {
            // Row existence is unknown; treating an unreadable database as
            // "never saved" risks seeding over live data, so refuse.
            return .unreadable(error.localizedDescription)
        }
        guard let data else { return .absent }
        do {
            var document = try JSONCoding.decoder.decode(ProjectStageSetDocument.self, from: data)
            document.schemaVersion = ProjectStageSetDocument.schemaVersion
            if document.projectId.isEmpty {
                document.projectId = project.projectId
            }
            return .document(document)
        } catch {
            return .unreadable(error.localizedDescription)
        }
    }

    func saveStageSet(_ stageSet: ProjectStageSetDocument, for project: ProjectRecord) throws {
        try guardProjectIdentity(
            documentProjectId: stageSet.projectId,
            project: project,
            documentType: ProjectStageSetDocument.documentType
        )
        try saveDBDocument(stageSet.normalized(), for: project, documentType: ProjectStageSetDocument.documentType)
    }

    func saveShotTimelineAndStageSet(
        timeline: ProjectShotTimelineDocument,
        stageSet: ProjectStageSetDocument,
        for project: ProjectRecord
    ) throws {
        try guardProjectIdentity(
            documentProjectId: timeline.projectId,
            project: project,
            documentType: ProjectShotTimelineDocument.documentType
        )
        try guardProjectIdentity(
            documentProjectId: stageSet.projectId,
            project: project,
            documentType: ProjectStageSetDocument.documentType
        )
        let normalizedTimeline = timeline.normalized()
        let normalizedStageSet = stageSet.normalized()
        try documentStore.saveDocumentsAtomically([
            ProjectDocumentBatchWrite(
                data: try JSONCoding.encoder.encode(normalizedTimeline),
                documentType: ProjectShotTimelineDocument.documentType
            ),
            ProjectDocumentBatchWrite(
                data: try JSONCoding.encoder.encode(normalizedStageSet),
                documentType: ProjectStageSetDocument.documentType
            )
        ], for: project)
    }

    func loadOutputSequence(for project: ProjectRecord) -> ProjectOutputSequenceDocument? {
        guard var document = loadDBDocument(
            ProjectOutputSequenceDocument.self,
            for: project,
            documentType: ProjectOutputSequenceDocument.documentType
        ) else {
            return nil
        }
        document.schemaVersion = ProjectOutputSequenceDocument.schemaVersion
        if document.projectId.isEmpty {
            document.projectId = project.projectId
        }
        return document.normalized()
    }

    func saveOutputSequence(_ sequence: ProjectOutputSequenceDocument, for project: ProjectRecord) throws {
        try guardProjectIdentity(
            documentProjectId: sequence.projectId,
            project: project,
            documentType: ProjectOutputSequenceDocument.documentType
        )
        try saveDBDocument(
            sequence.normalized(),
            for: project,
            documentType: ProjectOutputSequenceDocument.documentType
        )
    }

    /// The one-time Stage → flat-Shot cutover is all-or-nothing. A launch may
    /// never stamp the timeline migrated while losing the legacy Output picks.
    func saveFlatShotMigration(
        timeline: ProjectShotTimelineDocument,
        outputSequence: ProjectOutputSequenceDocument,
        for project: ProjectRecord
    ) throws {
        try guardProjectIdentity(
            documentProjectId: timeline.projectId,
            project: project,
            documentType: ProjectShotTimelineDocument.documentType
        )
        try guardProjectIdentity(
            documentProjectId: outputSequence.projectId,
            project: project,
            documentType: ProjectOutputSequenceDocument.documentType
        )
        let normalizedTimeline = timeline.normalized()
        let normalizedOutput = outputSequence.normalized()
        try documentStore.saveDocumentsAtomically([
            ProjectDocumentBatchWrite(
                data: try JSONCoding.encoder.encode(normalizedTimeline),
                documentType: ProjectShotTimelineDocument.documentType
            ),
            ProjectDocumentBatchWrite(
                data: try JSONCoding.encoder.encode(normalizedOutput),
                documentType: ProjectOutputSequenceDocument.documentType
            )
        ], for: project)
    }

    /// A Shot can be present in Output, so soft deletion updates both owners
    /// together. This is also useful for later Output edits that affect the
    /// visible Shot ledger.
    func saveShotTimelineAndOutputSequence(
        timeline: ProjectShotTimelineDocument,
        outputSequence: ProjectOutputSequenceDocument,
        for project: ProjectRecord
    ) throws {
        try saveFlatShotMigration(
            timeline: timeline,
            outputSequence: outputSequence,
            for: project
        )
    }

    func loadProjectOutputContext(for project: ProjectRecord) -> ProjectOutputContext {
        guard var document = loadDBDocument(ProjectOutputContext.self, for: project, documentType: "project_output_context"),
              document.schemaVersion == ProjectOutputContext.schemaVersion else {
            return ProjectOutputContext.empty(projectId: project.projectId)
        }
        if document.projectId.isEmpty {
            document.projectId = project.projectId
        }
        return document
    }

    func saveProjectOutputContext(_ outputContext: ProjectOutputContext, for project: ProjectRecord) throws {
        try saveDBDocument(outputContext, for: project, documentType: "project_output_context")
    }

    func creativeSchemaState(for project: ProjectRecord) -> CreativeSchemaCompatibilityState {
        let goalExists = goalSQLiteStore.goalExists(for: project)
        let lensesExists = lensSQLiteStore.lensSetExists(for: project)
        if !goalExists || !lensesExists {
            return .needsBootstrap
        }
        return .ready
    }

    func bootstrapCreativeV2Data(for project: ProjectRecord) throws {
        if !goalSQLiteStore.goalExists(for: project) {
            try saveProjectGoalV2(.empty(projectId: project.projectId), for: project)
        }
        if !lensSQLiteStore.lensSetExists(for: project) {
            try saveProjectLenses(.bootstrap(projectId: project.projectId), for: project)
        }
        if !documentStore.documentExists(for: project, documentType: "project_output_context") {
            try saveProjectOutputContext(.empty(projectId: project.projectId), for: project)
        }
        if !documentStore.documentExists(for: project, documentType: "lens_context"),
           !documentStore.documentExists(for: project, documentType: "theme_context") {
            try saveLensContext(.empty(projectId: project.projectId), for: project)
        }
    }

    func resetCreativeData(for project: ProjectRecord) throws -> CreativeDataResetResult {
        try documentStore.deleteDocuments(for: project, documentTypes: [
            "project_goal_v1",
            "project_goal_v2",
            "lens_context",
            "theme_context",
            "project_lenses",
            "project_themes",
            "project_output_context",
            "project_aesthetic",
            "project_aesthetic_interview",
            "aesthetic_brief",
            "aesthetic_wheel",
            "aesthetic_proof_sheets",
            "aesthetic_direction_composites",
            "aesthetic_evidence_profile",
            "aesthetic_direction_selection",
            "story_workspace",
            "storyline_creation",
            "story_theme_creation"
        ])

        try saveProjectGoalV2(.empty(projectId: project.projectId), for: project)
        try saveLensContext(.empty(projectId: project.projectId), for: project)
        try saveProjectLenses(.bootstrap(projectId: project.projectId), for: project)
        try saveProjectOutputContext(.empty(projectId: project.projectId), for: project)
        try saveStoryWorkspace(.empty(projectId: project.projectId), for: project)

        return CreativeDataResetResult(
            archivedPaths: [],
            archiveDirectory: nil
        )
    }

    func loadProjectAestheticInterview(
        for project: ProjectRecord,
        fallbackOpenQuestions: [String] = []
    ) -> ProjectAestheticInterviewDocument {
        if var document = loadDBDocument(ProjectAestheticInterviewDocument.self, for: project, documentType: "project_aesthetic_interview") {
            if document.projectId.isEmpty {
                document.projectId = project.projectId
            }
            return document
        }
        return ProjectAestheticInterviewDocument.fromLegacyOpenQuestions(
            projectId: project.projectId,
            questions: fallbackOpenQuestions
        )
    }

    func saveProjectAestheticInterview(_ interview: ProjectAestheticInterviewDocument, for project: ProjectRecord) throws {
        try saveDBDocument(interview, for: project, documentType: "project_aesthetic_interview")
    }

    func loadStoryWorkspace(for project: ProjectRecord) -> StoryWorkspaceDocument {
        guard var document = loadDBDocument(StoryWorkspaceDocument.self, for: project, documentType: "story_workspace") else {
            return StoryWorkspaceDocument.empty(projectId: project.projectId)
        }
        if document.projectId.isEmpty {
            document.projectId = project.projectId
        }
        return document
    }

    func saveStoryWorkspace(_ workspace: StoryWorkspaceDocument, for project: ProjectRecord) throws {
        try saveDBDocument(workspace, for: project, documentType: "story_workspace")
    }

    func loadStorySetup(for project: ProjectRecord) -> StorySetupDocument {
        guard var document = loadDBDocument(StorySetupDocument.self, for: project, documentType: "story_setup") else {
            return StorySetupDocument.empty(projectId: project.projectId)
        }
        if document.projectId.isEmpty {
            document.projectId = project.projectId
        }
        return document
    }

    func saveStorySetup(_ setup: StorySetupDocument, for project: ProjectRecord) throws {
        try saveDBDocument(setup, for: project, documentType: "story_setup")
    }

    func loadStorylineCreation(
        for project: ProjectRecord,
        seedSetup: StorySetupDocument
    ) -> StorylineCreationDocument {
        guard var document = loadDBDocument(StorylineCreationDocument.self, for: project, documentType: "storyline_creation")
            ?? loadDBDocument(StorylineCreationDocument.self, for: project, documentType: "story_theme_creation")
        else {
            return StorylineCreationDocument.empty(projectId: project.projectId, seedSetup: seedSetup)
        }
        document.schemaVersion = StorylineCreationDocument.schemaVersion
        if document.projectId.isEmpty {
            document.projectId = project.projectId
        }
        if document.draftSetup.projectId.isEmpty {
            document.draftSetup.projectId = project.projectId
        }
        return document
    }

    func saveStorylineCreation(_ creation: StorylineCreationDocument, for project: ProjectRecord) throws {
        try saveDBDocument(creation, for: project, documentType: "storyline_creation")
    }

    func loadStorySignals(for project: ProjectRecord) -> StorySignalSet {
        if var document = loadDBDocument(StorySignalSet.self, for: project, documentType: "story_signals") {
            if document.projectId.isEmpty {
                document.projectId = project.projectId
            }
            return document
        }
        return StorySignalSet.empty(projectId: project.projectId)
    }

    func saveStorySignals(_ signals: StorySignalSet, for project: ProjectRecord) throws {
        try saveDBDocument(signals, for: project, documentType: "story_signals")
    }

    func loadStoryDirectionHistory(for project: ProjectRecord) -> StoryDirectionHistoryDocument {
        guard var document = loadDBDocument(StoryDirectionHistoryDocument.self, for: project, documentType: "story_directions") else {
            return StoryDirectionHistoryDocument.empty(projectId: project.projectId)
        }
        if document.projectId.isEmpty {
            document.projectId = project.projectId
        }
        return document
    }

    func loadActiveStoryDirectionSet(for project: ProjectRecord) -> StoryDirectionSet {
        loadStoryDirectionHistory(for: project).activeSet
    }

    func saveStoryDirectionSet(_ set: StoryDirectionSet, for project: ProjectRecord) throws {
        let history = loadStoryDirectionHistory(for: project).appending(set)
        try saveDBDocument(history, for: project, documentType: "story_directions")
    }

    func loadStoryBeatBoards(for project: ProjectRecord) -> [StoryBeatBoard] {
        var boardsById: [String: StoryBeatBoard] = [:]
        for var board in loadDBDocuments(StoryBeatBoard.self, for: project, documentType: "story_beat_board") {
            if board.projectId.isEmpty {
                board.projectId = project.projectId
            }
            boardsById[board.beatBoardId] = board
        }
        return boardsById.values
            .sorted { lhs, rhs in
                let lhsDate = lhs.generatedAt.isEmpty ? lhs.updatedAt : lhs.generatedAt
                let rhsDate = rhs.generatedAt.isEmpty ? rhs.updatedAt : rhs.generatedAt
                if lhsDate == rhsDate {
                    return lhs.beatBoardId < rhs.beatBoardId
                }
                return lhsDate > rhsDate
            }
    }

    func loadStoryBeatBoard(for project: ProjectRecord, beatBoardId: String?) -> StoryBeatBoard {
        let trimmed = beatBoardId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty,
           var board = loadDBDocument(StoryBeatBoard.self, for: project, documentType: "story_beat_board", documentId: trimmed) {
            if board.projectId.isEmpty {
                board.projectId = project.projectId
            }
            return board
        }
        return loadStoryBeatBoards(for: project).first ?? StoryBeatBoard.empty(projectId: project.projectId)
    }

    func saveStoryBeatBoard(_ board: StoryBeatBoard, for project: ProjectRecord) throws {
        try saveDBDocument(board, for: project, documentType: "story_beat_board", documentId: board.beatBoardId)
    }

    func loadStorySequenceStrip(for project: ProjectRecord, beatBoardId: String? = nil) -> StorySequenceStripDocument {
        let trimmed = beatBoardId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty,
           var document = loadDBDocument(StorySequenceStripDocument.self, for: project, documentType: "story_sequence_strip", documentId: trimmed) {
            if document.projectId.isEmpty {
                document.projectId = project.projectId
            }
            return document
        }
        if var document = loadDBDocument(StorySequenceStripDocument.self, for: project, documentType: "story_sequence_strip", documentId: "default") {
            if document.projectId.isEmpty {
                document.projectId = project.projectId
            }
            if !trimmed.isEmpty, document.beatBoardId.isEmpty {
                document.beatBoardId = trimmed
            }
            return document
        }
        return StorySequenceStripDocument.empty(projectId: project.projectId)
    }

    func saveStorySequenceStrip(_ strip: StorySequenceStripDocument, for project: ProjectRecord) throws {
        let beatBoardId = strip.beatBoardId.trimmingCharacters(in: .whitespacesAndNewlines)
        try saveDBDocument(
            strip,
            for: project,
            documentType: "story_sequence_strip",
            documentId: beatBoardId.isEmpty ? "default" : beatBoardId
        )
    }

    func loadProjectStory(for project: ProjectRecord) -> ProjectStoryDocument {
        (try? storySQLiteStore.loadProjectStory(for: project)) ?? ProjectStoryDocument.empty(projectId: project.projectId)
    }

    func saveProjectStory(_ story: ProjectStoryDocument, for project: ProjectRecord) throws {
        try storySQLiteStore.saveProjectStory(story, for: project)
    }

    func loadSceneStorySets(for project: ProjectRecord) -> [SceneStorySetDocument] {
        (try? storySQLiteStore.loadSceneStorySets(for: project)) ?? []
    }

    func loadSceneStorySet(for project: ProjectRecord, sceneStorySetId: String?) -> SceneStorySetDocument? {
        try? storySQLiteStore.loadSceneStorySet(for: project, sceneStorySetId: sceneStorySetId)
    }

    func saveSceneStorySet(_ set: SceneStorySetDocument, for project: ProjectRecord) throws {
        try storySQLiteStore.saveSceneStorySet(set, for: project)
    }

    func loadStoryGenerationSessions(for project: ProjectRecord) -> [StoryGenerationSessionDocument] {
        (try? storySQLiteStore.loadStoryGenerationSessions(for: project)) ?? []
    }

    func saveStoryGenerationSession(_ session: StoryGenerationSessionDocument, for project: ProjectRecord) throws {
        try storySQLiteStore.saveStoryGenerationSession(session, for: project)
    }

    func saveStoryGenerationRequestSnapshot(
        _ request: SceneStoryGenerateRequest,
        for project: ProjectRecord,
        generationSessionId: String,
        slotIndex: Int,
        attemptIndex: Int
    ) throws -> (relativePath: String, fingerprint: String) {
        let data = try JSONCoding.prettyEncoder.encode(request)
        let documentId = [
            safeIdentifier(generationSessionId),
            "slot_\(max(slotIndex, 1))",
            "attempt_\(max(attemptIndex, 1))"
        ].joined(separator: "_")
        try saveDBDocument(request, for: project, documentType: "story_generation_request", documentId: documentId)
        let relativePath = [
            "db",
            "project_documents",
            "story_generation_request",
            safeIdentifier(generationSessionId),
            documentId
        ].joined(separator: "/")
        return (relativePath, sha256Hex(data))
    }

    func loadProjectStoryLibrary(for project: ProjectRecord) -> ProjectStoryLibraryDocument {
        (try? storySQLiteStore.loadProjectStoryLibrary(for: project)) ?? .empty(projectId: project.projectId)
    }

    func saveProjectStoryLibrary(_ library: ProjectStoryLibraryDocument, for project: ProjectRecord) throws {
        try storySQLiteStore.saveProjectStoryLibrary(library, for: project)
    }

    func loadStorySignatures(for project: ProjectRecord) -> [StorySignatureDocument] {
        (try? storySQLiteStore.loadStorySignatures(for: project)) ?? []
    }

    func loadStorySignature(for project: ProjectRecord, storySignatureId: String?) -> StorySignatureDocument? {
        try? storySQLiteStore.loadStorySignature(for: project, storySignatureId: storySignatureId)
    }

    func saveStorySignature(_ signature: StorySignatureDocument, for project: ProjectRecord) throws {
        try storySQLiteStore.saveStorySignature(signature, for: project)
    }

    func loadProjectStoryVersion(for project: ProjectRecord, projectStoryId: String, storyVersionId: String) -> ProjectStoryVersionDocument? {
        try? storySQLiteStore.loadProjectStoryVersion(for: project, projectStoryId: projectStoryId, storyVersionId: storyVersionId)
    }

    func saveProjectStoryVersion(_ version: ProjectStoryVersionDocument, for project: ProjectRecord) throws {
        try storySQLiteStore.saveProjectStoryVersion(version, for: project)
    }

    func loadStoryPersistenceRecovery(for project: ProjectRecord) -> StoryPersistenceRecoveryDocument? {
        storySQLiteStore.loadRecovery(for: project)
    }

    func saveBeatTake(_ take: BeatTakeDocument, for project: ProjectRecord) throws {
        try saveDBDocument(take, for: project, documentType: "beat_take", documentId: take.takeId)
    }

    func loadSceneWorkspaces(for project: ProjectRecord) -> [SceneWorkspaceDocument] {
        loadDBDocuments(SceneWorkspaceDocument.self, for: project, documentType: "scene_workspace")
            .map { document in
                var document = document
                if document.projectId.isEmpty {
                    document.projectId = project.projectId
                }
                return document
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func loadSceneWorkspace(for project: ProjectRecord, sceneWorkspaceId: String?) -> SceneWorkspaceDocument {
        let trimmed = sceneWorkspaceId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty,
           var document = loadDBDocument(SceneWorkspaceDocument.self, for: project, documentType: "scene_workspace", documentId: trimmed) {
            if document.projectId.isEmpty {
                document.projectId = project.projectId
            }
            return document
        }
        return loadSceneWorkspaces(for: project).first ?? SceneWorkspaceDocument.empty(projectId: project.projectId)
    }

    func saveSceneWorkspace(_ workspace: SceneWorkspaceDocument, for project: ProjectRecord) throws {
        try saveDBDocument(workspace, for: project, documentType: "scene_workspace", documentId: workspace.sceneWorkspaceId)
    }

    func loadSceneAssets(for project: ProjectRecord) -> [SceneAssetDocument] {
        loadDBDocuments(SceneAssetDocument.self, for: project, documentType: "scene_asset")
            .map { document in
                var document = document
                if document.projectId.isEmpty {
                    document.projectId = project.projectId
                }
                return document
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func saveSceneAsset(_ asset: SceneAssetDocument, for project: ProjectRecord) throws {
        try saveDBDocument(asset, for: project, documentType: "scene_asset", documentId: asset.assetId)
    }

    func loadVideoChains(for project: ProjectRecord) -> [VideoChainDocument] {
        loadVideoChainsWithDiagnostics(for: project).chains
    }

    func loadVideoChainsWithDiagnostics(for project: ProjectRecord) -> VideoChainLoadResult {
        var chainsById: [String: VideoChainDocument] = [:]
        for var document in loadDBDocuments(VideoChainDocument.self, for: project, documentType: "video_chain") {
            if document.projectId.isEmpty {
                document.projectId = project.projectId
            }
            guard !document.chainId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            chainsById[document.chainId] = document
        }

        return VideoChainLoadResult(
            chains: Array(chainsById.values).sorted { $0.updatedAt > $1.updatedAt },
            issues: []
        )
    }

    func loadVideoChain(for project: ProjectRecord, chainId: String?) -> VideoChainDocument {
        let trimmed = chainId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let loaded = loadVideoChainsWithDiagnostics(for: project)
        if !trimmed.isEmpty,
           let selected = loaded.chains.first(where: { $0.chainId == trimmed }) {
            return selected
        }
        return loaded.chains.first ?? .empty(projectId: project.projectId)
    }

    func saveVideoChain(_ chain: VideoChainDocument, for project: ProjectRecord) throws {
        try saveDBDocument(chain, for: project, documentType: "video_chain", documentId: chain.chainId)
    }

    func copyVideoChainKeyframe(
        from sourceURL: URL,
        for project: ProjectRecord,
        chainId: String,
        segmentId: String,
        role: String
    ) throws -> URL {
        let directory = videoChainKeyframesDirectory(for: project, chainId: chainId)
        try ensureDirectory(directory)
        let ext = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension
        let destination = directory.appendingPathComponent("\(safeIdentifier(segmentId))_\(safeIdentifier(role)).\(ext)")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return destination
    }

    func saveGeneratedVideoChainKeyframe(
        data: Data,
        for project: ProjectRecord,
        chainId: String,
        segmentId: String,
        role: String,
        mediaId: String,
        createdAt: String
    ) throws -> URL {
        let directory = videoChainKeyframesDirectory(for: project, chainId: chainId)
            .appendingPathComponent(safeIdentifier(segmentId), isDirectory: true)
            .appendingPathComponent("generated", isDirectory: true)
        try ensureDirectory(directory)
        let fingerprint = shortHash("\(chainId):\(segmentId):\(role):\(mediaId):\(createdAt)", length: 12)
        let destination = directory.appendingPathComponent(
            "\(safeIdentifier(role))_\(safeIdentifier(mediaId.isEmpty ? "source" : mediaId))_\(fingerprint).png"
        )
        try data.write(to: destination, options: [.atomic])
        return destination
    }

    func saveNormalizedVideoChainOpenAIInput(
        data: Data,
        for project: ProjectRecord,
        chainId: String,
        segmentId: String,
        role: String,
        sourceId: String,
        createdAt: String
    ) throws -> URL {
        let directory = videoChainOpenAIInputsDirectory(for: project, chainId: chainId, segmentId: segmentId)
        try ensureDirectory(directory)
        let fingerprint = shortHash("\(chainId):\(segmentId):\(role):\(sourceId):\(createdAt):\(sha256Hex(data))", length: 12)
        let destination = directory.appendingPathComponent(
            "\(safeIdentifier(role))_\(safeIdentifier(sourceId.isEmpty ? "source" : sourceId))_\(fingerprint).jpg"
        )
        try data.write(to: destination, options: [.atomic])
        return destination
    }

    func copyVideoChainClip(
        from sourceURL: URL,
        for project: ProjectRecord,
        chainId: String,
        segmentId: String
    ) throws -> URL {
        let directory = videoChainClipsDirectory(for: project, chainId: chainId)
        try ensureDirectory(directory)
        let ext = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        let destination = directory.appendingPathComponent("\(safeIdentifier(segmentId))_existing.\(ext)")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return destination
    }

    func loadStoryGenerationRunIndex(for project: ProjectRecord) -> StoryGenerationRunIndexDocument {
        guard var document = loadDBDocument(StoryGenerationRunIndexDocument.self, for: project, documentType: "story_generation_run_index") else {
            return StoryGenerationRunIndexDocument.empty(projectId: project.projectId)
        }
        if document.projectId.isEmpty {
            document.projectId = project.projectId
        }
        return document
    }

    func saveStoryGenerationRun(_ run: StoryGenerationRunDocument, for project: ProjectRecord) throws {
        try saveDBDocument(run, for: project, documentType: "story_generation_run", documentId: run.runId)
        var index = loadStoryGenerationRunIndex(for: project)
        index.runs.removeAll { $0.runId == run.runId }
        index.runs.insert(
            StoryGenerationRunIndexEntry(
                runId: run.runId,
                artifactType: run.artifactType,
                artifactId: run.artifactId,
                model: run.model,
                relativePath: "db/project_documents/story_generation_run/\(run.runId)",
                createdAt: run.createdAt
            ),
            at: 0
        )
        index.runs = Array(index.runs.prefix(80))
        index.updatedAt = DateFormats.now()
        try saveDBDocument(index, for: project, documentType: "story_generation_run_index")
    }

    // MARK: - Spend ledger (per-event rows + one rolled-up summary)

    func loadSpendLedgerSummary(for project: ProjectRecord) -> SpendLedgerSummaryDocument {
        var summary = loadDBDocument(
            SpendLedgerSummaryDocument.self,
            for: project,
            documentType: "spend_ledger_summary"
        ) ?? SpendLedgerSummaryDocument.empty(projectId: project.projectId)
        if summary.projectId.isEmpty {
            summary.projectId = project.projectId
        }
        return summary
    }

    /// Every ledger row, newest-first (the store orders by `updated_at DESC`).
    func loadSpendLedgerEntries(for project: ProjectRecord) -> [SpendLedgerEntry] {
        loadDBDocuments(SpendLedgerEntry.self, for: project, documentType: "spend_ledger_entry")
    }

    /// The authoritative dedupe check behind `recordSpend`'s fast in-memory
    /// window.
    func spendLedgerEntryExists(_ entryId: String, for project: ProjectRecord) -> Bool {
        (try? documentStore.documentExists(
            for: project,
            documentType: "spend_ledger_entry",
            documentId: entryId
        )) ?? false
    }

    /// One transaction for the entry row AND the folded summary — the ledger
    /// can never show a row its totals don't know about, or vice versa.
    func saveSpendLedgerEntry(
        _ entry: SpendLedgerEntry,
        summary: SpendLedgerSummaryDocument,
        for project: ProjectRecord
    ) throws {
        try documentStore.saveDocumentsAtomically(
            [
                ProjectDocumentBatchWrite(
                    data: try JSONCoding.encoder.encode(entry),
                    documentType: "spend_ledger_entry",
                    documentId: entry.entryId
                ),
                ProjectDocumentBatchWrite(
                    data: try JSONCoding.encoder.encode(summary),
                    documentType: "spend_ledger_summary"
                )
            ],
            for: project
        )
    }

    /// Persists only the summary (the acknowledgment watermark path).
    func saveSpendLedgerSummary(
        _ summary: SpendLedgerSummaryDocument,
        for project: ProjectRecord
    ) throws {
        try saveDBDocument(summary, for: project, documentType: "spend_ledger_summary")
    }

    func loadProjectArchiveMeaning(for project: ProjectRecord) -> ProjectArchiveMeaningGraph {
        guard var graph = loadDBDocument(ProjectArchiveMeaningGraph.self, for: project, documentType: "project_archive_meaning") else {
            return ProjectArchiveMeaningGraph.empty(projectId: project.projectId)
        }
        if graph.projectId.isEmpty {
            graph.projectId = project.projectId
        }
        return graph
    }

    func saveProjectArchiveMeaning(_ graph: ProjectArchiveMeaningGraph, for project: ProjectRecord) throws {
        try saveDBDocument(graph, for: project, documentType: "project_archive_meaning")
    }

    func loadStoryBeatSheet(for project: ProjectRecord) -> StoryBeatSheet {
        guard var sheet = loadDBDocument(StoryBeatSheet.self, for: project, documentType: "story_beat_sheet") else {
            return StoryBeatSheet.empty(projectId: project.projectId)
        }
        if sheet.projectId.isEmpty {
            sheet.projectId = project.projectId
        }
        return sheet
    }

    func saveStoryBeatSheet(_ sheet: StoryBeatSheet, for project: ProjectRecord) throws {
        try saveDBDocument(sheet, for: project, documentType: "story_beat_sheet")
    }

    func loadStoryAudioTrack(for project: ProjectRecord) -> StoryAudioTrackDocument {
        guard let data = loadDBDocumentData(for: project, documentType: "story_audio_track"),
              var document = try? StoryAudioTrackDocument.decode(from: data) else {
            return StoryAudioTrackDocument.empty(projectId: project.projectId)
        }
        if document.projectId.isEmpty {
            document.projectId = project.projectId
        }
        document.voicePresetId = StoryAudioVoiceCatalog.migratedPresetId(document.voicePresetId)
        return document
    }

    func saveStoryAudioTrack(_ track: StoryAudioTrackDocument, for project: ProjectRecord) throws {
        try saveDBDocumentData(track.encoded(), for: project, documentType: "story_audio_track")
    }

    func loadStoryAudioTracks(for project: ProjectRecord) -> StoryAudioTrackCollectionDocument {
        if let data = loadDBDocumentData(for: project, documentType: "story_audio_tracks"),
           var document = try? StoryAudioTrackCollectionDocument.decode(from: data) {
            if document.projectId.isEmpty {
                document.projectId = project.projectId
            }
            document.tracks = document.tracks.map { track in
                var upgraded = track
                if upgraded.projectId.isEmpty {
                    upgraded.projectId = project.projectId
                }
                if upgraded.sourceBeatIds == nil {
                    upgraded.sourceBeatIds = []
                }
                if upgraded.scope == nil {
                    upgraded.scope = upgraded.sourceBeatIds?.isEmpty == false ? "beat_aware_audio" : "global_project_audio"
                }
                upgraded.voicePresetId = StoryAudioVoiceCatalog.migratedPresetId(upgraded.voicePresetId)
                return upgraded
            }
            .sortedByStoryAudioRecency
            if document.activeTrackId.isEmpty {
                document.activeTrackId = document.tracks.first?.trackId ?? ""
            }
            return document
        }
        return StoryAudioTrackCollectionDocument.empty(projectId: project.projectId)
    }

    func saveStoryAudioTracks(_ document: StoryAudioTrackCollectionDocument, for project: ProjectRecord) throws {
        try saveDBDocumentData(document.encoded(), for: project, documentType: "story_audio_tracks")
    }

    func loadMediaObservations(for project: ProjectRecord) -> [String: ImageObservationResult] {
        (try? mediaSQLiteStore.loadMediaObservations(for: project)) ?? [:]
    }

    func saveMediaObservations(_ observationsById: [String: ImageObservationResult], for project: ProjectRecord) throws {
        try mediaSQLiteStore.saveMediaObservations(observationsById, for: project)
    }

    func makeSourceContext(from url: URL, kind: SourceContextKind, notes: String = "") -> SourceContextRecord {
        let bookmarkData = (try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)) ?? Data()
        let path = url.standardizedFileURL.path
        let now = DateFormats.now()
        return SourceContextRecord(
            sourceId: "source_context_\(shortHash("\(kind.rawValue):\(path)", length: 16))",
            kind: kind,
            title: url.lastPathComponent.isEmpty ? path : url.lastPathComponent,
            path: path,
            bookmarkDataBase64: bookmarkData.base64EncodedString(),
            notes: notes,
            addedAt: now,
            updatedAt: now
        )
    }

    func makeSourceNote(title: String, notes: String) -> SourceContextRecord {
        let now = DateFormats.now()
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return SourceContextRecord(
            sourceId: "source_context_note_\(UUID().uuidString.lowercased())",
            kind: .note,
            title: cleanedTitle.isEmpty ? "Source Note" : cleanedTitle,
            notes: notes,
            addedAt: now,
            updatedAt: now
        )
    }
}
