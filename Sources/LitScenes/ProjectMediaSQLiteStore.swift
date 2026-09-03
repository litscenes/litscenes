import Foundation
import SQLite3

private enum ProjectMediaSQLite {
    static func withProjectConnection<T>(
        _ project: ProjectRecord,
        projectLibrary: ProjectLibrary,
        readOnly: Bool,
        context: String,
        _ body: (OpaquePointer) throws -> T
    ) throws -> T {
        let url = try LitScenesDesktopDatabase.prepareProjectDatabase(for: project, projectLibrary: projectLibrary)
        let flags = readOnly
            ? SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
            : SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        return try LitScenesDesktopDatabase.withConnection(url: url, flags: flags, context: context, body)
    }

    static func writeTransaction(
        project: ProjectRecord,
        projectLibrary: ProjectLibrary,
        context: String,
        _ body: @escaping (OpaquePointer) throws -> Void
    ) throws {
        try withProjectConnection(project, projectLibrary: projectLibrary, readOnly: false, context: context) { connection in
            try beginImmediate(connection, context: context)
            do {
                try body(connection)
                try integrityChecks(connection, context: context)
                try litScenesSQLiteExecute(connection, "COMMIT;", context: context)
            } catch {
                try? litScenesSQLiteExecute(connection, "ROLLBACK;", context: context)
                throw error
            }
        }
    }

    static func beginImmediate(_ connection: OpaquePointer, context: String) throws {
        let delays: [TimeInterval] = [0, 0.1, 0.25, 0.5, 1.0, 2.0]
        var lastMessage = ""
        for delay in delays {
            if delay > 0 {
                Thread.sleep(forTimeInterval: delay)
            }
            let result = sqlite3_exec(connection, "BEGIN IMMEDIATE;", nil, nil, nil)
            if result == SQLITE_OK {
                return
            }
            lastMessage = litScenesSQLiteMessage(connection)
            guard result == SQLITE_BUSY || result == SQLITE_LOCKED else {
                throw ScreenGraphError.capture("\(context) begin failed: \(lastMessage)")
            }
        }
        throw ScreenGraphError.capture("\(context) begin failed after busy retries: \(lastMessage)")
    }

    static func integrityChecks(_ connection: OpaquePointer, context: String) throws {
        let quickCheck = try optionalString(connection, sql: "PRAGMA quick_check;", bindings: [], context: context) ?? ""
        guard quickCheck == "ok" else {
            throw ScreenGraphError.capture("\(context) quick_check failed: \(quickCheck)")
        }
        let failureCount = try foreignKeyViolationCount(connection, context: context)
        guard failureCount == 0 else {
            throw ScreenGraphError.capture("\(context) foreign_key_check failed: \(failureCount) violation(s)")
        }
    }

    static func execute(_ sql: String, connection: OpaquePointer, bindings: [Any?], context: String) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ScreenGraphError.capture("\(context) prepare failed: \(litScenesSQLiteMessage(connection))")
        }
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw ScreenGraphError.capture("\(context) step failed: \(litScenesSQLiteMessage(connection))")
        }
    }

    static func optionalString(
        _ connection: OpaquePointer,
        sql: String,
        bindings: [Any?],
        context: String
    ) throws -> String? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ScreenGraphError.capture("\(context) query prepare failed: \(litScenesSQLiteMessage(connection))")
        }
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        guard sqlite3_column_type(statement, 0) != SQLITE_NULL else { return nil }
        return litScenesSQLiteColumnText(statement, 0)
    }

    static func scalarInt(_ connection: OpaquePointer, sql: String, bindings: [Any?], context: String) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ScreenGraphError.capture("\(context) scalar prepare failed: \(litScenesSQLiteMessage(connection))")
        }
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(statement, 0))
    }

    static func query<T>(
        _ connection: OpaquePointer,
        sql: String,
        bindings: [Any?],
        context: String,
        map: (OpaquePointer) throws -> T
    ) throws -> [T] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ScreenGraphError.capture("\(context) query prepare failed: \(litScenesSQLiteMessage(connection))")
        }
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        var output: [T] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                output.append(try map(statement))
            } else if result == SQLITE_DONE {
                return output
            } else {
                throw ScreenGraphError.capture("\(context) query failed: \(litScenesSQLiteMessage(connection))")
            }
        }
    }

    static func columnString(_ statement: OpaquePointer, _ index: Int32) -> String {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return "" }
        return litScenesSQLiteColumnText(statement, index)
    }

    static func optionalColumnString(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        let value = litScenesSQLiteColumnText(statement, index).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    static func optionalColumnInt(_ statement: OpaquePointer, _ index: Int32) -> Int? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return Int(sqlite3_column_int(statement, index))
    }

    static func optionalColumnDouble(_ statement: OpaquePointer, _ index: Int32) -> Double? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_double(statement, index)
    }

    private static func foreignKeyViolationCount(_ connection: OpaquePointer, context: String) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, "PRAGMA foreign_key_check;", -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ScreenGraphError.capture("\(context) foreign_key_check prepare failed: \(litScenesSQLiteMessage(connection))")
        }
        defer { sqlite3_finalize(statement) }
        var count = 0
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                count += 1
            } else if result == SQLITE_DONE {
                return count
            } else {
                throw ScreenGraphError.capture("\(context) foreign_key_check failed: \(litScenesSQLiteMessage(connection))")
            }
        }
    }

    private static func bind(_ bindings: [Any?], to statement: OpaquePointer) throws {
        for (index, value) in bindings.enumerated() {
            let sqliteIndex = Int32(index + 1)
            switch value {
            case nil:
                sqlite3_bind_null(statement, sqliteIndex)
            case let value as String:
                litScenesSQLiteBindText(value, to: sqliteIndex, in: statement)
            case let value as Int:
                sqlite3_bind_int64(statement, sqliteIndex, sqlite3_int64(value))
            case let value as Int64:
                sqlite3_bind_int64(statement, sqliteIndex, value)
            case let value as Double:
                sqlite3_bind_double(statement, sqliteIndex, value)
            case let value as Bool:
                sqlite3_bind_int(statement, sqliteIndex, value ? 1 : 0)
            default:
                throw ScreenGraphError.capture("Unsupported SQLite binding type at index \(index + 1).")
            }
        }
    }
}

struct ProjectMediaSQLiteStore {
    private static let queue = DispatchQueue(label: "local.litscenes.project-media-sqlite-store")
    private let context = "Project Media DB"
    let projectLibrary: ProjectLibrary

    init(projectLibrary: ProjectLibrary = ProjectLibrary()) {
        self.projectLibrary = projectLibrary
    }

