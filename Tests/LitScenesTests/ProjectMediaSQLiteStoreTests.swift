import Foundation
import SQLite3
import Testing
@testable import LitScenes

@Test
func projectMediaLegacyJSONMigratesIntoTypedSQLiteTables() throws {
    let fixture = try makeProjectMediaSQLiteFixture()
    let source = mediaSQLiteSource()
    let video = mediaSQLiteItem(
        mediaId: "media_video",
        sourceId: source.sourceId,
        kind: .video,
        filename: "workshop.mov",
        relativePath: "workshop.mov",
        durationSeconds: 42,
        nominalFrameRate: 24,
        videoStripPath: "library/video_strips/workshop.jpg"
    )
    let image = mediaSQLiteItem(
        mediaId: "media_image",
        sourceId: source.sourceId,
        kind: .image,
        filename: "bench.jpg",
        relativePath: "bench.jpg"
    )
    let frame = mediaSQLiteItem(
        mediaId: "media_frame",
        sourceId: source.sourceId,
        kind: .image,
        filename: "workshop_frame.jpg",
        relativePath: "video_frames/media_video/workshop_frame.jpg",
        derivativeKind: MediaItemRecord.videoFrameDerivativeKind,
        sourceMediaId: video.mediaId,
        sourceTimestampSeconds: 12.5,
        frameIndex: 3
    )
    let curation = MediaCurationRecord(
        mediaId: image.mediaId,
        rejected: true,
        tags: ["archive", "workbench", "archive"],
        notes: "Use only for texture.",
        updatedAt: "2026-06-26T20:00:03.000Z"
    )
    let observation = mediaSQLiteObservation(mediaId: image.mediaId)

    try fixture.documentStore.saveDocument(
        MediaSourceDocument(projectId: fixture.project.projectId, sources: [source]),
        for: fixture.project,
        documentType: "media_sources"
    )
    try fixture.documentStore.saveDocument(
        MediaInventoryDocument(
            projectId: fixture.project.projectId,
            scannedAt: "2026-06-26T20:00:02.000Z",
            items: [video, image, frame]
        ),
        for: fixture.project,
        documentType: "media_inventory"
    )
    try fixture.documentStore.saveDocument(
        MediaCurationDocument(projectId: fixture.project.projectId, records: [curation]),
        for: fixture.project,
        documentType: "media_curation"
    )
    try fixture.documentStore.saveDocument(
        MediaObservationDocument(
            projectId: fixture.project.projectId,
            generatedAt: "2026-06-26T20:00:04.000Z",
            observations: [observation]
        ),
        for: fixture.project,
        documentType: "media_observations"
    )

    let loadedSources = fixture.mediaStore.loadSources(for: fixture.project)
    let loadedItems = fixture.mediaStore.loadInventory(for: fixture.project)
    let loadedCuration = fixture.mediaStore.loadCuration(for: fixture.project)
    let loadedObservations = fixture.contextStore.loadMediaObservations(for: fixture.project)

    #expect(loadedSources.map(\.sourceId) == [source.sourceId])
    #expect(loadedItems.map(\.mediaId) == [video.mediaId, image.mediaId, frame.mediaId])
    #expect(loadedItems.first { $0.mediaId == frame.mediaId }?.derivativeKind == MediaItemRecord.videoFrameDerivativeKind)
    #expect(loadedItems.first { $0.mediaId == frame.mediaId }?.sourceTimestampSeconds == 12.5)
    #expect(loadedItems.first { $0.mediaId == frame.mediaId }?.frameIndex == 3)
    #expect(loadedCuration[image.mediaId]?.rejected == true)
    #expect(loadedCuration[image.mediaId]?.tags == ["archive", "workbench"])
    #expect(loadedObservations[image.mediaId]?.plainCaption == "Hands over a red workbench.")
    #expect(loadedObservations[image.mediaId]?.objects == ["hands", "red workbench"])
    #expect(loadedObservations[image.mediaId]?.visibleText.first?.text == "OPEN")
    #expect(loadedObservations[image.mediaId]?.logosBrandsOrganizations.first?.name == "Rainforge")
    #expect(loadedObservations[image.mediaId]?.eventContext.eventType == "workshop")
    #expect(loadedObservations[image.mediaId]?.userProvidedContext.domainTags == ["craft"])

    #expect(try mediaSQLiteScalarInt(fixture.databaseURL, "SELECT COUNT(*) FROM project_media_state WHERE project_id = ?;", [fixture.project.projectId]) == 1)
    #expect(try mediaSQLiteScalarInt(fixture.databaseURL, "SELECT COUNT(*) FROM media_sources WHERE project_id = ?;", [fixture.project.projectId]) == 1)
    #expect(try mediaSQLiteScalarInt(fixture.databaseURL, "SELECT COUNT(*) FROM media_items WHERE project_id = ?;", [fixture.project.projectId]) == 3)
    #expect(try mediaSQLiteScalarInt(fixture.databaseURL, "SELECT COUNT(*) FROM media_curation WHERE project_id = ?;", [fixture.project.projectId]) == 1)
    #expect(try mediaSQLiteScalarInt(fixture.databaseURL, "SELECT COUNT(*) FROM media_curation_tags WHERE project_id = ?;", [fixture.project.projectId]) == 2)
    #expect(try mediaSQLiteScalarInt(fixture.databaseURL, "SELECT COUNT(*) FROM media_observations WHERE project_id = ?;", [fixture.project.projectId]) == 1)
    #expect(try mediaSQLiteScalarInt(fixture.databaseURL, "SELECT COUNT(*) FROM media_observation_terms WHERE project_id = ? AND term_kind = ?;", [fixture.project.projectId, "objects"]) == 2)
    #expect(try mediaSQLiteScalarInt(fixture.databaseURL, "SELECT COUNT(*) FROM media_observation_visible_text WHERE project_id = ?;", [fixture.project.projectId]) == 1)
    #expect(try mediaSQLiteScalarInt(fixture.databaseURL, "SELECT COUNT(*) FROM media_observation_domain_entities WHERE project_id = ?;", [fixture.project.projectId]) == 1)
    #expect(try mediaSQLiteScalarInt(fixture.databaseURL, "SELECT COUNT(*) FROM media_observation_flags_symbols WHERE project_id = ?;", [fixture.project.projectId]) == 1)
    #expect(try mediaSQLiteScalarInt(fixture.databaseURL, "SELECT COUNT(*) FROM media_observation_uncertainties WHERE project_id = ?;", [fixture.project.projectId]) == 1)
}

