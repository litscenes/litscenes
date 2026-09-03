import Foundation
import SQLite3
import Testing
@testable import LitScenes

// Media items carry a content hash so a copied, renamed, or re-imported photo is
// the same image; legacy rows and inventories decode without it, and the column
// arrives through the V14 migration on projects created before it.

private func contentHashItem(mediaId: String, filename: String, derivativeKind: String? = nil, contentSha256: String = "") -> MediaItemRecord {
    MediaItemRecord(
        mediaId: mediaId,
        sourceId: derivativeKind == nil ? "source_room" : MediaItemRecord.generatedMediaSourceId,
        kind: .image,
        filename: filename,
        path: "/tmp/room/\(filename)",
        relativePath: filename,
        byteCount: 2048,
        modifiedAt: "2026-07-28T09:00:00.000Z",
        width: 1920,
        height: 1080,
        thumbnailPath: "library/thumbnails/\(filename).jpg",
        scannedAt: "2026-07-28T09:00:01.000Z",
        derivativeKind: derivativeKind,
        contentSha256: contentSha256
    )
}

private func mediaItemsTableSQLForHash(_ databaseURL: URL) throws -> String {
    try LitScenesDesktopDatabase.withConnection(url: databaseURL, context: "Test DB") { connection in
        var statement: OpaquePointer?
        let sql = "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'media_items';"
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return "" }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return "" }
        return litScenesSQLiteColumnText(statement, 0)
    }
}

private func indexExists(_ databaseURL: URL, name: String) throws -> Bool {
    try LitScenesDesktopDatabase.withConnection(url: databaseURL, context: "Test DB") { connection in
        var statement: OpaquePointer?
        let sql = "SELECT name FROM sqlite_master WHERE type = 'index' AND name = '\(name)';"
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return false }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW
    }
}

/// Rewrites `media_items` back to its pre-hash shape, rows and all, and forgets the
/// V14 migration, so the test exercises the table an older project carries.
private func downgradeMediaItemsToPreHashShape(_ databaseURL: URL) throws {
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
            CREATE TABLE media_items_pre_hash (
                project_id TEXT NOT NULL,
                media_id TEXT NOT NULL,
                item_order INTEGER NOT NULL DEFAULT 0 CHECK(item_order >= 0),
                source_id TEXT NOT NULL DEFAULT '',
                kind TEXT NOT NULL CHECK(kind IN ('image', 'video', 'audio')),
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
            "INSERT INTO media_items_pre_hash (\(columns)) SELECT \(columns) FROM media_items;",
            "DROP TABLE media_items;",
            "ALTER TABLE media_items_pre_hash RENAME TO media_items;",
            "CREATE INDEX IF NOT EXISTS media_items_project_order_idx ON media_items(project_id, item_order);",
            "DELETE FROM project_schema_migrations WHERE version = '\(LitScenesDesktopDatabase.projectMediaContentHashSchemaVersion)';"
        ]
        for statement in statements {
            try litScenesSQLiteExecute(connection, statement, context: "Test DB")
        }
    }
}

@Suite("Media content hash")
struct MediaContentHashTests {
    @Test("Legacy media rows decode without a content hash; the hash round-trips under its wire key")
    func tolerantDecodeAndRoundTrip() throws {
        let legacy = #"{"media_id":"m1","source_id":"src","kind":"image","filename":"a.jpg","path":"/tmp/a.jpg","relative_path":"a.jpg","byte_count":10,"modified_at":"","width":1,"height":1,"thumbnail_path":"","scanned_at":""}"#
        let decoded = try JSONCoding.decoder.decode(MediaItemRecord.self, from: Data(legacy.utf8))
        #expect(decoded.mediaId == "m1")
        #expect(decoded.contentSha256 == "")
        #expect(decoded.derivativeKind == nil)

        let hashed = contentHashItem(mediaId: "m2", filename: "b.jpg", contentSha256: "abc123")
        let encoded = try JSONCoding.encoder.encode(hashed)
        #expect(String(decoding: encoded, as: UTF8.self).contains("\"content_sha256\""))
        let back = try JSONCoding.decoder.decode(MediaItemRecord.self, from: encoded)
        #expect(back == hashed)

        let listData = try JSONCoding.encoder.encode([decoded, hashed])
        let listBack = try JSONCoding.decoder.decode([MediaItemRecord].self, from: listData)
        #expect(listBack.map(\.contentSha256) == ["", "abc123"])
    }

    @Test("Character sources are generated media that survive rescans and stay out of Creations")
    func characterSourceKind() {
        let source = contentHashItem(mediaId: "cs1", filename: "face.png", derivativeKind: MediaItemRecord.characterSourceDerivativeKind, contentSha256: "deadbeef")
        #expect(source.isGeneratedMedia)
        #expect(source.isCharacterSource)
        #expect(!source.isCharacterSheet)
        #expect(source.canBeEnabledContent)
        let groups = creationsInventory(items: [source], lenses: [])
        #expect(groups.isEmpty)
    }

    @Test("A fresh project database carries the content hash column and its index")
    func freshDatabaseHasTheColumn() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("litscenes_content_hash_fresh_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let projectLibrary = ProjectLibrary(root: root)
        let project = try projectLibrary.createProject(named: "Hashes")
        let databaseURL = try LitScenesDesktopDatabase.prepareProjectDatabase(for: project, projectLibrary: projectLibrary)
        #expect(try mediaItemsTableSQLForHash(databaseURL).contains("content_sha256"))
        #expect(try indexExists(databaseURL, name: "media_items_project_content_sha_idx"))

        let store = MediaLibraryStore(projectLibrary: projectLibrary)
        let item = contentHashItem(mediaId: "m_hashed", filename: "wall.jpg", contentSha256: "feedface")
        try store.saveInventory([item, contentHashItem(mediaId: "m_plain", filename: "door.jpg")], for: project)
        let loaded = store.loadInventory(for: project)
        #expect(loaded.first { $0.mediaId == "m_hashed" }?.contentSha256 == "feedface")
        #expect(loaded.first { $0.mediaId == "m_plain" }?.contentSha256 == "")
    }

    @Test("An older project database gains the column on open and keeps its rows")
    func existingDatabaseMigrates() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("litscenes_content_hash_migrate_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let projectLibrary = ProjectLibrary(root: root)
        let project = try projectLibrary.createProject(named: "Older")
        let databaseURL = try LitScenesDesktopDatabase.prepareProjectDatabase(for: project, projectLibrary: projectLibrary)
        let store = MediaLibraryStore(projectLibrary: projectLibrary)
        try store.saveInventory([contentHashItem(mediaId: "m_kept", filename: "kept.jpg")], for: project)

        try downgradeMediaItemsToPreHashShape(databaseURL)
        #expect(try mediaItemsTableSQLForHash(databaseURL).contains("content_sha256") == false)

        _ = try LitScenesDesktopDatabase.prepareProjectDatabase(for: project, projectLibrary: projectLibrary)
        #expect(try mediaItemsTableSQLForHash(databaseURL).contains("content_sha256"))
        #expect(try indexExists(databaseURL, name: "media_items_project_content_sha_idx"))
        let loaded = store.loadInventory(for: project)
        #expect(loaded.map(\.mediaId) == ["m_kept"])
        #expect(loaded.first?.contentSha256 == "")

        try store.saveInventory([contentHashItem(mediaId: "m_kept", filename: "kept.jpg", contentSha256: "cafe")], for: project)
        #expect(store.loadInventory(for: project).first?.contentSha256 == "cafe")
    }
}
