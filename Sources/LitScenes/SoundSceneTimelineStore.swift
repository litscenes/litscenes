import Foundation
@preconcurrency import AVFoundation
import SQLite3

private let soundSceneTimelineSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
private let soundSceneTimelineSchemaVersion = "litscenes.sound_scene_timeline.v0.1"
private let sceneSoundArrangementSchemaVersion = "litscenes.scene_sound_arrangement.v0.1"

struct SoundSceneAsset: Hashable, Identifiable, Sendable {
    var schemaVersion: String = soundSceneTimelineSchemaVersion
    var soundId: String
    var id: String { soundId }
    var displayName: String
    var path: String
    var fileType: String
    var byteCount: Int64
    var modifiedAt: String
    var durationSeconds: Double
    var discoveredAt: String
    var updatedAt: String

    var durationLabel: String {
        soundSceneTimecode(durationSeconds)
    }

    var fileTypeLabel: String {
        fileType.uppercased()
    }
}

extension SoundSceneAsset {
    /// Adapts an imported audio media item to the sound-rail vocabulary, so the
    /// rail's row, waveform loader and transport work on project audio without
    /// being rewritten. The original rail was built against a folder scan;
    /// project audio arrives as `MediaItemRecord` instead, and this is the only
    /// difference between them.
    init(audioMediaItem item: MediaItemRecord) {
        self.init(
            soundId: item.mediaId,
            displayName: item.filename,
            path: item.path,
            fileType: (item.path as NSString).pathExtension.lowercased(),
            byteCount: item.byteCount,
            modifiedAt: item.modifiedAt,
            durationSeconds: item.durationSeconds ?? 0,
            discoveredAt: item.scannedAt,
            updatedAt: item.modifiedAt
        )
    }
}

struct SoundScenePlan: Hashable, Identifiable, Sendable {
    var schemaVersion: String = soundSceneTimelineSchemaVersion
    var planId: String
    var id: String { planId }
    var projectId: String
    var soundId: String
    var startSeconds: Double
    var durationSeconds: Double
    var title: String
    var setup: String
    var turn: String
    var resolution: String
    var notes: String
    var createdAt: String
    var updatedAt: String

    var endSeconds: Double {
        startSeconds + durationSeconds
    }

    var timeRangeLabel: String {
        "\(soundSceneTimecode(startSeconds)) - \(soundSceneTimecode(endSeconds))"
    }

    static func draft(
        projectId: String,
        soundId: String,
        startSeconds: Double,
        durationSeconds: Double,
        now: String = DateFormats.now()
    ) -> SoundScenePlan {
        let clampedStart = max(0, startSeconds)
        let planId = "sound_scene_plan_\(shortHash("\(projectId):\(soundId):\(clampedStart):\(now)", length: 14))"
        return SoundScenePlan(
            planId: planId,
            projectId: projectId,
            soundId: soundId,
            startSeconds: clampedStart,
            durationSeconds: max(durationSeconds, 1),
            title: "Scene \(soundSceneTimecode(clampedStart))",
            setup: "",
            turn: "",
            resolution: "",
            notes: "",
            createdAt: now,
            updatedAt: now
        )
    }
}

struct SceneSoundArrangementCard: Codable, Hashable, Identifiable, Sendable {
    var cardId: String
    var id: String { cardId }
    var arrangementId: String
    var planId: String
    var sceneId: String
    var sceneOrder: Int
    var beatIds: [String]
    var startSeconds: Double
    var durationSeconds: Double
    var title: String
    var setup: String
    var turn: String
    var resolution: String
    var notes: String
    var createdAt: String
    var updatedAt: String

    var endSeconds: Double {
        startSeconds + durationSeconds
    }

    var timeRangeLabel: String {
        "\(soundSceneTimecode(startSeconds)) - \(soundSceneTimecode(endSeconds))"
    }
}