@Test
func projectMediaTypedSavesDoNotRewriteLegacyAggregateDocuments() throws {
    let fixture = try makeProjectMediaSQLiteFixture()
    let source = mediaSQLiteSource()
    let first = mediaSQLiteItem(mediaId: "media_first", sourceId: source.sourceId, kind: .image, filename: "first.jpg", relativePath: "first.jpg")
    let second = mediaSQLiteItem(mediaId: "media_second", sourceId: source.sourceId, kind: .image, filename: "second.jpg", relativePath: "second.jpg")

    try fixture.documentStore.saveDocument(
        MediaInventoryDocument(
            projectId: fixture.project.projectId,
            scannedAt: "2026-06-26T20:00:02.000Z",
            items: [first]
        ),
        for: fixture.project,
        documentType: "media_inventory"
    )

    #expect(fixture.mediaStore.loadInventory(for: fixture.project).map(\.mediaId) == [first.mediaId])
    try fixture.mediaStore.saveInventory([first, second], for: fixture.project)

    let typedIds = fixture.mediaStore.loadInventory(for: fixture.project).map(\.mediaId)
    let legacy = try fixture.documentStore.loadDocument(
        MediaInventoryDocument.self,
        for: fixture.project,
        documentType: "media_inventory"
    )

    #expect(typedIds == [first.mediaId, second.mediaId])
    #expect(legacy?.items.map(\.mediaId) == [first.mediaId])
    #expect(try mediaSQLiteScalarInt(fixture.databaseURL, "SELECT COUNT(*) FROM media_items WHERE project_id = ?;", [fixture.project.projectId]) == 2)
    #expect(try mediaSQLiteScalarInt(fixture.databaseURL, "SELECT COUNT(*) FROM project_documents WHERE project_id = ? AND document_type = ?;", [fixture.project.projectId, "media_inventory"]) == 1)
}

