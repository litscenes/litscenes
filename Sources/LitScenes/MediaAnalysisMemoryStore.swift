import Foundation
import SQLite3

struct MediaAnalysisMemoryKey: Hashable {
    var schemaVersion: String = MediaObservationConstants.schemaVersion
    var promptVersion: String = MediaObservationConstants.promptVersion
    var thumbnailPolicyVersion: String = MediaObservationConstants.thumbnailPolicyVersion
    var visionInputKind: String = "thumbnail_base"
    var visionInputSha256: String

    var cacheKey: String {
        let basis = [
            schemaVersion,
            promptVersion,
            thumbnailPolicyVersion,
            visionInputKind,
            visionInputSha256
        ].joined(separator: "|")
        return "image_observation_\(sha256Hex(Data(basis.utf8)))"
    }

    static func current(visionInputSha256: String) -> MediaAnalysisMemoryKey {
        MediaAnalysisMemoryKey(visionInputSha256: visionInputSha256)
    }

    static func currentObservation(_ observation: ImageObservationResult) -> MediaAnalysisMemoryKey? {
        guard observation.isCurrentAestheticObservationVersion,
              !observation.visionInputSha256.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return MediaAnalysisMemoryKey(
            schemaVersion: observation.schemaVersion,
            promptVersion: observation.promptVersion,
            thumbnailPolicyVersion: observation.thumbnailPolicyVersion,
            visionInputKind: observation.visionInputKind.isEmpty ? "thumbnail_base" : observation.visionInputKind,
            visionInputSha256: observation.visionInputSha256
        )
    }
}

struct MediaAnalysisMemoryStore {
    static let schemaVersion = "litscenes.desktop.media_analysis_memory.v0.1"

    var databaseURL: URL = litScenesApplicationSupportDirectory()
        .appendingPathComponent("MediaAnalysisMemory.db")