struct SceneSoundArrangement: Codable, Hashable, Identifiable, Sendable {
    var schemaVersion: String = sceneSoundArrangementSchemaVersion
    var arrangementId: String
    var id: String { arrangementId }
    var projectId: String
    var sceneStorySetId: String
    var storyId: String
    var soundId: String
    var title: String
    var activeVideoChainId: String
    var cards: [SceneSoundArrangementCard]
    var createdAt: String
    var updatedAt: String

    var totalDurationSeconds: Double {
        cards.map(\.endSeconds).max() ?? 0
    }

    var sortedCards: [SceneSoundArrangementCard] {
        cards.sorted {
            if $0.startSeconds == $1.startSeconds {
                return $0.sceneOrder < $1.sceneOrder
            }
            return $0.startSeconds < $1.startSeconds
        }
    }
}

enum SoundSceneTimelineSettings {
    static func databaseURL(
        for project: ProjectRecord,
        projectLibrary: ProjectLibrary = ProjectLibrary()
    ) -> URL {
        LitScenesDesktopDatabase.projectDatabaseURL(for: project, projectLibrary: projectLibrary)
    }
}

actor SoundSceneTimelineStore {
    static let shared = SoundSceneTimelineStore()

    private let projectLibrary = ProjectLibrary()
    private var connection: OpaquePointer?
    private var initialized = false
    private var openProjectId = ""

    func refreshDefaultSoundAssets(project: ProjectRecord) async throws -> [SoundSceneAsset] {
        try ensureReady(for: project)
        let scannedAssets = try await scanDefaultSoundAssets()
        for asset in scannedAssets {
            try upsertSoundAsset(asset)
        }
        return try loadSoundAssets(project: project)
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .sorted { lhs, rhs in
                lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
    }

    func loadSoundAssets(project: ProjectRecord) throws -> [SoundSceneAsset] {
        try ensureReady(for: project)
        guard let connection else { throw ScreenGraphError.capture("Sound timeline DB is not open.") }
        let sql = """
        SELECT schema_version, sound_id, display_name, path, file_type, byte_count, modified_at,
               duration_seconds, discovered_at, updated_at
        FROM sound_assets
        ORDER BY display_name COLLATE NOCASE, path;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ScreenGraphError.capture("Sound asset query prepare failed: \(sqliteMessage())")
        }
        defer { sqlite3_finalize(statement) }

        var assets: [SoundSceneAsset] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            assets.append(SoundSceneAsset(
                schemaVersion: columnText(statement, 0),
                soundId: columnText(statement, 1),
                displayName: columnText(statement, 2),
                path: columnText(statement, 3),
                fileType: columnText(statement, 4),
                byteCount: sqlite3_column_int64(statement, 5),
                modifiedAt: columnText(statement, 6),
                durationSeconds: sqlite3_column_double(statement, 7),
                discoveredAt: columnText(statement, 8),
                updatedAt: columnText(statement, 9)
            ))
        }
        return assets
    }

    func loadSoundScenePlans(project: ProjectRecord, soundId: String) throws -> [SoundScenePlan] {
        try ensureReady(for: project)
        guard let connection else { throw ScreenGraphError.capture("Sound timeline DB is not open.") }
        let sql = """
        SELECT schema_version, plan_id, project_id, sound_id, start_seconds, duration_seconds,
               title, setup, turn, resolution, notes, created_at, updated_at
        FROM sound_scene_plans
        WHERE project_id = ? AND sound_id = ?
        ORDER BY start_seconds, duration_seconds, title COLLATE NOCASE;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ScreenGraphError.capture("Sound scene plan query prepare failed: \(sqliteMessage())")
        }
        defer { sqlite3_finalize(statement) }

        bindText(project.projectId, to: 1, in: statement)
        bindText(soundId, to: 2, in: statement)

        var plans: [SoundScenePlan] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            plans.append(SoundScenePlan(
                schemaVersion: columnText(statement, 0),
                planId: columnText(statement, 1),
                projectId: columnText(statement, 2),
                soundId: columnText(statement, 3),
                startSeconds: sqlite3_column_double(statement, 4),
                durationSeconds: sqlite3_column_double(statement, 5),
                title: columnText(statement, 6),
                setup: columnText(statement, 7),
                turn: columnText(statement, 8),
                resolution: columnText(statement, 9),
                notes: columnText(statement, 10),
                createdAt: columnText(statement, 11),
                updatedAt: columnText(statement, 12)
            ))
        }
        return plans
    }

    func upsertSoundScenePlan(
        _ plan: SoundScenePlan,
        project: ProjectRecord,
        soundDurationSeconds: Double
    ) throws -> SoundScenePlan {
        try ensureReady(for: project)
        let normalized = try validatedPlan(plan, project: project, soundDurationSeconds: soundDurationSeconds)
        guard let connection else { throw ScreenGraphError.capture("Sound timeline DB is not open.") }
        let sql = """
        INSERT INTO sound_scene_plans (
            schema_version, plan_id, project_id, sound_id, start_seconds, duration_seconds,
            title, setup, turn, resolution, notes, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(plan_id) DO UPDATE SET
            schema_version = excluded.schema_version,
            project_id = excluded.project_id,
            sound_id = excluded.sound_id,
            start_seconds = excluded.start_seconds,
            duration_seconds = excluded.duration_seconds,
            title = excluded.title,
            setup = excluded.setup,
            turn = excluded.turn,
            resolution = excluded.resolution,
            notes = excluded.notes,
            updated_at = excluded.updated_at;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ScreenGraphError.capture("Sound scene plan upsert prepare failed: \(sqliteMessage())")
        }
        defer { sqlite3_finalize(statement) }

        bindText(normalized.schemaVersion, to: 1, in: statement)
        bindText(normalized.planId, to: 2, in: statement)
        bindText(normalized.projectId, to: 3, in: statement)
        bindText(normalized.soundId, to: 4, in: statement)
        sqlite3_bind_double(statement, 5, normalized.startSeconds)
        sqlite3_bind_double(statement, 6, normalized.durationSeconds)
        bindText(normalized.title, to: 7, in: statement)
        bindText(normalized.setup, to: 8, in: statement)
        bindText(normalized.turn, to: 9, in: statement)
        bindText(normalized.resolution, to: 10, in: statement)
        bindText(normalized.notes, to: 11, in: statement)
        bindText(normalized.createdAt, to: 12, in: statement)
        bindText(normalized.updatedAt, to: 13, in: statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw ScreenGraphError.capture("Sound scene plan upsert failed: \(sqliteMessage())")
        }
        return normalized
    }

    func deleteSoundScenePlan(project: ProjectRecord, planId: String) throws {
        try ensureReady(for: project)
        guard let connection else { throw ScreenGraphError.capture("Sound timeline DB is not open.") }
        let sql = "DELETE FROM sound_scene_plans WHERE plan_id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ScreenGraphError.capture("Sound scene plan delete prepare failed: \(sqliteMessage())")
        }
        defer { sqlite3_finalize(statement) }
        bindText(planId, to: 1, in: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw ScreenGraphError.capture("Sound scene plan delete failed: \(sqliteMessage())")
        }
    }

    func loadSceneSoundArrangements(project: ProjectRecord) throws -> [SceneSoundArrangement] {
        try ensureReady(for: project)
        guard let connection else { throw ScreenGraphError.capture("Sound arrangement DB is not open.") }
        let sql = """
        SELECT schema_version, arrangement_id, project_id, scene_story_set_id, story_id, sound_id,
               title, active_video_chain_id, created_at, updated_at
        FROM scene_sound_arrangements
        WHERE project_id = ?
        ORDER BY updated_at DESC, title COLLATE NOCASE;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ScreenGraphError.capture("Scene sound arrangement query prepare failed: \(sqliteMessage())")
        }
        defer { sqlite3_finalize(statement) }
        bindText(project.projectId, to: 1, in: statement)

        var arrangements: [SceneSoundArrangement] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let arrangementId = columnText(statement, 1)
            arrangements.append(SceneSoundArrangement(
                schemaVersion: columnText(statement, 0),
                arrangementId: arrangementId,
                projectId: columnText(statement, 2),
                sceneStorySetId: columnText(statement, 3),
                storyId: columnText(statement, 4),
                soundId: columnText(statement, 5),
                title: columnText(statement, 6),
                activeVideoChainId: columnText(statement, 7),
                cards: try loadSceneSoundArrangementCards(arrangementId: arrangementId),
                createdAt: columnText(statement, 8),
                updatedAt: columnText(statement, 9)
            ))
        }
        return arrangements
    }

    func loadSceneSoundArrangement(
        project: ProjectRecord,
        arrangementId: String
    ) throws -> SceneSoundArrangement? {
        try ensureReady(for: project)
        return try loadSceneSoundArrangements(project: project)
            .first { $0.arrangementId == arrangementId }
    }

    func upsertSceneSoundArrangement(
        _ arrangement: SceneSoundArrangement,
        project: ProjectRecord
    ) throws -> SceneSoundArrangement {
        try ensureReady(for: project)
        guard connection != nil else { throw ScreenGraphError.capture("Sound arrangement DB is not open.") }
        let normalized = normalizedArrangement(arrangement, project: project)
        try execute("BEGIN IMMEDIATE;")
        do {
            try upsertSceneSoundArrangementRow(normalized)
            try deleteSceneSoundArrangementCards(arrangementId: normalized.arrangementId)
            for card in normalized.sortedCards {
                try insertSceneSoundArrangementCard(card)
            }
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
        return normalized
    }

    func updateSceneSoundArrangementActiveVideoChain(
        project: ProjectRecord,
        arrangementId: String,
        chainId: String
    ) throws {
        try ensureReady(for: project)
        guard let connection else { throw ScreenGraphError.capture("Sound arrangement DB is not open.") }
        let sql = """
        UPDATE scene_sound_arrangements
        SET active_video_chain_id = ?, updated_at = ?
        WHERE project_id = ? AND arrangement_id = ?;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ScreenGraphError.capture("Scene sound arrangement chain update prepare failed: \(sqliteMessage())")
        }
        defer { sqlite3_finalize(statement) }
        bindText(chainId, to: 1, in: statement)
        bindText(DateFormats.now(), to: 2, in: statement)
        bindText(project.projectId, to: 3, in: statement)
        bindText(arrangementId, to: 4, in: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw ScreenGraphError.capture("Scene sound arrangement chain update failed: \(sqliteMessage())")
        }
    }

    private func scanDefaultSoundAssets() async throws -> [SoundSceneAsset] {
        let urls = defaultSoundFileURLs()
        var assets: [SoundSceneAsset] = []
        for url in urls.sorted(by: { $0.path.localizedStandardCompare($1.path) == .orderedAscending }) {
            guard let asset = try await soundAsset(for: url) else { continue }
            assets.append(asset)
        }
        return assets
    }

    private func defaultSoundFileURLs() -> [URL] {
        let directories = defaultSoundDirectories()
        guard !directories.isEmpty else { return [] }
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isHiddenKey,
            .fileSizeKey,
            .contentModificationDateKey
        ]
        var seenPaths = Set<String>()
        var urls: [URL] = []
        for directory in directories {
            guard let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }
            for case let url as URL in enumerator {
                guard isSupportedSound(url) else { continue }
                guard let values = try? url.resourceValues(forKeys: keys),
                      values.isRegularFile == true,
                      values.isHidden != true else {
                    continue
                }
                let standardizedPath = url.standardizedFileURL.path
                guard !seenPaths.contains(standardizedPath) else { continue }
                seenPaths.insert(standardizedPath)
                urls.append(URL(fileURLWithPath: standardizedPath))
            }
        }
        return urls
    }

    private func soundAsset(for url: URL) async throws -> SoundSceneAsset? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let avAsset = AVURLAsset(url: url)
        let duration = try await avAsset.load(.duration)
        let seconds = duration.seconds.isFinite ? max(duration.seconds, 0) : 0
        let modifiedAt = values.contentModificationDate.map(DateFormats.string(from:)) ?? ""
        let now = DateFormats.now()
        return SoundSceneAsset(
            soundId: "sound_\(shortHash(url.path, length: 16))",
            displayName: url.lastPathComponent,
            path: url.path,
            fileType: url.pathExtension.lowercased(),
            byteCount: Int64(values.fileSize ?? 0),
            modifiedAt: modifiedAt,
            durationSeconds: seconds,
            discoveredAt: now,
            updatedAt: now
        )
    }

    private func defaultSoundDirectories() -> [URL] {
        var candidates: [URL] = []
        if let configured = environmentValue("LITSCENES_SOUND_LIBRARY_DIR")?.trimmed, !configured.isEmpty {
            candidates.append(URL(fileURLWithPath: configured, isDirectory: true).standardizedFileURL)
        }

        var cursor = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true).standardizedFileURL
        for _ in 0..<8 {
            candidates.append(cursor.appendingPathComponent("sounds", isDirectory: true))
            candidates.append(cursor.appendingPathComponent("audio", isDirectory: true))
            let parent = cursor.deletingLastPathComponent()
            guard parent.path != cursor.path else { break }
            cursor = parent
        }

        var seen = Set<String>()
        return candidates.compactMap { url in
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                return nil
            }
            let path = url.standardizedFileURL.path
            guard !seen.contains(path) else { return nil }
            seen.insert(path)
            return URL(fileURLWithPath: path, isDirectory: true)
        }
    }

    private func isSupportedSound(_ url: URL) -> Bool {
        ["wav", "m4a", "mp3", "aiff", "aif", "aac", "caf", "flac"].contains(url.pathExtension.lowercased())
    }

    private func validatedPlan(
        _ plan: SoundScenePlan,
        project: ProjectRecord,
        soundDurationSeconds: Double
    ) throws -> SoundScenePlan {
        var normalized = plan
        let now = DateFormats.now()
        normalized.schemaVersion = soundSceneTimelineSchemaVersion
        normalized.projectId = project.projectId
        normalized.soundId = normalized.soundId.trimmed
        normalized.planId = normalized.planId.trimmed.isEmpty
            ? "sound_scene_plan_\(shortHash("\(normalized.projectId):\(normalized.soundId):\(normalized.startSeconds):\(now)", length: 14))"
            : normalized.planId.trimmed
        normalized.title = normalized.title.trimmed.isEmpty
            ? "Scene \(soundSceneTimecode(normalized.startSeconds))"
            : normalized.title.trimmed
        normalized.setup = normalized.setup.trimmed
        normalized.turn = normalized.turn.trimmed
        normalized.resolution = normalized.resolution.trimmed
        normalized.notes = normalized.notes.trimmed
        normalized.createdAt = normalized.createdAt.trimmed.isEmpty ? now : normalized.createdAt.trimmed
        normalized.updatedAt = now

        guard !normalized.projectId.isEmpty else {
            throw ScreenGraphError.capture("Create or select a project before saving sound scene plans.")
        }
        guard !normalized.soundId.isEmpty else {
            throw ScreenGraphError.capture("Select a sound file before saving scene plans.")
        }
        guard normalized.startSeconds >= 0 else {
            throw ScreenGraphError.capture("Scene start time must be zero or later.")
        }
        guard normalized.durationSeconds > 0 else {
            throw ScreenGraphError.capture("Scene duration must be greater than zero.")
        }
        if soundDurationSeconds > 0, normalized.endSeconds > soundDurationSeconds + 0.05 {
            throw ScreenGraphError.capture("Scene card exceeds the selected sound duration.")
        }

        let existingPlans = try loadSoundScenePlans(project: project, soundId: normalized.soundId)
        for existing in existingPlans where existing.planId != normalized.planId {
            let overlapStart = max(existing.startSeconds, normalized.startSeconds)
            let overlapEnd = min(existing.endSeconds, normalized.endSeconds)
            if overlapStart < overlapEnd - 0.05 {
                throw ScreenGraphError.capture("Sound scene cards cannot overlap.")
            }
        }

        return normalized
    }

    private func upsertSoundAsset(_ asset: SoundSceneAsset) throws {
        guard let connection else { throw ScreenGraphError.capture("Sound timeline DB is not open.") }
        let sql = """
        INSERT INTO sound_assets (
            schema_version, sound_id, display_name, path, file_type, byte_count,
            modified_at, duration_seconds, discovered_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(sound_id) DO UPDATE SET
            schema_version = excluded.schema_version,
            display_name = excluded.display_name,
            path = excluded.path,
            file_type = excluded.file_type,
            byte_count = excluded.byte_count,
            modified_at = excluded.modified_at,
            duration_seconds = excluded.duration_seconds,
            updated_at = excluded.updated_at;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ScreenGraphError.capture("Sound asset upsert prepare failed: \(sqliteMessage())")
        }
        defer { sqlite3_finalize(statement) }

        bindText(asset.schemaVersion, to: 1, in: statement)
        bindText(asset.soundId, to: 2, in: statement)
        bindText(asset.displayName, to: 3, in: statement)
        bindText(asset.path, to: 4, in: statement)
        bindText(asset.fileType, to: 5, in: statement)
        sqlite3_bind_int64(statement, 6, asset.byteCount)
        bindText(asset.modifiedAt, to: 7, in: statement)
        sqlite3_bind_double(statement, 8, asset.durationSeconds)
        bindText(asset.discoveredAt, to: 9, in: statement)
        bindText(asset.updatedAt, to: 10, in: statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw ScreenGraphError.capture("Sound asset upsert failed: \(sqliteMessage())")
        }
    }

    private func loadSceneSoundArrangementCards(arrangementId: String) throws -> [SceneSoundArrangementCard] {
        guard let connection else { throw ScreenGraphError.capture("Sound arrangement DB is not open.") }
        let sql = """
        SELECT card_id, arrangement_id, plan_id, scene_id, scene_order, beat_ids_json,
               start_seconds, duration_seconds, title, setup, turn, resolution, notes, created_at, updated_at
        FROM scene_sound_arrangement_cards
        WHERE arrangement_id = ?
        ORDER BY scene_order, start_seconds;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ScreenGraphError.capture("Scene sound arrangement cards query prepare failed: \(sqliteMessage())")
        }
        defer { sqlite3_finalize(statement) }
        bindText(arrangementId, to: 1, in: statement)

        var cards: [SceneSoundArrangementCard] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            cards.append(SceneSoundArrangementCard(
                cardId: columnText(statement, 0),
                arrangementId: columnText(statement, 1),
                planId: columnText(statement, 2),
                sceneId: columnText(statement, 3),
                sceneOrder: Int(sqlite3_column_int(statement, 4)),
                beatIds: decodeBeatIds(columnText(statement, 5)),
                startSeconds: sqlite3_column_double(statement, 6),
                durationSeconds: sqlite3_column_double(statement, 7),
                title: columnText(statement, 8),
                setup: columnText(statement, 9),
                turn: columnText(statement, 10),
                resolution: columnText(statement, 11),
                notes: columnText(statement, 12),
                createdAt: columnText(statement, 13),
                updatedAt: columnText(statement, 14)
            ))
        }
        return cards
    }

    private func normalizedArrangement(
        _ arrangement: SceneSoundArrangement,
        project: ProjectRecord
    ) -> SceneSoundArrangement {
        let now = DateFormats.now()
        let arrangementId = arrangement.arrangementId.trimmed.isEmpty
            ? "scene_sound_arrangement_\(shortHash("\(project.projectId):\(arrangement.sceneStorySetId):\(arrangement.storyId):\(arrangement.soundId):\(now)", length: 14))"
            : arrangement.arrangementId.trimmed
        let cards = arrangement.cards.enumerated().map { index, card -> SceneSoundArrangementCard in
            let cardId = card.cardId.trimmed.isEmpty
                ? "scene_sound_card_\(shortHash("\(arrangementId):\(card.sceneId):\(index)", length: 14))"
                : card.cardId.trimmed
            return SceneSoundArrangementCard(
                cardId: cardId,
                arrangementId: arrangementId,
                planId: card.planId.trimmed,
                sceneId: card.sceneId.trimmed,
                sceneOrder: max(card.sceneOrder, index + 1),
                beatIds: card.beatIds.map(\.trimmed).filter { !$0.isEmpty },
                startSeconds: max(0, card.startSeconds),
                durationSeconds: max(0.1, card.durationSeconds),
                title: card.title.trimmed.isEmpty ? "Scene \(index + 1)" : card.title.trimmed,
                setup: card.setup.trimmed,
                turn: card.turn.trimmed,
                resolution: card.resolution.trimmed,
                notes: card.notes.trimmed,
                createdAt: card.createdAt.trimmed.isEmpty ? now : card.createdAt.trimmed,
                updatedAt: now
            )
        }
        return SceneSoundArrangement(
            schemaVersion: sceneSoundArrangementSchemaVersion,
            arrangementId: arrangementId,
            projectId: project.projectId,
            sceneStorySetId: arrangement.sceneStorySetId.trimmed,
            storyId: arrangement.storyId.trimmed,
            soundId: arrangement.soundId.trimmed,
            title: arrangement.title.trimmed.isEmpty ? "Sound Arrangement" : arrangement.title.trimmed,
            activeVideoChainId: arrangement.activeVideoChainId.trimmed,
            cards: cards,
            createdAt: arrangement.createdAt.trimmed.isEmpty ? now : arrangement.createdAt.trimmed,
            updatedAt: now
        )
    }

    private func upsertSceneSoundArrangementRow(_ arrangement: SceneSoundArrangement) throws {
        guard let connection else { throw ScreenGraphError.capture("Sound arrangement DB is not open.") }
        let sql = """
        INSERT INTO scene_sound_arrangements (
            schema_version, arrangement_id, project_id, scene_story_set_id, story_id, sound_id,
            title, active_video_chain_id, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(arrangement_id) DO UPDATE SET
            schema_version = excluded.schema_version,
            project_id = excluded.project_id,
            scene_story_set_id = excluded.scene_story_set_id,
            story_id = excluded.story_id,
            sound_id = excluded.sound_id,
            title = excluded.title,
            active_video_chain_id = excluded.active_video_chain_id,
            updated_at = excluded.updated_at;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ScreenGraphError.capture("Scene sound arrangement upsert prepare failed: \(sqliteMessage())")
        }
        defer { sqlite3_finalize(statement) }
        bindText(arrangement.schemaVersion, to: 1, in: statement)
        bindText(arrangement.arrangementId, to: 2, in: statement)
        bindText(arrangement.projectId, to: 3, in: statement)
        bindText(arrangement.sceneStorySetId, to: 4, in: statement)
        bindText(arrangement.storyId, to: 5, in: statement)
        bindText(arrangement.soundId, to: 6, in: statement)
        bindText(arrangement.title, to: 7, in: statement)
        bindText(arrangement.activeVideoChainId, to: 8, in: statement)
        bindText(arrangement.createdAt, to: 9, in: statement)
        bindText(arrangement.updatedAt, to: 10, in: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw ScreenGraphError.capture("Scene sound arrangement upsert failed: \(sqliteMessage())")
        }
    }

    private func deleteSceneSoundArrangementCards(arrangementId: String) throws {
        guard let connection else { throw ScreenGraphError.capture("Sound arrangement DB is not open.") }
        let sql = "DELETE FROM scene_sound_arrangement_cards WHERE arrangement_id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ScreenGraphError.capture("Scene sound arrangement card delete prepare failed: \(sqliteMessage())")
        }
        defer { sqlite3_finalize(statement) }
        bindText(arrangementId, to: 1, in: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw ScreenGraphError.capture("Scene sound arrangement card delete failed: \(sqliteMessage())")
        }
    }

    private func insertSceneSoundArrangementCard(_ card: SceneSoundArrangementCard) throws {
        guard let connection else { throw ScreenGraphError.capture("Sound arrangement DB is not open.") }
        let sql = """
        INSERT INTO scene_sound_arrangement_cards (
            card_id, arrangement_id, plan_id, scene_id, scene_order, beat_ids_json,
            start_seconds, duration_seconds, title, setup, turn, resolution, notes, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ScreenGraphError.capture("Scene sound arrangement card insert prepare failed: \(sqliteMessage())")
        }
        defer { sqlite3_finalize(statement) }
        bindText(card.cardId, to: 1, in: statement)
        bindText(card.arrangementId, to: 2, in: statement)
        bindText(card.planId, to: 3, in: statement)
        bindText(card.sceneId, to: 4, in: statement)
        sqlite3_bind_int(statement, 5, Int32(card.sceneOrder))
        bindText(encodeBeatIds(card.beatIds), to: 6, in: statement)
        sqlite3_bind_double(statement, 7, card.startSeconds)
        sqlite3_bind_double(statement, 8, card.durationSeconds)
        bindText(card.title, to: 9, in: statement)
        bindText(card.setup, to: 10, in: statement)
        bindText(card.turn, to: 11, in: statement)
        bindText(card.resolution, to: 12, in: statement)
        bindText(card.notes, to: 13, in: statement)
        bindText(card.createdAt, to: 14, in: statement)
        bindText(card.updatedAt, to: 15, in: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw ScreenGraphError.capture("Scene sound arrangement card insert failed: \(sqliteMessage())")
        }
    }

    private func encodeBeatIds(_ beatIds: [String]) -> String {
        guard let data = try? JSONCoding.encoder.encode(beatIds),
              let value = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return value
    }

    private func decodeBeatIds(_ value: String) -> [String] {
        guard let data = value.data(using: .utf8),
              let ids = try? JSONCoding.decoder.decode([String].self, from: data) else {
            return []
        }
        return ids
    }

    private func ensureReady(for project: ProjectRecord) throws {
        if initialized, openProjectId == project.projectId { return }
        if let connection {
            sqlite3_close(connection)
            self.connection = nil
        }
        initialized = false
        openProjectId = ""
        let databaseURL = try LitScenesDesktopDatabase.prepareProjectDatabase(
            for: project,
            projectLibrary: projectLibrary
        )
        var db: OpaquePointer?
        guard sqlite3_open_v2(
            databaseURL.path,
            &db,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let db else {
            let message = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "could not open sqlite database"
            if let db {
                sqlite3_close(db)
            }
            throw ScreenGraphError.capture("Sound timeline DB open failed: \(message)")
        }
        connection = db
        try LitScenesDesktopDatabase.ensureProjectSchema(db, project: project, projectLibrary: projectLibrary)
        initialized = true
        openProjectId = project.projectId
    }

    private func execute(_ sql: String) throws {
        guard let connection else { throw ScreenGraphError.capture("Sound timeline DB is not open.") }
        guard sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK else {
            throw ScreenGraphError.capture("Sound timeline SQL failed: \(sqliteMessage())")
        }
    }

    private func sqliteMessage() -> String {
        guard let connection else { return "database is not open" }
        return String(cString: sqlite3_errmsg(connection))
    }
}

private func bindText(_ value: String, to index: Int32, in statement: OpaquePointer) {
    _ = value.withCString { pointer in
        sqlite3_bind_text(statement, index, pointer, -1, soundSceneTimelineSQLiteTransient)
    }
}

private func columnText(_ statement: OpaquePointer, _ index: Int32) -> String {
    guard let pointer = sqlite3_column_text(statement, index) else { return "" }
    return String(cString: pointer)
}

func soundSceneTimecode(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "00:00" }
    let total = max(0, Int(seconds.rounded(.down)))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let remainingSeconds = total % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
    }
    return String(format: "%02d:%02d", minutes, remainingSeconds)
}