private struct ProjectMediaSQLiteFixture {
    let root: URL
    let projectLibrary: ProjectLibrary
    let project: ProjectRecord
    let mediaStore: MediaLibraryStore
    let contextStore: ProjectContextStore
    let documentStore: ProjectSQLiteDocumentStore
    let databaseURL: URL
}

private enum ProjectMediaSQLiteTestError: Error {
    case sqliteOpen(String)
    case sqlitePrepare(String)
}

private func makeProjectMediaSQLiteFixture() throws -> ProjectMediaSQLiteFixture {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("litscenes_project_media_sqlite_\(UUID().uuidString)", isDirectory: true)
    let projectLibrary = ProjectLibrary(root: root)
    let project = try projectLibrary.createProject(named: "Project Media SQLite")
    return ProjectMediaSQLiteFixture(
        root: root,
        projectLibrary: projectLibrary,
        project: project,
        mediaStore: MediaLibraryStore(projectLibrary: projectLibrary),
        contextStore: ProjectContextStore(projectLibrary: projectLibrary),
        documentStore: ProjectSQLiteDocumentStore(projectLibrary: projectLibrary),
        databaseURL: LitScenesDesktopDatabase.projectDatabaseURL(for: project, projectLibrary: projectLibrary)
    )
}

private func mediaSQLiteSource() -> MediaSourceRecord {
    MediaSourceRecord(
        sourceId: "source_workshop",
        displayName: "Workshop",
        path: "/tmp/workshop",
        sourceKind: .folder,
        bookmarkDataBase64: "bookmark",
        addedAt: "2026-06-26T20:00:00.000Z",
        lastScannedAt: "2026-06-26T20:00:01.000Z"
    )
}

private func mediaSQLiteItem(
    mediaId: String,
    sourceId: String,
    kind: MediaKind,
    filename: String,
    relativePath: String,
    durationSeconds: Double? = nil,
    nominalFrameRate: Double? = nil,
    videoStripPath: String? = nil,
    derivativeKind: String? = nil,
    sourceMediaId: String? = nil,
    sourceTimestampSeconds: Double? = nil,
    frameIndex: Int? = nil
) -> MediaItemRecord {
    MediaItemRecord(
        mediaId: mediaId,
        sourceId: sourceId,
        kind: kind,
        filename: filename,
        path: "/tmp/workshop/\(relativePath)",
        relativePath: relativePath,
        byteCount: 1234,
        modifiedAt: "2026-06-26T20:00:00.000Z",
        width: 1280,
        height: 720,
        durationSeconds: durationSeconds,
        nominalFrameRate: nominalFrameRate,
        thumbnailPath: "library/thumbnails/\(filename).jpg",
        videoStripPath: videoStripPath,
        scannedAt: "2026-06-26T20:00:02.000Z",
        scanError: nil,
        derivativeKind: derivativeKind,
        sourceMediaId: sourceMediaId,
        sourceTimestampSeconds: sourceTimestampSeconds,
        frameIndex: frameIndex
    )
}