    func loadSources(for project: ProjectRecord) throws -> [MediaSourceRecord] {
        try importLegacyMediaIfNeeded(for: project)
        return try ProjectMediaSQLite.withProjectConnection(
            project,
            projectLibrary: projectLibrary,
            readOnly: true,
            context: context
        ) { connection in
            try loadTypedSources(for: project, connection: connection)
        }
    }

    func saveSources(_ sources: [MediaSourceRecord], for project: ProjectRecord) throws {
        try importLegacyMediaIfNeeded(for: project)
        try Self.queue.sync {
            try ProjectMediaSQLite.writeTransaction(project: project, projectLibrary: projectLibrary, context: context) { connection in
                try replaceSources(sources, project: project, connection: connection)
                try upsertMediaState(project: project, connection: connection, inventoryScannedAt: nil, observationsGeneratedAt: nil)
            }
        }
    }

    func loadInventory(for project: ProjectRecord) throws -> [MediaItemRecord] {
        try importLegacyMediaIfNeeded(for: project)
        return try ProjectMediaSQLite.withProjectConnection(
            project,
            projectLibrary: projectLibrary,
            readOnly: true,
            context: context
        ) { connection in
            try loadTypedInventory(for: project, connection: connection)
        }
    }

    func saveInventory(_ items: [MediaItemRecord], for project: ProjectRecord) throws {
        try importLegacyMediaIfNeeded(for: project)
        let scannedAt = DateFormats.now()
        try Self.queue.sync {
            try ProjectMediaSQLite.writeTransaction(project: project, projectLibrary: projectLibrary, context: context) { connection in
                try replaceInventory(items, project: project, scannedAt: scannedAt, connection: connection)
                try upsertMediaState(project: project, connection: connection, inventoryScannedAt: scannedAt, observationsGeneratedAt: nil)
            }
        }
    }

    /// One transaction for ownership-changing imports/consolidation: callers
    /// never observe a source row whose media item was not saved, or vice versa.
    func saveLibrary(
        sources: [MediaSourceRecord],
        items: [MediaItemRecord],
        for project: ProjectRecord
    ) throws {
        try importLegacyMediaIfNeeded(for: project)
        let scannedAt = DateFormats.now()
        try Self.queue.sync {
            try ProjectMediaSQLite.writeTransaction(project: project, projectLibrary: projectLibrary, context: context) { connection in
                try replaceSources(sources, project: project, connection: connection)
                try replaceInventory(items, project: project, scannedAt: scannedAt, connection: connection)
                try upsertMediaState(
                    project: project,
                    connection: connection,
                    inventoryScannedAt: scannedAt,
                    observationsGeneratedAt: nil
                )
            }
        }
    }

    func loadCuration(for project: ProjectRecord) throws -> [String: MediaCurationRecord] {
        try importLegacyMediaIfNeeded(for: project)
        return try ProjectMediaSQLite.withProjectConnection(
            project,
            projectLibrary: projectLibrary,
            readOnly: true,
            context: context
        ) { connection in
            try loadTypedCuration(for: project, connection: connection)
        }
    }

    func saveCuration(_ curation: [String: MediaCurationRecord], for project: ProjectRecord) throws {
        try importLegacyMediaIfNeeded(for: project)
        let records = curation.values.sorted { $0.mediaId < $1.mediaId }
        try Self.queue.sync {
            try ProjectMediaSQLite.writeTransaction(project: project, projectLibrary: projectLibrary, context: context) { connection in
                try replaceCuration(records, project: project, connection: connection)
                try upsertMediaState(project: project, connection: connection, inventoryScannedAt: nil, observationsGeneratedAt: nil)
            }
        }
    }

    func loadMediaObservations(for project: ProjectRecord) throws -> [String: ImageObservationResult] {
        try importLegacyMediaIfNeeded(for: project)
        return try ProjectMediaSQLite.withProjectConnection(
            project,
            projectLibrary: projectLibrary,
            readOnly: true,
            context: context
        ) { connection in
            try loadTypedObservations(for: project, connection: connection)
        }
    }