    func loadObservation(for key: MediaAnalysisMemoryKey) throws -> ImageObservationResult? {
        try withConnection { connection in
            let sql = """
            SELECT observation_json
            FROM media_analysis_observations
            WHERE cache_key = ?
              AND schema_version = ?
              AND prompt_version = ?
              AND thumbnail_policy_version = ?
              AND vision_input_kind = ?
              AND vision_input_sha256 = ?
            LIMIT 1;
            """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw ScreenGraphError.capture("Media analysis memory lookup prepare failed: \(litScenesSQLiteMessage(connection))")
            }
            defer { sqlite3_finalize(statement) }
            bind(key, to: statement)
            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
            let json = litScenesSQLiteColumnText(statement, 0)
            guard let data = json.data(using: .utf8) else { return nil }
            let observation = try ImageObservationResult.decode(from: data)
            guard MediaAnalysisMemoryKey.currentObservation(observation)?.cacheKey == key.cacheKey else {
                return nil
            }
            return observation
        }
    }

    func saveObservation(_ observation: ImageObservationResult, for key: MediaAnalysisMemoryKey, sourceSha256: String = "") throws {
        guard observation.isCurrentAestheticObservationVersion,
              observation.visionInputSha256 == key.visionInputSha256 else {
            return
        }
        try withConnection { connection in
            try upsertObservation(observation, key: key, sourceSha256: sourceSha256, connection: connection)
        }
    }

    /// Second key: the ORIGINAL file's hash. A copy of the same photo whose 640px
    /// thumbnail re-encodes differently still finds its analysis.
    func loadObservation(sourceSha256: String) throws -> ImageObservationResult? {
        let sha = sourceSha256.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sha.isEmpty else { return nil }
        return try withConnection { connection in
            let sql = """
            SELECT observation_json
            FROM media_analysis_observations
            WHERE source_sha256 = ?
              AND schema_version = ?
              AND prompt_version = ?
              AND thumbnail_policy_version = ?
            ORDER BY updated_at DESC
            LIMIT 1;
            """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw ScreenGraphError.capture("Media analysis memory source lookup prepare failed: \(litScenesSQLiteMessage(connection))")
            }
            defer { sqlite3_finalize(statement) }
            litScenesSQLiteBindText(sha, to: 1, in: statement)
            litScenesSQLiteBindText(MediaObservationConstants.schemaVersion, to: 2, in: statement)
            litScenesSQLiteBindText(MediaObservationConstants.promptVersion, to: 3, in: statement)
            litScenesSQLiteBindText(MediaObservationConstants.thumbnailPolicyVersion, to: 4, in: statement)
            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
            let json = litScenesSQLiteColumnText(statement, 0)
            guard let data = json.data(using: .utf8) else { return nil }
            let observation = try ImageObservationResult.decode(from: data)
            guard observation.isCurrentAestheticObservationVersion else { return nil }
            return observation
        }
    }

    func bootstrapNeutralObservations(_ observationsById: [String: ImageObservationResult]) throws -> Int {
        var importedCount = 0
        try withConnection { connection in
            try litScenesSQLiteExecute(connection, "BEGIN IMMEDIATE;", context: "Media analysis memory")
            do {
                for observation in observationsById.values {
                    guard let key = MediaAnalysisMemoryKey.currentObservation(observation) else { continue }
                    try upsertObservation(observation, key: key, sourceSha256: observation.sourceImageSha256, connection: connection)
                    importedCount += 1
                }
                try litScenesSQLiteExecute(connection, "COMMIT;", context: "Media analysis memory")
            } catch {
                try? litScenesSQLiteExecute(connection, "ROLLBACK;", context: "Media analysis memory")
                throw error
            }
        }
        return importedCount
    }

    private func withConnection<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        try LitScenesDesktopDatabase.withConnection(
            url: databaseURL,
            context: "Media analysis memory"
        ) { connection in
            try ensureSchema(connection)
            return try body(connection)
        }
    }

    private func ensureSchema(_ connection: OpaquePointer) throws {
        try litScenesSQLiteExecute(connection, """
        CREATE TABLE IF NOT EXISTS media_analysis_memory_schema_migrations (
            version TEXT PRIMARY KEY,
            applied_at TEXT NOT NULL
        );
        """, context: "Media analysis memory")
        try litScenesSQLiteExecute(connection, """
        CREATE TABLE IF NOT EXISTS media_analysis_observations (
            cache_key TEXT PRIMARY KEY,
            schema_version TEXT NOT NULL,
            prompt_version TEXT NOT NULL,
            thumbnail_policy_version TEXT NOT NULL,
            vision_input_kind TEXT NOT NULL,
            vision_input_sha256 TEXT NOT NULL,
            vision_input_width INTEGER NOT NULL,
            vision_input_height INTEGER NOT NULL,
            vision_input_bytes INTEGER NOT NULL,
            observation_provider TEXT NOT NULL,
            model TEXT NOT NULL,
            observation_json TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        """, context: "Media analysis memory")
        try litScenesSQLiteExecute(
            connection,
            "CREATE INDEX IF NOT EXISTS media_analysis_observations_input_idx ON media_analysis_observations(vision_input_sha256, prompt_version, thumbnail_policy_version);",
            context: "Media analysis memory"
        )
        try ensureSourceHashColumn(connection)
        try litScenesSQLiteExecute(
            connection,
            "CREATE INDEX IF NOT EXISTS media_analysis_observations_source_idx ON media_analysis_observations(source_sha256, prompt_version, thumbnail_policy_version);",
            context: "Media analysis memory"
        )
        try insertMigration(
            connection,
            table: "media_analysis_memory_schema_migrations",
            version: Self.schemaVersion,
            context: "Media analysis memory"
        )
    }

    private func ensureSourceHashColumn(_ connection: OpaquePointer) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, "PRAGMA table_info(media_analysis_observations);", -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ScreenGraphError.capture("Media analysis memory table_info prepare failed: \(litScenesSQLiteMessage(connection))")
        }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            if litScenesSQLiteColumnText(statement, 1) == "source_sha256" { return }
        }
        try litScenesSQLiteExecute(
            connection,
            "ALTER TABLE media_analysis_observations ADD COLUMN source_sha256 TEXT NOT NULL DEFAULT '';",
            context: "Media analysis memory"
        )
    }

    private func insertMigration(
        _ connection: OpaquePointer,
        table: String,
        version: String,
        context: String
    ) throws {
        let sql = "INSERT OR IGNORE INTO \(table) (version, applied_at) VALUES (?, ?);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ScreenGraphError.capture("\(context) migration insert prepare failed: \(litScenesSQLiteMessage(connection))")
        }
        defer { sqlite3_finalize(statement) }
        litScenesSQLiteBindText(version, to: 1, in: statement)
        litScenesSQLiteBindText(DateFormats.now(), to: 2, in: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw ScreenGraphError.capture("\(context) migration insert failed: \(litScenesSQLiteMessage(connection))")
        }
    }

    private func upsertObservation(
        _ observation: ImageObservationResult,
        key: MediaAnalysisMemoryKey,
        sourceSha256: String = "",
        connection: OpaquePointer
    ) throws {
        let sanitized = sanitizedObservationTemplate(observation, key: key)
        let sourceHash = sourceSha256.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonData = try sanitized.encoded(pretty: true)
        guard let json = String(data: jsonData, encoding: .utf8) else {
            throw ScreenGraphError.capture("Media analysis memory could not encode observation JSON.")
        }
        let sql = """
        INSERT INTO media_analysis_observations (
            cache_key, schema_version, prompt_version, thumbnail_policy_version,
            vision_input_kind, vision_input_sha256, vision_input_width, vision_input_height,
            vision_input_bytes, observation_provider, model, observation_json, created_at, updated_at,
            source_sha256
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(cache_key) DO UPDATE SET
            schema_version = excluded.schema_version,
            prompt_version = excluded.prompt_version,
            thumbnail_policy_version = excluded.thumbnail_policy_version,
            vision_input_kind = excluded.vision_input_kind,
            vision_input_sha256 = excluded.vision_input_sha256,
            vision_input_width = excluded.vision_input_width,
            vision_input_height = excluded.vision_input_height,
            vision_input_bytes = excluded.vision_input_bytes,
            observation_provider = excluded.observation_provider,
            model = excluded.model,
            observation_json = excluded.observation_json,
            updated_at = excluded.updated_at,
            source_sha256 = CASE WHEN excluded.source_sha256 = '' THEN media_analysis_observations.source_sha256 ELSE excluded.source_sha256 END;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ScreenGraphError.capture("Media analysis memory upsert prepare failed: \(litScenesSQLiteMessage(connection))")
        }
        defer { sqlite3_finalize(statement) }
        litScenesSQLiteBindText(key.cacheKey, to: 1, in: statement)
        litScenesSQLiteBindText(key.schemaVersion, to: 2, in: statement)
        litScenesSQLiteBindText(key.promptVersion, to: 3, in: statement)
        litScenesSQLiteBindText(key.thumbnailPolicyVersion, to: 4, in: statement)
        litScenesSQLiteBindText(key.visionInputKind, to: 5, in: statement)
        litScenesSQLiteBindText(key.visionInputSha256, to: 6, in: statement)
        sqlite3_bind_int64(statement, 7, Int64(sanitized.visionInputWidth))
        sqlite3_bind_int64(statement, 8, Int64(sanitized.visionInputHeight))
        sqlite3_bind_int64(statement, 9, Int64(sanitized.visionInputBytes))
        litScenesSQLiteBindText(sanitized.observationProvider, to: 10, in: statement)
        litScenesSQLiteBindText(sanitized.model, to: 11, in: statement)
        litScenesSQLiteBindText(json, to: 12, in: statement)
        litScenesSQLiteBindText(sanitized.createdAt, to: 13, in: statement)
        litScenesSQLiteBindText(DateFormats.now(), to: 14, in: statement)
        litScenesSQLiteBindText(sourceHash, to: 15, in: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw ScreenGraphError.capture("Media analysis memory upsert failed: \(litScenesSQLiteMessage(connection))")
        }
    }

    private func sanitizedObservationTemplate(
        _ observation: ImageObservationResult,
        key: MediaAnalysisMemoryKey
    ) -> ImageObservationResult {
        var sanitized = observation
        sanitized.schemaVersion = key.schemaVersion
        sanitized.mediaId = ""
        sanitized.frameId = ""
        sanitized.sourcePath = ""
        sanitized.imageHash = key.visionInputSha256
        sanitized.promptVersion = key.promptVersion
        sanitized.createdAt = sanitized.createdAt.isEmpty ? DateFormats.now() : sanitized.createdAt
        sanitized.userProvidedContext = UserProvidedContext()
        sanitized.sourceImagePath = ""
        sanitized.sourceImageSha256 = ""
        sanitized.visionInputKind = key.visionInputKind
        sanitized.visionInputPath = ""
        sanitized.visionInputSha256 = key.visionInputSha256
        sanitized.visionThumbnailProfile = "base"
        sanitized.fullresVisionAllowed = false
        sanitized.thumbnailPolicyVersion = key.thumbnailPolicyVersion
        sanitized.detailPassUsed = false
        sanitized.detailPassReason = ""
        sanitized.detailObservationNotes = ""
        sanitized.objectDescriptionPassUsed = false
        sanitized.objectDescriptionPromptVersion = ""
        sanitized.detailVisionInputKind = ""
        sanitized.detailVisionInputPath = ""
        sanitized.detailVisionInputSha256 = ""
        sanitized.detailVisionInputWidth = 0
        sanitized.detailVisionInputHeight = 0
        sanitized.detailVisionInputBytes = 0
        sanitized.detailVisionThumbnailProfile = ""
        return sanitized
    }

    private func bind(_ key: MediaAnalysisMemoryKey, to statement: OpaquePointer) {
        litScenesSQLiteBindText(key.cacheKey, to: 1, in: statement)
        litScenesSQLiteBindText(key.schemaVersion, to: 2, in: statement)
        litScenesSQLiteBindText(key.promptVersion, to: 3, in: statement)
        litScenesSQLiteBindText(key.thumbnailPolicyVersion, to: 4, in: statement)
        litScenesSQLiteBindText(key.visionInputKind, to: 5, in: statement)
        litScenesSQLiteBindText(key.visionInputSha256, to: 6, in: statement)
    }
}