private func mediaSQLiteObservation(mediaId: String) -> ImageObservationResult {
    var observation = ImageObservationResult()
    observation.mediaId = mediaId
    observation.frameId = "frame_1"
    observation.sourcePath = "/tmp/workshop/bench.jpg"
    observation.imageHash = "image_hash"
    observation.observationProvider = "openai"
    observation.model = "test-model"
    observation.createdAt = "2026-06-26T20:00:04.000Z"
    observation.plainCaption = "Hands over a red workbench."
    observation.literalDescription = "Two hands rest above a red enamel workbench."
    observation.objects = ["hands", "red workbench"]
    observation.objectDescriptions = [
        ImageObjectDescription(accurateTitle: "Red workbench", thoroughDescription: "A worn red enamel workbench with hand tools.")
    ]
    observation.peopleVisible = true
    observation.peopleCountEstimate = 1
    observation.peopleRolesVisible = ["craftsperson"]
    observation.activities = ["repair"]
    observation.setting = "workshop"
    observation.lighting = "soft daylight"
    observation.mood = ["patient"]
    observation.materials = ["red enamel", "wood"]
    observation.visualSpecificity = ["worn surface"]
    observation.paletteTerms = ["red", "steel"]
    observation.placeCues = ["workbench"]
    observation.eraCues = ["contemporary"]
    observation.motifCues = ["hands"]
    observation.energyCues = ["focused"]
    observation.compositionCues = ["close-up"]
    observation.visibleText = [VisibleTextObservation(text: "OPEN", whereSeen: "small sign", confidence0To1: 0.81)]
    observation.logosBrandsOrganizations = [DomainEntity(name: "Rainforge", kind: "brand", visibleEvidence: "tool label", confidence0To1: 0.7)]
    observation.flagsSymbolsSignage = [FlagSymbolSignage(name: "Open sign", kind: "signage", visibleEvidence: "visible text", confidence0To1: 0.82)]
    observation.eventContext = EventContext(eventType: "workshop", eventNameGuess: "repair day", competitionOrProgramGuess: "", why: "Tools and hands suggest a workshop.", confidence0To1: 0.75)
    observation.mediaRole = "evidence"
    observation.mediaRoleAssessment = MediaRoleAssessment(mediaRole: "evidence", why: "It documents the craft surface.", confidence0To1: 0.9)
    observation.sourceKindNotes = "Photo."
    observation.domainTags = ["craft"]
    observation.localContextTags = ["bench"]
    observation.technicalContextTags = ["still"]
    observation.storyObservationTags = ["material care"]
    observation.possibleMeanings = ["craft as care"]
    observation.negativeConstraints = ["Do not imply a factory."]
    observation.uncertainties = [ObservationUncertainty(field: "person", question: "Whose hands are visible?", whyUncertain: "Face is not visible.")]
    observation.humanReview = HumanOverride(needsReview: true, reviewReason: "Identity unknown.", suggestedQuestion: "Who is shown?")
    observation.detailPassUsed = true
    observation.detailPassReason = "Small text."
    observation.detailObservationNotes = "Read sign text."
    observation.objectDescriptionPassUsed = true
    observation.objectDescriptionPromptVersion = "test-object-prompt"
    observation.userProvidedContext = UserProvidedContext(
        knownContext: "Public repair day.",
        domainTags: ["craft"],
        preferredMediaRole: "evidence",
        notes: "Use respectfully."
    )
    observation.sourceImagePath = "/tmp/workshop/bench.jpg"
    observation.sourceImageSha256 = "source_sha"
    observation.visionInputKind = "thumbnail"
    observation.visionInputPath = "/tmp/workshop/thumb.jpg"
    observation.visionInputSha256 = "vision_sha"
    observation.visionInputWidth = 640
    observation.visionInputHeight = 360
    observation.visionInputBytes = 3456
    observation.visionThumbnailProfile = "base"
    observation.fullresVisionAllowed = false
    observation.detailVisionInputKind = "detail"
    observation.detailVisionInputPath = "/tmp/workshop/detail.jpg"
    observation.detailVisionInputSha256 = "detail_sha"
    observation.detailVisionInputWidth = 1280
    observation.detailVisionInputHeight = 720
    observation.detailVisionInputBytes = 7890
    observation.detailVisionThumbnailProfile = "detail"
    return observation
}

private func mediaSQLiteScalarInt(_ databaseURL: URL, _ sql: String, _ bindings: [String] = []) throws -> Int {
    var connection: OpaquePointer?
    guard sqlite3_open_v2(databaseURL.path, &connection, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
        throw ProjectMediaSQLiteTestError.sqliteOpen(mediaSQLiteErrorMessage(connection))
    }
    defer {
        sqlite3_close(connection)
    }

    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK else {
        throw ProjectMediaSQLiteTestError.sqlitePrepare(mediaSQLiteErrorMessage(connection))
    }
    defer {
        sqlite3_finalize(statement)
    }

    for (index, value) in bindings.enumerated() {
        sqlite3_bind_text(statement, Int32(index + 1), value, -1, litScenesSQLiteTransient)
    }
    guard sqlite3_step(statement) == SQLITE_ROW else {
        return 0
    }
    return Int(sqlite3_column_int(statement, 0))
}

private func mediaSQLiteErrorMessage(_ connection: OpaquePointer?) -> String {
    guard let connection else { return "unknown SQLite error" }
    return String(cString: sqlite3_errmsg(connection))
}