    func saveMediaObservations(_ observationsById: [String: ImageObservationResult], for project: ProjectRecord) throws {
        try importLegacyMediaIfNeeded(for: project)
        let generatedAt = DateFormats.now()
        let observations = observationsById.values.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.mediaId < rhs.mediaId
            }
            return lhs.createdAt > rhs.createdAt
        }
        try Self.queue.sync {
            try ProjectMediaSQLite.writeTransaction(project: project, projectLibrary: projectLibrary, context: context) { connection in
                try replaceMediaObservations(observations, project: project, generatedAt: generatedAt, connection: connection)
                try upsertMediaState(project: project, connection: connection, inventoryScannedAt: nil, observationsGeneratedAt: generatedAt)
            }
        }
    }

    private var documentStore: ProjectSQLiteDocumentStore {
        ProjectSQLiteDocumentStore(projectLibrary: projectLibrary)
    }

    private func importLegacyMediaIfNeeded(for project: ProjectRecord) throws {
        guard try !hasTypedMediaState(for: project) else { return }

        let sourceDocument: MediaSourceDocument? = (try? documentStore.loadDocument(
            MediaSourceDocument.self,
            for: project,
            documentType: "media_sources"
        )) ?? nil
        let inventoryDocument: MediaInventoryDocument? = (try? documentStore.loadDocument(
            MediaInventoryDocument.self,
            for: project,
            documentType: "media_inventory"
        )) ?? nil
        let curationDocument: MediaCurationDocument? = (try? documentStore.loadDocument(
            MediaCurationDocument.self,
            for: project,
            documentType: "media_curation"
        )) ?? nil
        let observationDocument: MediaObservationDocument? = (try? documentStore.loadDocument(
            MediaObservationDocument.self,
            for: project,
            documentType: "media_observations"
        )) ?? nil

        let sources = sourceDocument?.sources ?? []
        let items = inventoryDocument?.items ?? []
        let curationRecords = curationDocument?.records ?? []
        let observations = observationDocument?.observations ?? []
        let itemIds = Set(items.map(\.mediaId))
        var warnings: [String] = []

        for record in curationRecords where !itemIds.contains(record.mediaId) {
            warnings.append("Legacy curation references missing media item \(record.mediaId).")
        }
        for observation in observations where !itemIds.contains(observation.mediaId) {
            warnings.append("Legacy observation references missing media item \(observation.mediaId).")
        }

        let scannedAt = inventoryDocument?.scannedAt ?? ""
        let generatedAt = observationDocument?.generatedAt ?? ""
        try Self.queue.sync {
            try ProjectMediaSQLite.writeTransaction(project: project, projectLibrary: projectLibrary, context: context) { connection in
                try replaceSources(sources, project: project, connection: connection)
                try replaceInventory(items, project: project, scannedAt: scannedAt, connection: connection)
                try replaceCuration(curationRecords, project: project, connection: connection)
                try replaceMediaObservations(observations, project: project, generatedAt: generatedAt, connection: connection)
                try replaceImportWarnings(warnings, project: project, connection: connection)
                try upsertMediaState(project: project, connection: connection, inventoryScannedAt: scannedAt, observationsGeneratedAt: generatedAt)
            }
        }
    }

    private func hasTypedMediaState(for project: ProjectRecord) throws -> Bool {
        try ProjectMediaSQLite.withProjectConnection(
            project,
            projectLibrary: projectLibrary,
            readOnly: true,
            context: context
        ) { connection in
            try ProjectMediaSQLite.scalarInt(
                connection,
                sql: "SELECT COUNT(*) FROM project_media_state WHERE project_id = ?;",
                bindings: [project.projectId],
                context: context
            ) > 0
        }
    }

    private func loadTypedSources(for project: ProjectRecord, connection: OpaquePointer) throws -> [MediaSourceRecord] {
        let sql = """
        SELECT source_id, display_name, path, source_kind, bookmark_data_base64,
               storage_mode, original_path, original_bookmark_data_base64,
               added_at, last_scanned_at
        FROM media_sources
        WHERE project_id = ? AND source_id != ?
        ORDER BY source_order ASC, added_at ASC, source_id ASC;
        """
        return try ProjectMediaSQLite.query(
            connection,
            sql: sql,
            bindings: [project.projectId, MediaItemRecord.generatedMediaSourceId],
            context: context
        ) { statement in
            let sourceKindRaw = ProjectMediaSQLite.columnString(statement, 3)
            return MediaSourceRecord(
                sourceId: ProjectMediaSQLite.columnString(statement, 0),
                displayName: ProjectMediaSQLite.columnString(statement, 1),
                path: ProjectMediaSQLite.columnString(statement, 2),
                sourceKind: MediaSourceKind(rawValue: sourceKindRaw),
                bookmarkDataBase64: ProjectMediaSQLite.columnString(statement, 4),
                storageMode: MediaStorageMode(rawValue: ProjectMediaSQLite.columnString(statement, 5)),
                originalPath: ProjectMediaSQLite.columnString(statement, 6),
                originalBookmarkDataBase64: ProjectMediaSQLite.columnString(statement, 7),
                addedAt: ProjectMediaSQLite.columnString(statement, 8),
                lastScannedAt: ProjectMediaSQLite.optionalColumnString(statement, 9)
            )
        }
    }

    private func replaceSources(_ sources: [MediaSourceRecord], project: ProjectRecord, connection: OpaquePointer) throws {
        try ProjectMediaSQLite.execute(
            "DELETE FROM media_sources WHERE project_id = ? AND source_id != ?;",
            connection: connection,
            bindings: [project.projectId, MediaItemRecord.generatedMediaSourceId],
            context: context
        )
        for (index, source) in sources.enumerated() where source.sourceId != MediaItemRecord.generatedMediaSourceId {
            try insertSource(source, order: index, project: project, connection: connection)
        }
    }

    private func insertSource(
        _ source: MediaSourceRecord,
        order: Int,
        project: ProjectRecord,
        connection: OpaquePointer
    ) throws {
        let sql = """
        INSERT INTO media_sources (
            project_id, source_id, source_order, display_name, path, source_kind,
            bookmark_data_base64, storage_mode, original_path,
            original_bookmark_data_base64, added_at, last_scanned_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(project_id, source_id) DO UPDATE SET
            source_order = excluded.source_order,
            display_name = excluded.display_name,
            path = excluded.path,
            source_kind = excluded.source_kind,
            bookmark_data_base64 = excluded.bookmark_data_base64,
            storage_mode = excluded.storage_mode,
            original_path = excluded.original_path,
            original_bookmark_data_base64 = excluded.original_bookmark_data_base64,
            added_at = excluded.added_at,
            last_scanned_at = excluded.last_scanned_at,
            record_revision = media_sources.record_revision + 1;
        """
        try ProjectMediaSQLite.execute(sql, connection: connection, bindings: [
            project.projectId,
            source.sourceId,
            order,
            source.displayName,
            source.path,
            source.sourceKind?.rawValue ?? "",
            source.bookmarkDataBase64,
            source.resolvedStorageMode.rawValue,
            source.resolvedOriginalPath,
            source.originalBookmarkDataBase64 ?? "",
            source.addedAt,
            source.lastScannedAt
        ], context: context)
    }

    private func ensureGeneratedMediaSource(project: ProjectRecord, connection: OpaquePointer) throws {
        let now = DateFormats.now()
        let source = MediaSourceRecord(
            sourceId: MediaItemRecord.generatedMediaSourceId,
            displayName: "Generated Media",
            path: "",
            sourceKind: nil,
            bookmarkDataBase64: "",
            storageMode: .managed,
            originalPath: "",
            originalBookmarkDataBase64: "",
            addedAt: now,
            lastScannedAt: nil
        )
        try insertSource(source, order: 999_000, project: project, connection: connection)
    }

    private func loadTypedInventory(for project: ProjectRecord, connection: OpaquePointer) throws -> [MediaItemRecord] {
        let sql = """
        SELECT media_id, source_id, kind, filename, path, relative_path, byte_count, modified_at,
               width, height, duration_seconds, nominal_frame_rate, thumbnail_path, video_strip_path,
               scanned_at, scan_error, derivative_kind, source_media_id, source_timestamp_seconds, frame_index,
               content_sha256
        FROM media_items
        WHERE project_id = ?
        ORDER BY item_order ASC, scanned_at DESC, media_id ASC;
        """
        return try ProjectMediaSQLite.query(connection, sql: sql, bindings: [project.projectId], context: context) { statement in
            let kindRaw = ProjectMediaSQLite.columnString(statement, 2)
            return MediaItemRecord(
                mediaId: ProjectMediaSQLite.columnString(statement, 0),
                sourceId: ProjectMediaSQLite.columnString(statement, 1),
                kind: MediaKind(rawValue: kindRaw) ?? .image,
                filename: ProjectMediaSQLite.columnString(statement, 3),
                path: ProjectMediaSQLite.columnString(statement, 4),
                relativePath: ProjectMediaSQLite.columnString(statement, 5),
                byteCount: sqlite3_column_int64(statement, 6),
                modifiedAt: ProjectMediaSQLite.columnString(statement, 7),
                width: Int(sqlite3_column_int(statement, 8)),
                height: Int(sqlite3_column_int(statement, 9)),
                durationSeconds: ProjectMediaSQLite.optionalColumnDouble(statement, 10),
                nominalFrameRate: ProjectMediaSQLite.optionalColumnDouble(statement, 11),
                thumbnailPath: ProjectMediaSQLite.columnString(statement, 12),
                videoStripPath: ProjectMediaSQLite.optionalColumnString(statement, 13),
                scannedAt: ProjectMediaSQLite.columnString(statement, 14),
                scanError: ProjectMediaSQLite.optionalColumnString(statement, 15),
                derivativeKind: ProjectMediaSQLite.optionalColumnString(statement, 16),
                sourceMediaId: ProjectMediaSQLite.optionalColumnString(statement, 17),
                sourceTimestampSeconds: ProjectMediaSQLite.optionalColumnDouble(statement, 18),
                frameIndex: ProjectMediaSQLite.optionalColumnInt(statement, 19),
                contentSha256: ProjectMediaSQLite.columnString(statement, 20)
            )
        }
    }

    private func replaceInventory(
        _ items: [MediaItemRecord],
        project: ProjectRecord,
        scannedAt: String,
        connection: OpaquePointer
    ) throws {
        if items.contains(where: { $0.sourceId == MediaItemRecord.generatedMediaSourceId }) {
            try ensureGeneratedMediaSource(project: project, connection: connection)
        }
        try ProjectMediaSQLite.execute(
            "DELETE FROM media_items WHERE project_id = ?;",
            connection: connection,
            bindings: [project.projectId],
            context: context
        )
        for (index, item) in items.enumerated() {
            try insertMediaItem(item, order: index, project: project, connection: connection)
        }
    }

    private func insertMediaItem(
        _ item: MediaItemRecord,
        order: Int,
        project: ProjectRecord,
        connection: OpaquePointer
    ) throws {
        let payload = (try? JSONCoding.encoder.encode(item)) ?? Data()
        let sql = """
        INSERT INTO media_items (
            project_id, media_id, item_order, source_id, kind, filename, path, relative_path,
            byte_count, modified_at, width, height, duration_seconds, nominal_frame_rate,
            thumbnail_path, video_strip_path, scanned_at, scan_error, derivative_kind,
            source_media_id, source_timestamp_seconds, frame_index, content_sha256, content_fingerprint
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(project_id, media_id) DO UPDATE SET
            item_order = excluded.item_order,
            source_id = excluded.source_id,
            kind = excluded.kind,
            filename = excluded.filename,
            path = excluded.path,
            relative_path = excluded.relative_path,
            byte_count = excluded.byte_count,
            modified_at = excluded.modified_at,
            width = excluded.width,
            height = excluded.height,
            duration_seconds = excluded.duration_seconds,
            nominal_frame_rate = excluded.nominal_frame_rate,
            thumbnail_path = excluded.thumbnail_path,
            video_strip_path = excluded.video_strip_path,
            scanned_at = excluded.scanned_at,
            scan_error = excluded.scan_error,
            derivative_kind = excluded.derivative_kind,
            source_media_id = excluded.source_media_id,
            source_timestamp_seconds = excluded.source_timestamp_seconds,
            frame_index = excluded.frame_index,
            content_sha256 = excluded.content_sha256,
            content_fingerprint = excluded.content_fingerprint,
            record_revision = media_items.record_revision + 1;
        """
        try ProjectMediaSQLite.execute(sql, connection: connection, bindings: [
            project.projectId,
            item.mediaId,
            order,
            item.sourceId,
            item.kind.rawValue,
            item.filename,
            item.path,
            item.relativePath,
            item.byteCount,
            item.modifiedAt,
            item.width,
            item.height,
            item.durationSeconds,
            item.nominalFrameRate,
            item.thumbnailPath,
            item.videoStripPath,
            item.scannedAt,
            item.scanError,
            item.derivativeKind,
            item.sourceMediaId,
            item.sourceTimestampSeconds,
            item.frameIndex,
            item.contentSha256,
            sha256Hex(payload)
        ], context: context)
    }

    private func loadTypedCuration(
        for project: ProjectRecord,
        connection: OpaquePointer
    ) throws -> [String: MediaCurationRecord] {
        let rows = try ProjectMediaSQLite.query(
            connection,
            sql: """
            SELECT media_id, rejected, notes, updated_at
            FROM media_curation
            WHERE project_id = ?
            ORDER BY media_id ASC;
            """,
            bindings: [project.projectId],
            context: context
        ) { statement in
            MediaCurationRecord(
                mediaId: ProjectMediaSQLite.columnString(statement, 0),
                rejected: sqlite3_column_int(statement, 1) != 0,
                tags: [],
                notes: ProjectMediaSQLite.columnString(statement, 2),
                updatedAt: ProjectMediaSQLite.columnString(statement, 3)
            )
        }
        var records = Dictionary(uniqueKeysWithValues: rows.map { ($0.mediaId, $0) })
        let tags = try ProjectMediaSQLite.query(
            connection,
            sql: """
            SELECT media_id, tag
            FROM media_curation_tags
            WHERE project_id = ?
            ORDER BY media_id ASC, tag_order ASC;
            """,
            bindings: [project.projectId],
            context: context
        ) { statement in
            (
                ProjectMediaSQLite.columnString(statement, 0),
                ProjectMediaSQLite.columnString(statement, 1)
            )
        }
        for (mediaId, tag) in tags {
            records[mediaId]?.tags.append(tag)
        }
        return records
    }

    private func replaceCuration(
        _ records: [MediaCurationRecord],
        project: ProjectRecord,
        connection: OpaquePointer
    ) throws {
        try ProjectMediaSQLite.execute(
            "DELETE FROM media_curation WHERE project_id = ?;",
            connection: connection,
            bindings: [project.projectId],
            context: context
        )
        for record in records {
            try insertCuration(record, project: project, connection: connection)
        }
    }

    private func insertCuration(
        _ record: MediaCurationRecord,
        project: ProjectRecord,
        connection: OpaquePointer
    ) throws {
        try ProjectMediaSQLite.execute(
            """
            INSERT INTO media_curation (project_id, media_id, rejected, notes, updated_at)
            VALUES (?, ?, ?, ?, ?);
            """,
            connection: connection,
            bindings: [project.projectId, record.mediaId, record.rejected, record.notes, record.updatedAt],
            context: context
        )
        for (index, tag) in normalizedTags(record.tags).enumerated() {
            try ProjectMediaSQLite.execute(
                """
                INSERT INTO media_curation_tags (project_id, media_id, tag_order, tag)
                VALUES (?, ?, ?, ?);
                """,
                connection: connection,
                bindings: [project.projectId, record.mediaId, index, tag],
                context: context
            )
        }
    }

    private func replaceMediaObservations(
        _ observations: [ImageObservationResult],
        project: ProjectRecord,
        generatedAt: String,
        connection: OpaquePointer
    ) throws {
        try ProjectMediaSQLite.execute(
            "DELETE FROM media_observations WHERE project_id = ?;",
            connection: connection,
            bindings: [project.projectId],
            context: context
        )
        for observation in observations {
            try insertObservation(observation, project: project, connection: connection)
        }
    }

    private func insertObservation(
        _ observation: ImageObservationResult,
        project: ProjectRecord,
        connection: OpaquePointer
    ) throws {
        let payload = try observation.encoded(pretty: false)
        let rawPayload = String(decoding: payload, as: UTF8.self)
        let now = DateFormats.now()
        let sql = """
        INSERT INTO media_observations (
            project_id, media_id, schema_version, frame_id, source_path, image_hash,
            observation_provider, model, prompt_version, created_at, plain_caption,
            literal_description, people_visible, people_count_estimate, setting, lighting,
            media_role, media_role_assessment_role, media_role_assessment_why,
            media_role_assessment_confidence, source_kind_notes, detail_pass_used,
            detail_pass_reason, detail_observation_notes, object_description_pass_used,
            object_description_prompt_version, source_image_path, source_image_sha256,
            vision_input_kind, vision_input_path, vision_input_sha256, vision_input_width,
            vision_input_height, vision_input_bytes, vision_thumbnail_profile,
            fullres_vision_allowed, thumbnail_policy_version, detail_vision_input_kind,
            detail_vision_input_path, detail_vision_input_sha256, detail_vision_input_width,
            detail_vision_input_height, detail_vision_input_bytes, detail_vision_thumbnail_profile,
            event_type, event_name_guess, event_competition_or_program_guess, event_why,
            event_confidence, human_review_needs_review, human_review_reason,
            human_review_suggested_question, user_known_context, user_preferred_media_role,
            user_notes, raw_payload_json, content_fingerprint, updated_at
        ) VALUES (
            ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
            ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
            ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
        );
        """
        try ProjectMediaSQLite.execute(sql, connection: connection, bindings: [
            project.projectId,
            observation.mediaId,
            observation.schemaVersion,
            observation.frameId,
            observation.sourcePath,
            observation.imageHash,
            observation.observationProvider,
            observation.model,
            observation.promptVersion,
            observation.createdAt,
            observation.plainCaption,
            observation.literalDescription,
            observation.peopleVisible,
            observation.peopleCountEstimate,
            observation.setting,
            observation.lighting,
            observation.mediaRole,
            observation.mediaRoleAssessment.mediaRole,
            observation.mediaRoleAssessment.why,
            observation.mediaRoleAssessment.confidence0To1,
            observation.sourceKindNotes,
            observation.detailPassUsed,
            observation.detailPassReason,
            observation.detailObservationNotes,
            observation.objectDescriptionPassUsed,
            observation.objectDescriptionPromptVersion,
            observation.sourceImagePath,
            observation.sourceImageSha256,
            observation.visionInputKind,
            observation.visionInputPath,
            observation.visionInputSha256,
            observation.visionInputWidth,
            observation.visionInputHeight,
            observation.visionInputBytes,
            observation.visionThumbnailProfile,
            observation.fullresVisionAllowed,
            observation.thumbnailPolicyVersion,
            observation.detailVisionInputKind,
            observation.detailVisionInputPath,
            observation.detailVisionInputSha256,
            observation.detailVisionInputWidth,
            observation.detailVisionInputHeight,
            observation.detailVisionInputBytes,
            observation.detailVisionThumbnailProfile,
            observation.eventContext.eventType,
            observation.eventContext.eventNameGuess,
            observation.eventContext.competitionOrProgramGuess,
            observation.eventContext.why,
            observation.eventContext.confidence0To1,
            observation.humanReview.needsReview,
            observation.humanReview.reviewReason,
            observation.humanReview.suggestedQuestion,
            observation.userProvidedContext.knownContext,
            observation.userProvidedContext.preferredMediaRole,
            observation.userProvidedContext.notes,
            rawPayload,
            sha256Hex(payload),
            now
        ], context: context)
        try insertObservationTerms(observation, project: project, connection: connection)
        try insertObservationStructuredDetails(observation, project: project, connection: connection)
    }

    private func insertObservationTerms(
        _ observation: ImageObservationResult,
        project: ProjectRecord,
        connection: OpaquePointer
    ) throws {
        let termGroups: [(String, [String])] = [
            ("objects", observation.objects),
            ("people_roles_visible", observation.peopleRolesVisible),
            ("activities", observation.activities),
            ("mood", observation.mood),
            ("materials", observation.materials),
            ("visual_specificity", observation.visualSpecificity),
            ("palette_terms", observation.paletteTerms),
            ("place_cues", observation.placeCues),
            ("era_cues", observation.eraCues),
            ("motif_cues", observation.motifCues),
            ("energy_cues", observation.energyCues),
            ("composition_cues", observation.compositionCues),
            ("domain_tags", observation.domainTags),
            ("local_context_tags", observation.localContextTags),
            ("technical_context_tags", observation.technicalContextTags),
            ("story_observation_tags", observation.storyObservationTags),
            ("possible_meanings", observation.possibleMeanings),
            ("negative_constraints", observation.negativeConstraints)
        ]
        for (termKind, values) in termGroups {
            for (index, value) in normalizedValues(values).enumerated() {
                try ProjectMediaSQLite.execute(
                    """
                    INSERT INTO media_observation_terms (project_id, media_id, term_kind, item_order, value)
                    VALUES (?, ?, ?, ?, ?);
                    """,
                    connection: connection,
                    bindings: [project.projectId, observation.mediaId, termKind, index, value],
                    context: context
                )
            }
        }
    }

    private func insertObservationStructuredDetails(
        _ observation: ImageObservationResult,
        project: ProjectRecord,
        connection: OpaquePointer
    ) throws {
        for (index, value) in observation.objectDescriptions.enumerated() {
            try ProjectMediaSQLite.execute(
                """
                INSERT INTO media_observation_object_descriptions (
                    project_id, media_id, item_order, accurate_title, thorough_description
                ) VALUES (?, ?, ?, ?, ?);
                """,
                connection: connection,
                bindings: [project.projectId, observation.mediaId, index, value.accurateTitle, value.thoroughDescription],
                context: context
            )
        }
        for (index, value) in observation.visibleText.enumerated() {
            try ProjectMediaSQLite.execute(
                """
                INSERT INTO media_observation_visible_text (
                    project_id, media_id, item_order, text, where_seen, confidence0_to1
                ) VALUES (?, ?, ?, ?, ?, ?);
                """,
                connection: connection,
                bindings: [project.projectId, observation.mediaId, index, value.text, value.whereSeen, value.confidence0To1],
                context: context
            )
        }
        for (index, value) in observation.logosBrandsOrganizations.enumerated() {
            try ProjectMediaSQLite.execute(
                """
                INSERT INTO media_observation_domain_entities (
                    project_id, media_id, entity_scope, item_order, name, kind, visible_evidence, confidence0_to1
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
                """,
                connection: connection,
                bindings: [project.projectId, observation.mediaId, "logos_brands_organizations", index, value.name, value.kind, value.visibleEvidence, value.confidence0To1],
                context: context
            )
        }
        for (index, value) in observation.flagsSymbolsSignage.enumerated() {
            try ProjectMediaSQLite.execute(
                """
                INSERT INTO media_observation_flags_symbols (
                    project_id, media_id, item_order, name, kind, visible_evidence, confidence0_to1
                ) VALUES (?, ?, ?, ?, ?, ?, ?);
                """,
                connection: connection,
                bindings: [project.projectId, observation.mediaId, index, value.name, value.kind, value.visibleEvidence, value.confidence0To1],
                context: context
            )
        }
        for (index, value) in observation.uncertainties.enumerated() {
            try ProjectMediaSQLite.execute(
                """
                INSERT INTO media_observation_uncertainties (
                    project_id, media_id, item_order, field, question, why_uncertain
                ) VALUES (?, ?, ?, ?, ?, ?);
                """,
                connection: connection,
                bindings: [project.projectId, observation.mediaId, index, value.field, value.question, value.whyUncertain],
                context: context
            )
        }
        for (index, tag) in normalizedValues(observation.userProvidedContext.domainTags).enumerated() {
            try ProjectMediaSQLite.execute(
                """
                INSERT INTO media_observation_user_context_tags (project_id, media_id, tag_order, tag)
                VALUES (?, ?, ?, ?);
                """,
                connection: connection,
                bindings: [project.projectId, observation.mediaId, index, tag],
                context: context
            )
        }
    }

    private func loadTypedObservations(
        for project: ProjectRecord,
        connection: OpaquePointer
    ) throws -> [String: ImageObservationResult] {
        let baseRows = try loadObservationBaseRows(for: project, connection: connection)
        guard !baseRows.isEmpty else { return [:] }
        var observations = Dictionary(uniqueKeysWithValues: baseRows.map { ($0.mediaId, $0) })
        try applyObservationTerms(project: project, connection: connection, observations: &observations)
        try applyObjectDescriptions(project: project, connection: connection, observations: &observations)
        try applyVisibleText(project: project, connection: connection, observations: &observations)
        try applyDomainEntities(project: project, connection: connection, observations: &observations)
        try applyFlagsSymbols(project: project, connection: connection, observations: &observations)
        try applyUncertainties(project: project, connection: connection, observations: &observations)
        try applyUserContextTags(project: project, connection: connection, observations: &observations)
        return observations
    }

    private func loadObservationBaseRows(
        for project: ProjectRecord,
        connection: OpaquePointer
    ) throws -> [ImageObservationResult] {
        try ProjectMediaSQLite.query(
            connection,
            sql: """
            SELECT schema_version, media_id, frame_id, source_path, image_hash, observation_provider,
                   model, prompt_version, created_at, plain_caption, literal_description,
                   people_visible, people_count_estimate, setting, lighting, media_role,
                   media_role_assessment_role, media_role_assessment_why,
                   media_role_assessment_confidence, source_kind_notes, detail_pass_used,
                   detail_pass_reason, detail_observation_notes, object_description_pass_used,
                   object_description_prompt_version, source_image_path, source_image_sha256,
                   vision_input_kind, vision_input_path, vision_input_sha256, vision_input_width,
                   vision_input_height, vision_input_bytes, vision_thumbnail_profile,
                   fullres_vision_allowed, thumbnail_policy_version, detail_vision_input_kind,
                   detail_vision_input_path, detail_vision_input_sha256, detail_vision_input_width,
                   detail_vision_input_height, detail_vision_input_bytes, detail_vision_thumbnail_profile,
                   event_type, event_name_guess, event_competition_or_program_guess, event_why,
                   event_confidence, human_review_needs_review, human_review_reason,
                   human_review_suggested_question, user_known_context, user_preferred_media_role,
                   user_notes
            FROM media_observations
            WHERE project_id = ?
            ORDER BY created_at DESC, media_id ASC;
            """,
            bindings: [project.projectId],
            context: context
        ) { statement in
            var observation = ImageObservationResult()
            observation.schemaVersion = ProjectMediaSQLite.columnString(statement, 0)
            observation.mediaId = ProjectMediaSQLite.columnString(statement, 1)
            observation.frameId = ProjectMediaSQLite.columnString(statement, 2)
            observation.sourcePath = ProjectMediaSQLite.columnString(statement, 3)
            observation.imageHash = ProjectMediaSQLite.columnString(statement, 4)
            observation.observationProvider = ProjectMediaSQLite.columnString(statement, 5)
            observation.model = ProjectMediaSQLite.columnString(statement, 6)
            observation.promptVersion = ProjectMediaSQLite.columnString(statement, 7)
            observation.createdAt = ProjectMediaSQLite.columnString(statement, 8)
            observation.plainCaption = ProjectMediaSQLite.columnString(statement, 9)
            observation.literalDescription = ProjectMediaSQLite.columnString(statement, 10)
            observation.peopleVisible = sqlite3_column_int(statement, 11) != 0
            observation.peopleCountEstimate = ProjectMediaSQLite.optionalColumnInt(statement, 12)
            observation.setting = ProjectMediaSQLite.columnString(statement, 13)
            observation.lighting = ProjectMediaSQLite.columnString(statement, 14)
            observation.mediaRole = ProjectMediaSQLite.columnString(statement, 15)
            observation.mediaRoleAssessment = MediaRoleAssessment(
                mediaRole: ProjectMediaSQLite.columnString(statement, 16),
                why: ProjectMediaSQLite.columnString(statement, 17),
                confidence0To1: sqlite3_column_double(statement, 18)
            )
            observation.sourceKindNotes = ProjectMediaSQLite.columnString(statement, 19)
            observation.detailPassUsed = sqlite3_column_int(statement, 20) != 0
            observation.detailPassReason = ProjectMediaSQLite.columnString(statement, 21)
            observation.detailObservationNotes = ProjectMediaSQLite.columnString(statement, 22)
            observation.objectDescriptionPassUsed = sqlite3_column_int(statement, 23) != 0
            observation.objectDescriptionPromptVersion = ProjectMediaSQLite.columnString(statement, 24)
            observation.sourceImagePath = ProjectMediaSQLite.columnString(statement, 25)
            observation.sourceImageSha256 = ProjectMediaSQLite.columnString(statement, 26)
            observation.visionInputKind = ProjectMediaSQLite.columnString(statement, 27)
            observation.visionInputPath = ProjectMediaSQLite.columnString(statement, 28)
            observation.visionInputSha256 = ProjectMediaSQLite.columnString(statement, 29)
            observation.visionInputWidth = Int(sqlite3_column_int(statement, 30))
            observation.visionInputHeight = Int(sqlite3_column_int(statement, 31))
            observation.visionInputBytes = Int(sqlite3_column_int(statement, 32))
            observation.visionThumbnailProfile = ProjectMediaSQLite.columnString(statement, 33)
            observation.fullresVisionAllowed = sqlite3_column_int(statement, 34) != 0
            observation.thumbnailPolicyVersion = ProjectMediaSQLite.columnString(statement, 35)
            observation.detailVisionInputKind = ProjectMediaSQLite.columnString(statement, 36)
            observation.detailVisionInputPath = ProjectMediaSQLite.columnString(statement, 37)
            observation.detailVisionInputSha256 = ProjectMediaSQLite.columnString(statement, 38)
            observation.detailVisionInputWidth = Int(sqlite3_column_int(statement, 39))
            observation.detailVisionInputHeight = Int(sqlite3_column_int(statement, 40))
            observation.detailVisionInputBytes = Int(sqlite3_column_int(statement, 41))
            observation.detailVisionThumbnailProfile = ProjectMediaSQLite.columnString(statement, 42)
            observation.eventContext = EventContext(
                eventType: ProjectMediaSQLite.columnString(statement, 43),
                eventNameGuess: ProjectMediaSQLite.columnString(statement, 44),
                competitionOrProgramGuess: ProjectMediaSQLite.columnString(statement, 45),
                why: ProjectMediaSQLite.columnString(statement, 46),
                confidence0To1: sqlite3_column_double(statement, 47)
            )
            observation.humanReview = HumanOverride(
                needsReview: sqlite3_column_int(statement, 48) != 0,
                reviewReason: ProjectMediaSQLite.columnString(statement, 49),
                suggestedQuestion: ProjectMediaSQLite.columnString(statement, 50)
            )
            observation.userProvidedContext = UserProvidedContext(
                knownContext: ProjectMediaSQLite.columnString(statement, 51),
                domainTags: [],
                preferredMediaRole: ProjectMediaSQLite.columnString(statement, 52),
                notes: ProjectMediaSQLite.columnString(statement, 53)
            )
            return observation
        }
    }

    private func applyObservationTerms(
        project: ProjectRecord,
        connection: OpaquePointer,
        observations: inout [String: ImageObservationResult]
    ) throws {
        let rows = try ProjectMediaSQLite.query(
            connection,
            sql: """
            SELECT media_id, term_kind, value
            FROM media_observation_terms
            WHERE project_id = ?
            ORDER BY media_id ASC, term_kind ASC, item_order ASC;
            """,
            bindings: [project.projectId],
            context: context
        ) { statement in
            (
                ProjectMediaSQLite.columnString(statement, 0),
                ProjectMediaSQLite.columnString(statement, 1),
                ProjectMediaSQLite.columnString(statement, 2)
            )
        }
        for (mediaId, termKind, value) in rows {
            switch termKind {
            case "objects": observations[mediaId]?.objects.append(value)
            case "people_roles_visible": observations[mediaId]?.peopleRolesVisible.append(value)
            case "activities": observations[mediaId]?.activities.append(value)
            case "mood": observations[mediaId]?.mood.append(value)
            case "materials": observations[mediaId]?.materials.append(value)
            case "visual_specificity": observations[mediaId]?.visualSpecificity.append(value)
            case "palette_terms": observations[mediaId]?.paletteTerms.append(value)
            case "place_cues": observations[mediaId]?.placeCues.append(value)
            case "era_cues": observations[mediaId]?.eraCues.append(value)
            case "motif_cues": observations[mediaId]?.motifCues.append(value)
            case "energy_cues": observations[mediaId]?.energyCues.append(value)
            case "composition_cues": observations[mediaId]?.compositionCues.append(value)
            case "domain_tags": observations[mediaId]?.domainTags.append(value)
            case "local_context_tags": observations[mediaId]?.localContextTags.append(value)
            case "technical_context_tags": observations[mediaId]?.technicalContextTags.append(value)
            case "story_observation_tags": observations[mediaId]?.storyObservationTags.append(value)
            case "possible_meanings": observations[mediaId]?.possibleMeanings.append(value)
            case "negative_constraints": observations[mediaId]?.negativeConstraints.append(value)
            default: break
            }
        }
    }

    private func applyObjectDescriptions(
        project: ProjectRecord,
        connection: OpaquePointer,
        observations: inout [String: ImageObservationResult]
    ) throws {
        let rows = try ProjectMediaSQLite.query(
            connection,
            sql: """
            SELECT media_id, accurate_title, thorough_description
            FROM media_observation_object_descriptions
            WHERE project_id = ?
            ORDER BY media_id ASC, item_order ASC;
            """,
            bindings: [project.projectId],
            context: context
        ) { statement in
            (
                ProjectMediaSQLite.columnString(statement, 0),
                ImageObjectDescription(
                    accurateTitle: ProjectMediaSQLite.columnString(statement, 1),
                    thoroughDescription: ProjectMediaSQLite.columnString(statement, 2)
                )
            )
        }
        for (mediaId, value) in rows {
            observations[mediaId]?.objectDescriptions.append(value)
        }
    }

    private func applyVisibleText(
        project: ProjectRecord,
        connection: OpaquePointer,
        observations: inout [String: ImageObservationResult]
    ) throws {
        let rows = try ProjectMediaSQLite.query(
            connection,
            sql: """
            SELECT media_id, text, where_seen, confidence0_to1
            FROM media_observation_visible_text
            WHERE project_id = ?
            ORDER BY media_id ASC, item_order ASC;
            """,
            bindings: [project.projectId],
            context: context
        ) { statement in
            (
                ProjectMediaSQLite.columnString(statement, 0),
                VisibleTextObservation(
                    text: ProjectMediaSQLite.columnString(statement, 1),
                    whereSeen: ProjectMediaSQLite.columnString(statement, 2),
                    confidence0To1: sqlite3_column_double(statement, 3)
                )
            )
        }
        for (mediaId, value) in rows {
            observations[mediaId]?.visibleText.append(value)
        }
    }

    private func applyDomainEntities(
        project: ProjectRecord,
        connection: OpaquePointer,
        observations: inout [String: ImageObservationResult]
    ) throws {
        let rows = try ProjectMediaSQLite.query(
            connection,
            sql: """
            SELECT media_id, entity_scope, name, kind, visible_evidence, confidence0_to1
            FROM media_observation_domain_entities
            WHERE project_id = ?
            ORDER BY media_id ASC, entity_scope ASC, item_order ASC;
            """,
            bindings: [project.projectId],
            context: context
        ) { statement in
            (
                ProjectMediaSQLite.columnString(statement, 0),
                ProjectMediaSQLite.columnString(statement, 1),
                DomainEntity(
                    name: ProjectMediaSQLite.columnString(statement, 2),
                    kind: ProjectMediaSQLite.columnString(statement, 3),
                    visibleEvidence: ProjectMediaSQLite.columnString(statement, 4),
                    confidence0To1: sqlite3_column_double(statement, 5)
                )
            )
        }
        for (mediaId, scope, value) in rows where scope == "logos_brands_organizations" {
            observations[mediaId]?.logosBrandsOrganizations.append(value)
        }
    }

    private func applyFlagsSymbols(
        project: ProjectRecord,
        connection: OpaquePointer,
        observations: inout [String: ImageObservationResult]
    ) throws {
        let rows = try ProjectMediaSQLite.query(
            connection,
            sql: """
            SELECT media_id, name, kind, visible_evidence, confidence0_to1
            FROM media_observation_flags_symbols
            WHERE project_id = ?
            ORDER BY media_id ASC, item_order ASC;
            """,
            bindings: [project.projectId],
            context: context
        ) { statement in
            (
                ProjectMediaSQLite.columnString(statement, 0),
                FlagSymbolSignage(
                    name: ProjectMediaSQLite.columnString(statement, 1),
                    kind: ProjectMediaSQLite.columnString(statement, 2),
                    visibleEvidence: ProjectMediaSQLite.columnString(statement, 3),
                    confidence0To1: sqlite3_column_double(statement, 4)
                )
            )
        }
        for (mediaId, value) in rows {
            observations[mediaId]?.flagsSymbolsSignage.append(value)
        }
    }

    private func applyUncertainties(
        project: ProjectRecord,
        connection: OpaquePointer,
        observations: inout [String: ImageObservationResult]
    ) throws {
        let rows = try ProjectMediaSQLite.query(
            connection,
            sql: """
            SELECT media_id, field, question, why_uncertain
            FROM media_observation_uncertainties
            WHERE project_id = ?
            ORDER BY media_id ASC, item_order ASC;
            """,
            bindings: [project.projectId],
            context: context
        ) { statement in
            (
                ProjectMediaSQLite.columnString(statement, 0),
                ObservationUncertainty(
                    field: ProjectMediaSQLite.columnString(statement, 1),
                    question: ProjectMediaSQLite.columnString(statement, 2),
                    whyUncertain: ProjectMediaSQLite.columnString(statement, 3)
                )
            )
        }
        for (mediaId, value) in rows {
            observations[mediaId]?.uncertainties.append(value)
        }
    }

    private func applyUserContextTags(
        project: ProjectRecord,
        connection: OpaquePointer,
        observations: inout [String: ImageObservationResult]
    ) throws {
        let rows = try ProjectMediaSQLite.query(
            connection,
            sql: """
            SELECT media_id, tag
            FROM media_observation_user_context_tags
            WHERE project_id = ?
            ORDER BY media_id ASC, tag_order ASC;
            """,
            bindings: [project.projectId],
            context: context
        ) { statement in
            (
                ProjectMediaSQLite.columnString(statement, 0),
                ProjectMediaSQLite.columnString(statement, 1)
            )
        }
        for (mediaId, tag) in rows {
            observations[mediaId]?.userProvidedContext.domainTags.append(tag)
        }
    }

    private func replaceImportWarnings(
        _ warnings: [String],
        project: ProjectRecord,
        connection: OpaquePointer
    ) throws {
        try ProjectMediaSQLite.execute(
            "DELETE FROM media_import_warnings WHERE project_id = ?;",
            connection: connection,
            bindings: [project.projectId],
            context: context
        )
        let createdAt = DateFormats.now()
        for (index, warning) in warnings.enumerated() {
            try ProjectMediaSQLite.execute(
                """
                INSERT INTO media_import_warnings (project_id, warning_order, warning, created_at)
                VALUES (?, ?, ?, ?);
                """,
                connection: connection,
                bindings: [project.projectId, index, warning, createdAt],
                context: context
            )
        }
    }

    private func upsertMediaState(
        project: ProjectRecord,
        connection: OpaquePointer,
        inventoryScannedAt: String?,
        observationsGeneratedAt: String?
    ) throws {
        let now = DateFormats.now()
        try ProjectMediaSQLite.execute(
            """
            INSERT INTO project_media_state (
                project_id, schema_version, inventory_scanned_at, observations_generated_at, updated_at
            ) VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(project_id) DO UPDATE SET
                schema_version = excluded.schema_version,
                inventory_scanned_at = CASE
                    WHEN excluded.inventory_scanned_at != '' THEN excluded.inventory_scanned_at
                    ELSE project_media_state.inventory_scanned_at
                END,
                observations_generated_at = CASE
                    WHEN excluded.observations_generated_at != '' THEN excluded.observations_generated_at
                    ELSE project_media_state.observations_generated_at
                END,
                updated_at = excluded.updated_at,
                record_revision = project_media_state.record_revision + 1;
            """,
            connection: connection,
            bindings: [
                project.projectId,
                LitScenesDesktopDatabase.projectMediaSchemaVersion,
                inventoryScannedAt ?? "",
                observationsGeneratedAt ?? "",
                now
            ],
            context: context
        )
    }

    private func normalizedTags(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for rawValue in values {
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            let key = value.lowercased()
            guard seen.insert(key).inserted else { continue }
            output.append(value)
        }
        return output
    }

    private func normalizedValues(_ values: [String]) -> [String] {
        values.compactMap { rawValue in
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
    }
}
