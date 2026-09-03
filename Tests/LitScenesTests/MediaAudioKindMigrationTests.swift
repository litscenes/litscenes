import Foundation
import SQLite3
import Testing
@testable import LitScenes

// Audio became a media kind in a later schema, but `media_items` had shipped since
// the V5 media schema with CHECK(kind IN ('image', 'video')). Importing an mp3
// into a project created before today failed with "CHECK constraint failed".
// SQLite cannot alter a CHECK, so V12 rebuilds the table; these pin that the
// rebuild happens, keeps the rows it inherited, and lets audio through.

/// Rewrites `media_items` back to its pre-audio shape, rows and all, so the
/// test exercises the same table an existing project on disk carries.
private func downgradeMediaItemsToPreAudioShape(_ databaseURL: URL) throws {
    try LitScenesDesktopDatabase.withConnection(url: databaseURL, context: "Test DB") { connection in
        let columns = """
        project_id, media_id, item_order, source_id, kind, filename, path, relative_path,
        byte_count, modified_at, width, height, duration_seconds, nominal_frame_rate,
        thumbnail_path, video_strip_path, scanned_at, scan_error, derivative_kind,
        source_media_id, source_timestamp_seconds, frame_index, content_fingerprint,
        record_revision
        """
        let statements = [
            """
            CREATE TABLE media_items_pre_audio (
                project_id TEXT NOT NULL,
                media_id TEXT NOT NULL,
                item_order INTEGER NOT NULL DEFAULT 0 CHECK(item_order >= 0),
                source_id TEXT NOT NULL DEFAULT '',
                kind TEXT NOT NULL CHECK(kind IN ('image', 'video')),
                filename TEXT NOT NULL DEFAULT '',
                path TEXT NOT NULL DEFAULT '',
                relative_path TEXT NOT NULL DEFAULT '',
                byte_count INTEGER NOT NULL DEFAULT 0,
                modified_at TEXT NOT NULL DEFAULT '',
                width INTEGER NOT NULL DEFAULT 0,
                height INTEGER NOT NULL DEFAULT 0,
                duration_seconds REAL,
                nominal_frame_rate REAL,
                thumbnail_path TEXT NOT NULL DEFAULT '',
                video_strip_path TEXT,
                scanned_at TEXT NOT NULL DEFAULT '',
                scan_error TEXT,
                derivative_kind TEXT,
                source_media_id TEXT,
                source_timestamp_seconds REAL,
                frame_index INTEGER,
                content_fingerprint TEXT NOT NULL DEFAULT '',
                record_revision INTEGER NOT NULL DEFAULT 1 CHECK(record_revision > 0),
                PRIMARY KEY(project_id, media_id),
                FOREIGN KEY(project_id) REFERENCES project_identity(project_id) ON DELETE CASCADE
            );
            """,
            "INSERT INTO media_items_pre_audio (\(columns)) SELECT \(columns) FROM media_items;",
            "DROP TABLE media_items;",
            "ALTER TABLE media_items_pre_audio RENAME TO media_items;",
            "CREATE INDEX IF NOT EXISTS media_items_project_order_idx ON media_items(project_id, item_order);",
            "CREATE INDEX IF NOT EXISTS media_items_project_kind_idx ON media_items(project_id, kind);",
            "CREATE INDEX IF NOT EXISTS media_items_project_source_idx ON media_items(project_id, source_id);",
            "CREATE INDEX IF NOT EXISTS media_items_project_derivative_idx ON media_items(project_id, derivative_kind);",
            "CREATE INDEX IF NOT EXISTS media_items_project_source_media_idx ON media_items(project_id, source_media_id);",
            "DELETE FROM project_schema_migrations WHERE version = '\(LitScenesDesktopDatabase.projectAudioMediaKindSchemaVersion)';"
        ]
        for statement in statements {
            try litScenesSQLiteExecute(connection, statement, context: "Test DB")
        }
    }
}

private func mediaItemsTableSQL(_ databaseURL: URL) throws -> String {
    try LitScenesDesktopDatabase.withConnection(url: databaseURL, context: "Test DB") { connection in
        var statement: OpaquePointer?
        let sql = "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'media_items';"
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return ""
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return "" }
        return litScenesSQLiteColumnText(statement, 0)
    }
}

private func audioKindMigrationItem(mediaId: String, kind: MediaKind, filename: String) -> MediaItemRecord {
    MediaItemRecord(
        mediaId: mediaId,
        sourceId: "source_room",
        kind: kind,
        filename: filename,
        path: "/tmp/room/\(filename)",
        relativePath: filename,
        byteCount: 2048,
        modifiedAt: "2026-07-28T09:00:00.000Z",
        width: kind == .audio ? 0 : 1920,
        height: kind == .audio ? 0 : 1080,
        durationSeconds: kind == .image ? nil : 12.5,
        thumbnailPath: kind == .audio ? "" : "library/thumbnails/\(filename).jpg",
        scannedAt: "2026-07-28T09:00:01.000Z"
    )
}

@Test
func existingProjectDatabaseAcceptsAudioMediaAfterV12Migration() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("litscenes_audio_kind_migration_\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let projectLibrary = ProjectLibrary(root: root)
    let project = try projectLibrary.createProject(named: "Audio Kind Migration")
    let store = MediaLibraryStore(projectLibrary: projectLibrary)
    let databaseURL = try LitScenesDesktopDatabase.prepareProjectDatabase(for: project, projectLibrary: projectLibrary)

    let image = audioKindMigrationItem(mediaId: "media_image", kind: .image, filename: "wall.jpg")
    try store.saveInventory([image], for: project)

    try downgradeMediaItemsToPreAudioShape(databaseURL)
    #expect(try mediaItemsTableSQL(databaseURL).contains("'audio'") == false)

    // Re-preparing the database is what every project open does.
    _ = try LitScenesDesktopDatabase.prepareProjectDatabase(for: project, projectLibrary: projectLibrary)
    #expect(try mediaItemsTableSQL(databaseURL).contains("'audio'"))

    // The rows the table already held survive the rebuild.
    #expect(store.loadInventory(for: project).map(\.mediaId) == [image.mediaId])

    let audio = audioKindMigrationItem(mediaId: "media_audio", kind: .audio, filename: "score.wav")
    try store.saveInventory([image, audio], for: project)

    let loaded = store.loadInventory(for: project)
    #expect(loaded.map(\.mediaId) == [image.mediaId, audio.mediaId])
    #expect(loaded.first { $0.mediaId == audio.mediaId }?.kind == .audio)
    #expect(loaded.first { $0.mediaId == audio.mediaId }?.thumbnailPath.isEmpty == true)
}

@Test
func freshProjectDatabaseCarriesTheAudioMediaKindWithoutARebuild() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("litscenes_audio_kind_fresh_\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let projectLibrary = ProjectLibrary(root: root)
    let project = try projectLibrary.createProject(named: "Audio Kind Fresh")
    let databaseURL = try LitScenesDesktopDatabase.prepareProjectDatabase(for: project, projectLibrary: projectLibrary)

    #expect(try mediaItemsTableSQL(databaseURL).contains("'audio'"))

    let store = MediaLibraryStore(projectLibrary: projectLibrary)
    let audio = audioKindMigrationItem(mediaId: "media_audio", kind: .audio, filename: "cue.wav")
    try store.saveInventory([audio], for: project)
    #expect(store.loadInventory(for: project).first?.kind == .audio)
}
