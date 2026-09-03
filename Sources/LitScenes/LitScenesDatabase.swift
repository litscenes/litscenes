import Foundation
import SQLite3

let litScenesSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum LitScenesDesktopDatabase {
    static let registrySchemaVersion = "litscenes.desktop_registry.v0.1"
    static let projectBaseSchemaVersion = "litscenes.desktop_project.v0.1"
    static let projectStorySchemaVersion = "litscenes.desktop_project.v0.2"
    static let projectSchemaVersion = "litscenes.desktop_project.v0.3"
    static let projectGoalThemeSchemaVersion = "litscenes.desktop_project.v0.4"
    static let projectMediaSchemaVersion = "litscenes.desktop_project.v0.5"
    static let projectThemeVersioningSchemaVersion = "litscenes.desktop_project.v0.6"
    static let projectLensSchemaVersion = "litscenes.desktop_project.v0.7"
    static let projectGoalStyleRefsSchemaVersion = "litscenes.desktop_project.v0.8"
    static let projectGoalMoodboardArticulationSchemaVersion = "litscenes.desktop_project.v0.9"
    static let projectLensRenderVersionSchemaVersion = "litscenes.desktop_project.v0.10"
    static let projectLensActiveRenderVersionSchemaVersion = "litscenes.desktop_project.v0.11"
    static let projectAudioMediaKindSchemaVersion = "litscenes.desktop_project.v0.12"
    static let projectMediaStorageSchemaVersion = "litscenes.desktop_project.v0.13"
    static let projectMediaContentHashSchemaVersion = "litscenes.desktop_project.v0.14"
    static let legacySoundTimelineMigrationId = "legacy_sound_scene_timeline_to_project_db_v1"

    static var registryDatabaseURL: URL {
        litScenesApplicationSupportDirectory().appendingPathComponent("LitScenesRegistry.db")
    }

    static var legacySoundTimelineDatabaseURL: URL {
        litScenesApplicationSupportDirectory().appendingPathComponent("sound_scene_timelines.sqlite")
    }

    static func projectDatabaseURL(
        for project: ProjectRecord,
        projectLibrary: ProjectLibrary = ProjectLibrary()
    ) -> URL {
        projectLibrary.projectDirectory(for: project).appendingPathComponent("LitScenes.db")
    }

    static func prepareProjectDatabase(
        for project: ProjectRecord,
        projectLibrary: ProjectLibrary = ProjectLibrary()
    ) throws -> URL {
        try registerProject(project, projectLibrary: projectLibrary)
        let databaseURL = projectDatabaseURL(for: project, projectLibrary: projectLibrary)
        try ensureDirectory(databaseURL.deletingLastPathComponent())
        try withConnection(url: databaseURL, context: "Project DB") { connection in
            try ensureProjectSchema(connection, project: project, projectLibrary: projectLibrary)
        }
        return databaseURL
    }

    static func ensureProjectSchema(
        _ connection: OpaquePointer,
        project: ProjectRecord,
        projectLibrary: ProjectLibrary = ProjectLibrary()
    ) throws {
        try litScenesSQLiteExecute(connection, """
        CREATE TABLE IF NOT EXISTS project_schema_migrations (
            version TEXT PRIMARY KEY,
            applied_at TEXT NOT NULL
        );
        """, context: "Project DB")
        try litScenesSQLiteExecute(connection, """
        CREATE TABLE IF NOT EXISTS project_identity (
            project_id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            project_path TEXT NOT NULL,
            session_count INTEGER NOT NULL DEFAULT 0 CHECK(session_count >= 0),
            last_session_id TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        """, context: "Project DB")
        try ensureColumn(
            connection,
            table: "project_identity",
            column: "session_count",
            definition: "session_count INTEGER NOT NULL DEFAULT 0 CHECK(session_count >= 0)",
            context: "Project DB"
        )
        try ensureColumn(
            connection,
            table: "project_identity",
            column: "last_session_id",
            definition: "last_session_id TEXT",
            context: "Project DB"
        )
        try litScenesSQLiteExecute(connection, """
        CREATE TABLE IF NOT EXISTS sound_assets (
            sound_id TEXT PRIMARY KEY,
            schema_version TEXT NOT NULL,
            display_name TEXT NOT NULL,
            path TEXT NOT NULL UNIQUE,
            file_type TEXT NOT NULL,
            byte_count INTEGER NOT NULL,
            modified_at TEXT NOT NULL,
            duration_seconds REAL NOT NULL,
            discovered_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        """, context: "Project DB")
        try litScenesSQLiteExecute(connection, """
        CREATE TABLE IF NOT EXISTS sound_scene_plans (
            plan_id TEXT PRIMARY KEY,
            schema_version TEXT NOT NULL,
            project_id TEXT NOT NULL,
            sound_id TEXT NOT NULL,
            start_seconds REAL NOT NULL,
            duration_seconds REAL NOT NULL,
            title TEXT NOT NULL,
            setup TEXT NOT NULL,
            turn TEXT NOT NULL,
            resolution TEXT NOT NULL,
            notes TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        """, context: "Project DB")
        try litScenesSQLiteExecute(connection, """
        CREATE TABLE IF NOT EXISTS scene_sound_arrangements (
            arrangement_id TEXT PRIMARY KEY,
            schema_version TEXT NOT NULL,
            project_id TEXT NOT NULL,
            scene_story_set_id TEXT NOT NULL,
            story_id TEXT NOT NULL,
            sound_id TEXT NOT NULL,
            title TEXT NOT NULL,
            active_video_chain_id TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        """, context: "Project DB")
        try litScenesSQLiteExecute(connection, """
        CREATE TABLE IF NOT EXISTS scene_sound_arrangement_cards (
            card_id TEXT PRIMARY KEY,
            arrangement_id TEXT NOT NULL,
            plan_id TEXT NOT NULL,
            scene_id TEXT NOT NULL,
            scene_order INTEGER NOT NULL,
            beat_ids_json TEXT NOT NULL,
            start_seconds REAL NOT NULL,
            duration_seconds REAL NOT NULL,
            title TEXT NOT NULL,
            setup TEXT NOT NULL,
            turn TEXT NOT NULL,
            resolution TEXT NOT NULL,
            notes TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY(arrangement_id) REFERENCES scene_sound_arrangements(arrangement_id) ON DELETE CASCADE
        );
        """, context: "Project DB")
        try litScenesSQLiteExecute(connection, "CREATE INDEX IF NOT EXISTS sound_assets_path_idx ON sound_assets(path);", context: "Project DB")
        try litScenesSQLiteExecute(connection, "CREATE INDEX IF NOT EXISTS sound_scene_plans_project_sound_idx ON sound_scene_plans(project_id, sound_id, start_seconds);", context: "Project DB")
        try litScenesSQLiteExecute(connection, "CREATE INDEX IF NOT EXISTS sound_scene_plans_sound_idx ON sound_scene_plans(sound_id, start_seconds);", context: "Project DB")
        try litScenesSQLiteExecute(connection, "CREATE INDEX IF NOT EXISTS scene_sound_arrangements_project_idx ON scene_sound_arrangements(project_id, updated_at);", context: "Project DB")
        try litScenesSQLiteExecute(connection, "CREATE INDEX IF NOT EXISTS scene_sound_arrangements_story_sound_idx ON scene_sound_arrangements(project_id, scene_story_set_id, story_id, sound_id);", context: "Project DB")
        try litScenesSQLiteExecute(connection, "CREATE INDEX IF NOT EXISTS scene_sound_arrangement_cards_arrangement_idx ON scene_sound_arrangement_cards(arrangement_id, scene_order);", context: "Project DB")
        try insertMigration(connection, table: "project_schema_migrations", version: projectBaseSchemaVersion, context: "Project DB")
        try migrateProjectSchemaV2IfNeeded(connection, project: project, projectLibrary: projectLibrary)
        try migrateProjectSchemaV3IfNeeded(connection)
        try migrateProjectSchemaV4IfNeeded(connection, project: project, projectLibrary: projectLibrary)
        try migrateProjectSchemaV5IfNeeded(connection, project: project, projectLibrary: projectLibrary)
        try migrateProjectSchemaV6IfNeeded(connection, project: project, projectLibrary: projectLibrary)
        try migrateProjectSchemaV7IfNeeded(connection, project: project, projectLibrary: projectLibrary)
        try migrateProjectSchemaV8IfNeeded(connection)
        try migrateProjectSchemaV9IfNeeded(connection)
        try migrateProjectSchemaV10IfNeeded(connection)
        try migrateProjectSchemaV11IfNeeded(connection)
        try migrateProjectSchemaV12IfNeeded(connection, project: project, projectLibrary: projectLibrary)
        try migrateProjectSchemaV13IfNeeded(connection)
        try migrateProjectSchemaV14IfNeeded(connection)
        try upsertProjectIdentity(connection, project: project, projectLibrary: projectLibrary)
    }

    static func withConnection<T>(
        url: URL,
        flags: Int32 = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
        context: String,
        _ body: (OpaquePointer) throws -> T
    ) throws -> T {
        try ensureDirectory(url.deletingLastPathComponent())
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, flags, nil) == SQLITE_OK, let connection = db else {
            let message = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "could not open sqlite database"
            if let db {
                sqlite3_close(db)
            }
            throw ScreenGraphError.capture("\(context) open failed: \(message)")
        }
        defer { sqlite3_close(connection) }
        try configureConnection(connection, context: context)
        return try body(connection)
    }

    private static func registerProject(
        _ project: ProjectRecord,
        projectLibrary: ProjectLibrary
    ) throws {
        let projectURL = projectLibrary.projectDirectory(for: project)
        let databaseURL = projectDatabaseURL(for: project, projectLibrary: projectLibrary)
        try withRegistryConnection { connection in
            let sql = """
            INSERT INTO projects (
                project_id, name, project_path, database_path, session_count, last_session_id, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(project_id) DO UPDATE SET
                name = excluded.name,
                project_path = excluded.project_path,
                database_path = excluded.database_path,
                session_count = excluded.session_count,
                last_session_id = excluded.last_session_id,
                updated_at = excluded.updated_at;
            """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw ScreenGraphError.capture("Registry project upsert prepare failed: \(litScenesSQLiteMessage(connection))")
            }
            defer { sqlite3_finalize(statement) }
            litScenesSQLiteBindText(project.projectId, to: 1, in: statement)
            litScenesSQLiteBindText(project.name, to: 2, in: statement)
            litScenesSQLiteBindText(projectURL.path, to: 3, in: statement)
            litScenesSQLiteBindText(databaseURL.path, to: 4, in: statement)
            sqlite3_bind_int64(statement, 5, sqlite3_int64(project.sessionCount))
            if let lastSessionId = project.lastSessionId {
                litScenesSQLiteBindText(lastSessionId, to: 6, in: statement)
            } else {
                sqlite3_bind_null(statement, 6)
            }
            litScenesSQLiteBindText(project.createdAt, to: 7, in: statement)
            litScenesSQLiteBindText(project.updatedAt, to: 8, in: statement)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw ScreenGraphError.capture("Registry project upsert failed: \(litScenesSQLiteMessage(connection))")
            }
        }
    }

    static func listCurrentProjects(projectLibrary: ProjectLibrary = ProjectLibrary()) throws -> [ProjectRecord] {
        let rootPath = projectLibrary.root.standardizedFileURL.path
        return try withRegistryConnection { connection in
            let sql = """
            SELECT project_id, name, project_path, database_path, session_count, last_session_id, created_at, updated_at
            FROM projects
            ORDER BY updated_at DESC, name COLLATE NOCASE ASC;
            """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw ScreenGraphError.capture("Registry project list prepare failed: \(litScenesSQLiteMessage(connection))")
            }
            defer { sqlite3_finalize(statement) }
            var projects: [ProjectRecord] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let projectPath = litScenesSQLiteColumnText(statement, 2)
                guard projectPath == rootPath || projectPath.hasPrefix(rootPath + "/") else {
                    continue
                }
                let databasePath = litScenesSQLiteColumnText(statement, 3)
                guard projectDatabaseHasCurrentSchema(URL(fileURLWithPath: databasePath)) else {
                    continue
                }
                let lastSessionId = sqlite3_column_type(statement, 5) == SQLITE_NULL
                    ? nil
                    : litScenesSQLiteColumnText(statement, 5)
                projects.append(ProjectRecord(
                    projectId: litScenesSQLiteColumnText(statement, 0),
                    name: litScenesSQLiteColumnText(statement, 1),
                    createdAt: litScenesSQLiteColumnText(statement, 6),
                    updatedAt: litScenesSQLiteColumnText(statement, 7),
                    sessionCount: Int(sqlite3_column_int(statement, 4)),
                    lastSessionId: lastSessionId
                ))
            }
            return projects
        }
    }

    private static func projectDatabaseHasCurrentSchema(_ databaseURL: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return false }
        var db: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let connection = db else {
            if let db {
                sqlite3_close(db)
            }
            return false
        }
        defer { sqlite3_close(connection) }
        var statement: OpaquePointer?
        let sql = "SELECT 1 FROM project_schema_migrations WHERE version = ? LIMIT 1;"
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return false
        }
        defer { sqlite3_finalize(statement) }
        litScenesSQLiteBindText(projectSchemaVersion, to: 1, in: statement)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private static func migrateLegacySoundTimelineIfNeeded(projectLibrary: ProjectLibrary) throws {
        let legacyURL = legacySoundTimelineDatabaseURL
        guard FileManager.default.fileExists(atPath: legacyURL.path) else { return }
        guard try !legacyMigrationCompleted() else { return }

        let projects = try projectLibrary.listProjects()
        guard !projects.isEmpty else { return }

        var legacyAssets: [SoundSceneAsset] = []
        var legacyPlans: [SoundScenePlan] = []
        try withConnection(
            url: legacyURL,
            flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            context: "Legacy sound timeline DB"
        ) { connection in
            legacyAssets = try loadLegacySoundAssets(connection)
            legacyPlans = try loadLegacySoundScenePlans(connection)
        }

        var migratedProjectCount = 0
        var migratedPlanCount = 0
        let plansByProject = Dictionary(grouping: legacyPlans, by: \.projectId)
        let assetsById = Dictionary(uniqueKeysWithValues: legacyAssets.map { ($0.soundId, $0) })
        for project in projects {
            let projectPlans = plansByProject[project.projectId] ?? []
            guard !projectPlans.isEmpty else { continue }
            let projectURL = projectDatabaseURL(for: project, projectLibrary: projectLibrary)
            try withConnection(url: projectURL, context: "Project DB") { connection in
                try ensureProjectSchema(connection, project: project, projectLibrary: projectLibrary)
                try litScenesSQLiteExecute(connection, "BEGIN IMMEDIATE;", context: "Project DB")
                do {
                    let referencedSoundIds = Set(projectPlans.map(\.soundId))
                    for soundId in referencedSoundIds {
                        if let asset = assetsById[soundId] {
                            try upsertSoundAsset(asset, connection: connection)
                        }
                    }
                    for plan in projectPlans {
                        try upsertSoundScenePlan(plan, connection: connection)
                    }
                    try litScenesSQLiteExecute(connection, "COMMIT;", context: "Project DB")
                } catch {
                    try? litScenesSQLiteExecute(connection, "ROLLBACK;", context: "Project DB")
                    throw error
                }
            }
            migratedProjectCount += 1
            migratedPlanCount += projectPlans.count
        }

        try markLegacyMigrationCompleted(
            "projects=\(migratedProjectCount); plans=\(migratedPlanCount)"
        )
        try deprecateLegacySoundTimelineDatabase(legacyURL)
    }

    private static func ensureRegistrySchema(_ connection: OpaquePointer) throws {
        try litScenesSQLiteExecute(connection, """
        CREATE TABLE IF NOT EXISTS registry_schema_migrations (
            version TEXT PRIMARY KEY,
            applied_at TEXT NOT NULL
        );
        """, context: "Registry DB")
        try litScenesSQLiteExecute(connection, """
        CREATE TABLE IF NOT EXISTS projects (
            project_id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            project_path TEXT NOT NULL,
            database_path TEXT NOT NULL,
            session_count INTEGER NOT NULL DEFAULT 0 CHECK(session_count >= 0),
            last_session_id TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        """, context: "Registry DB")
        try ensureColumn(
            connection,
            table: "projects",
            column: "session_count",
            definition: "session_count INTEGER NOT NULL DEFAULT 0 CHECK(session_count >= 0)",
            context: "Registry DB"
        )
        try ensureColumn(
            connection,
            table: "projects",
            column: "last_session_id",
            definition: "last_session_id TEXT",
            context: "Registry DB"
        )
        try litScenesSQLiteExecute(connection, """
        CREATE TABLE IF NOT EXISTS legacy_migrations (
            migration_id TEXT PRIMARY KEY,
            completed_at TEXT NOT NULL,
            details TEXT NOT NULL
        );
        """, context: "Registry DB")
        try litScenesSQLiteExecute(connection, "CREATE INDEX IF NOT EXISTS projects_updated_at_idx ON projects(updated_at);", context: "Registry DB")
        try insertMigration(connection, table: "registry_schema_migrations", version: registrySchemaVersion, context: "Registry DB")
    }

    private static func withRegistryConnection<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        try withConnection(url: registryDatabaseURL, context: "Registry DB") { connection in
            try ensureRegistrySchema(connection)
            return try body(connection)
        }
    }

    private static func legacyMigrationCompleted() throws -> Bool {
        try withRegistryConnection { connection in
            let sql = "SELECT 1 FROM legacy_migrations WHERE migration_id = ? LIMIT 1;"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw ScreenGraphError.capture("Legacy migration query prepare failed: \(litScenesSQLiteMessage(connection))")
            }
            defer { sqlite3_finalize(statement) }
            litScenesSQLiteBindText(legacySoundTimelineMigrationId, to: 1, in: statement)
            return sqlite3_step(statement) == SQLITE_ROW
        }
    }

    private static func markLegacyMigrationCompleted(_ details: String) throws {
        try withRegistryConnection { connection in
            let sql = """
            INSERT INTO legacy_migrations (migration_id, completed_at, details)
            VALUES (?, ?, ?)
            ON CONFLICT(migration_id) DO UPDATE SET
                completed_at = excluded.completed_at,
                details = excluded.details;
            """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw ScreenGraphError.capture("Legacy migration mark prepare failed: \(litScenesSQLiteMessage(connection))")
            }
            defer { sqlite3_finalize(statement) }
            litScenesSQLiteBindText(legacySoundTimelineMigrationId, to: 1, in: statement)
            litScenesSQLiteBindText(DateFormats.now(), to: 2, in: statement)
            litScenesSQLiteBindText(details, to: 3, in: statement)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw ScreenGraphError.capture("Legacy migration mark failed: \(litScenesSQLiteMessage(connection))")
            }
        }
    }

    private static func deprecateLegacySoundTimelineDatabase(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let timestamp = safeIdentifier(DateFormats.now())
        let destination = url.deletingLastPathComponent()
            .appendingPathComponent(".deprecated_sound_scene_timelines.sqlite_\(timestamp)")
        guard !FileManager.default.fileExists(atPath: destination.path) else { return }
        try FileManager.default.moveItem(at: url, to: destination)
    }

    private static func upsertProjectIdentity(
        _ connection: OpaquePointer,
        project: ProjectRecord,
        projectLibrary: ProjectLibrary
    ) throws {
        let sql = """
        INSERT INTO project_identity (
            project_id, name, project_path, session_count, last_session_id, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(project_id) DO UPDATE SET
            name = excluded.name,
            project_path = excluded.project_path,
            session_count = excluded.session_count,
            last_session_id = excluded.last_session_id,
            updated_at = excluded.updated_at;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ScreenGraphError.capture("Project identity upsert prepare failed: \(litScenesSQLiteMessage(connection))")
        }
        defer { sqlite3_finalize(statement) }
        litScenesSQLiteBindText(project.projectId, to: 1, in: statement)
        litScenesSQLiteBindText(project.name, to: 2, in: statement)
        litScenesSQLiteBindText(projectLibrary.projectDirectory(for: project).path, to: 3, in: statement)
        sqlite3_bind_int64(statement, 4, sqlite3_int64(project.sessionCount))
        if let lastSessionId = project.lastSessionId {
            litScenesSQLiteBindText(lastSessionId, to: 5, in: statement)
        } else {
            sqlite3_bind_null(statement, 5)
        }
        litScenesSQLiteBindText(project.createdAt, to: 6, in: statement)
        litScenesSQLiteBindText(project.updatedAt, to: 7, in: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw ScreenGraphError.capture("Project identity upsert failed: \(litScenesSQLiteMessage(connection))")
        }
    }

    private static func insertMigration(
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

    private static func configureConnection(_ connection: OpaquePointer, context: String) throws {
        try litScenesSQLiteExecute(connection, "PRAGMA foreign_keys = ON;", context: context)
        try litScenesSQLiteExecute(connection, "PRAGMA busy_timeout = 5000;", context: context)
    }

    private static func ensureColumn(
        _ connection: OpaquePointer,
        table: String,
        column: String,
        definition: String,
        context: String
    ) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, "PRAGMA table_info(\(table));", -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ScreenGraphError.capture("\(context) table_info prepare failed: \(litScenesSQLiteMessage(connection))")
        }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            if litScenesSQLiteColumnText(statement, 1) == column {
                return
            }
        }
        try litScenesSQLiteExecute(connection, "ALTER TABLE \(table) ADD COLUMN \(definition);", context: context)
    }

    private static func columnExists(
        _ connection: OpaquePointer,
        table: String,
        column: String,
        context: String
    ) throws -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, "PRAGMA table_info(\(table));", -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ScreenGraphError.capture("\(context) table_info prepare failed: \(litScenesSQLiteMessage(connection))")
        }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            if litScenesSQLiteColumnText(statement, 1) == column {
                return true
            }
        }
        return false
    }

    private static func migrationApplied(
        _ connection: OpaquePointer,
        table: String,
        version: String,
        context: String
    ) throws -> Bool {
        let sql = "SELECT 1 FROM \(table) WHERE version = ? LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ScreenGraphError.capture("\(context) migration lookup prepare failed: \(litScenesSQLiteMessage(connection))")
        }
        defer { sqlite3_finalize(statement) }
        litScenesSQLiteBindText(version, to: 1, in: statement)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private static func migrateProjectSchemaV2IfNeeded(
        _ connection: OpaquePointer,
        project: ProjectRecord,
        projectLibrary: ProjectLibrary
    ) throws {
        guard try !migrationApplied(
            connection,
            table: "project_schema_migrations",
            version: projectStorySchemaVersion,
            context: "Project DB"
        ) else {
            return
        }

        try backupProjectDatabaseBeforeV2Migration(project: project, projectLibrary: projectLibrary)
        try litScenesSQLiteExecute(connection, "BEGIN IMMEDIATE;", context: "Project DB")
        do {
            try createProjectStorySchemaV2(connection)
            try insertMigration(connection, table: "project_schema_migrations", version: projectStorySchemaVersion, context: "Project DB")
            try runProjectIntegrityChecks(connection, context: "Project DB")
            try litScenesSQLiteExecute(connection, "COMMIT;", context: "Project DB")
        } catch {
            try? litScenesSQLiteExecute(connection, "ROLLBACK;", context: "Project DB")
            throw error
        }
    }

    private static func migrateProjectSchemaV3IfNeeded(_ connection: OpaquePointer) throws {
        guard try !migrationApplied(
            connection,
            table: "project_schema_migrations",
            version: projectSchemaVersion,
            context: "Project DB"
        ) else {
            return
        }

        try litScenesSQLiteExecute(connection, "BEGIN IMMEDIATE;", context: "Project DB")
        do {
            try createCanonicalProjectDocumentSchemaV3(connection)
            try insertMigration(connection, table: "project_schema_migrations", version: projectSchemaVersion, context: "Project DB")
            try runProjectIntegrityChecks(connection, context: "Project DB")
            try litScenesSQLiteExecute(connection, "COMMIT;", context: "Project DB")
        } catch {
            try? litScenesSQLiteExecute(connection, "ROLLBACK;", context: "Project DB")
            throw error
        }
    }

    private static func migrateProjectSchemaV4IfNeeded(
        _ connection: OpaquePointer,
        project: ProjectRecord,
        projectLibrary: ProjectLibrary
    ) throws {
        guard try !migrationApplied(
            connection,
            table: "project_schema_migrations",
            version: projectGoalThemeSchemaVersion,
            context: "Project DB"
        ) else {
            return
        }

        try backupProjectDatabaseBeforeV4Migration(project: project, projectLibrary: projectLibrary)
        try litScenesSQLiteExecute(connection, "BEGIN IMMEDIATE;", context: "Project DB")
        do {
            try createGoalThemeSchemaV4(connection)
            try insertMigration(connection, table: "project_schema_migrations", version: projectGoalThemeSchemaVersion, context: "Project DB")
            try runProjectIntegrityChecks(connection, context: "Project DB")
            try litScenesSQLiteExecute(connection, "COMMIT;", context: "Project DB")
        } catch {
            try? litScenesSQLiteExecute(connection, "ROLLBACK;", context: "Project DB")
            throw error
        }
    }

    private static func migrateProjectSchemaV5IfNeeded(
        _ connection: OpaquePointer,
        project: ProjectRecord,
        projectLibrary: ProjectLibrary
    ) throws {
        guard try !migrationApplied(
            connection,
            table: "project_schema_migrations",
            version: projectMediaSchemaVersion,
            context: "Project DB"
        ) else {
            return
        }

        try backupProjectDatabaseBeforeV5Migration(project: project, projectLibrary: projectLibrary)
        try litScenesSQLiteExecute(connection, "BEGIN IMMEDIATE;", context: "Project DB")
        do {
            try createProjectMediaSchemaV5(connection)
            try insertMigration(connection, table: "project_schema_migrations", version: projectMediaSchemaVersion, context: "Project DB")
            try runProjectIntegrityChecks(connection, context: "Project DB")
            try litScenesSQLiteExecute(connection, "COMMIT;", context: "Project DB")
        } catch {
            try? litScenesSQLiteExecute(connection, "ROLLBACK;", context: "Project DB")
            throw error
        }
    }

    private static func migrateProjectSchemaV6IfNeeded(
        _ connection: OpaquePointer,
        project: ProjectRecord,
        projectLibrary: ProjectLibrary
    ) throws {
        guard try !migrationApplied(
            connection,
            table: "project_schema_migrations",
            version: projectThemeVersioningSchemaVersion,
            context: "Project DB"
        ) else {
            return
        }

        try backupProjectDatabaseBeforeV6Migration(project: project, projectLibrary: projectLibrary)
        try litScenesSQLiteExecute(connection, "BEGIN IMMEDIATE;", context: "Project DB")
        do {
            try createProjectLensVersioningSchemaV6(connection)
            try insertMigration(connection, table: "project_schema_migrations", version: projectThemeVersioningSchemaVersion, context: "Project DB")
            try runProjectIntegrityChecks(connection, context: "Project DB")
            try litScenesSQLiteExecute(connection, "COMMIT;", context: "Project DB")
        } catch {
            try? litScenesSQLiteExecute(connection, "ROLLBACK;", context: "Project DB")
            throw error
        }
    }

    private static func migrateProjectSchemaV7IfNeeded(
        _ connection: OpaquePointer,
        project: ProjectRecord,
        projectLibrary: ProjectLibrary
    ) throws {
        guard try !migrationApplied(
            connection,
            table: "project_schema_migrations",
            version: projectLensSchemaVersion,
            context: "Project DB"
        ) else {
            return
        }

        try backupProjectDatabaseBeforeV7Migration(project: project, projectLibrary: projectLibrary)
        try litScenesSQLiteExecute(connection, "BEGIN IMMEDIATE;", context: "Project DB")
        do {
            try createProjectLensSchemaV7(connection)
            try backfillProjectLensSchemaV7(connection)
            try insertMigration(connection, table: "project_schema_migrations", version: projectLensSchemaVersion, context: "Project DB")
            try runProjectIntegrityChecks(connection, context: "Project DB")
            try litScenesSQLiteExecute(connection, "COMMIT;", context: "Project DB")
        } catch {
            try? litScenesSQLiteExecute(connection, "ROLLBACK;", context: "Project DB")
            throw error
        }
    }

    private static func migrateProjectSchemaV8IfNeeded(_ connection: OpaquePointer) throws {
        guard try !migrationApplied(
            connection,
            table: "project_schema_migrations",
            version: projectGoalStyleRefsSchemaVersion,
            context: "Project DB"
        ) else {
            return
        }

        try litScenesSQLiteExecute(connection, "BEGIN IMMEDIATE;", context: "Project DB")
        do {
            try litScenesSQLiteExecute(connection, """
            CREATE TABLE IF NOT EXISTS project_goal_style_term_refs (
                version_id TEXT NOT NULL,
                ref_order INTEGER NOT NULL CHECK(ref_order >= 0),
                term TEXT NOT NULL,
                kind TEXT NOT NULL,
                weight REAL NOT NULL DEFAULT 1,
                rationale TEXT NOT NULL DEFAULT '',
                PRIMARY KEY(version_id, ref_order),
                FOREIGN KEY(version_id) REFERENCES project_goal_versions(version_id) ON DELETE CASCADE
            );
            """, context: "Project DB")
            try insertMigration(connection, table: "project_schema_migrations", version: projectGoalStyleRefsSchemaVersion, context: "Project DB")
            try runProjectIntegrityChecks(connection, context: "Project DB")
            try litScenesSQLiteExecute(connection, "COMMIT;", context: "Project DB")
        } catch {
            try? litScenesSQLiteExecute(connection, "ROLLBACK;", context: "Project DB")
            throw error
        }
    }

    private static func migrateProjectSchemaV9IfNeeded(_ connection: OpaquePointer) throws {
        guard try !migrationApplied(
            connection,
            table: "project_schema_migrations",
            version: projectGoalMoodboardArticulationSchemaVersion,
            context: "Project DB"
        ) else {
            return
        }

        try litScenesSQLiteExecute(connection, "BEGIN IMMEDIATE;", context: "Project DB")
        do {
            try ensureColumn(
                connection,
                table: "project_goal_versions",
                column: "moodboard_articulation",
                definition: "moodboard_articulation TEXT NOT NULL DEFAULT ''",
                context: "Project DB"
            )
            try litScenesSQLiteExecute(
                connection,
                "UPDATE project_goal_state SET schema_version = 'litscenes.project_goal.v0.4' WHERE schema_version = 'litscenes.project_goal.v0.3';",
                context: "Project DB"
            )
            try insertMigration(connection, table: "project_schema_migrations", version: projectGoalMoodboardArticulationSchemaVersion, context: "Project DB")
            try runProjectIntegrityChecks(connection, context: "Project DB")
            try litScenesSQLiteExecute(connection, "COMMIT;", context: "Project DB")
        } catch {
            try? litScenesSQLiteExecute(connection, "ROLLBACK;", context: "Project DB")
            throw error
        }
    }

    private static func migrateProjectSchemaV10IfNeeded(_ connection: OpaquePointer) throws {
        guard try !migrationApplied(
            connection,
            table: "project_schema_migrations",
            version: projectLensRenderVersionSchemaVersion,
            context: "Project DB"
        ) else {
            return
        }

        try litScenesSQLiteExecute(connection, "BEGIN IMMEDIATE;", context: "Project DB")
        do {
            try ensureColumn(connection, table: "project_lens_hero_images", column: "render_version_id", definition: "render_version_id TEXT NOT NULL DEFAULT ''", context: "Project DB")
            try ensureColumn(connection, table: "project_lens_hero_images", column: "render_target_id", definition: "render_target_id TEXT NOT NULL DEFAULT ''", context: "Project DB")
            try ensureColumn(connection, table: "project_lens_hero_images", column: "render_stack_fingerprint", definition: "render_stack_fingerprint TEXT NOT NULL DEFAULT ''", context: "Project DB")
            try ensureColumn(connection, table: "project_lens_hero_images", column: "render_version_group_id", definition: "render_version_group_id TEXT NOT NULL DEFAULT ''", context: "Project DB")
            try ensureColumn(connection, table: "project_lens_hero_images", column: "version_number", definition: "version_number INTEGER NOT NULL DEFAULT 0", context: "Project DB")
            try ensureColumn(connection, table: "project_lens_hero_images", column: "seed", definition: "seed TEXT NOT NULL DEFAULT ''", context: "Project DB")
            try ensureColumn(connection, table: "project_lens_hero_images", column: "final_prompt_fingerprint", definition: "final_prompt_fingerprint TEXT NOT NULL DEFAULT ''", context: "Project DB")
            try ensureColumn(connection, table: "project_lens_hero_images", column: "render_params_fingerprint", definition: "render_params_fingerprint TEXT NOT NULL DEFAULT ''", context: "Project DB")
            try litScenesSQLiteExecute(
                connection,
                "CREATE INDEX IF NOT EXISTS project_lens_hero_images_render_group_idx ON project_lens_hero_images(version_id, lens_id, render_version_group_id, version_number);",
                context: "Project DB"
            )
            try litScenesSQLiteExecute(
                connection,
                "CREATE INDEX IF NOT EXISTS project_lens_hero_images_render_target_stack_idx ON project_lens_hero_images(version_id, lens_id, render_target_id, render_stack_fingerprint);",
                context: "Project DB"
            )
            try insertMigration(connection, table: "project_schema_migrations", version: projectLensRenderVersionSchemaVersion, context: "Project DB")
            try runProjectIntegrityChecks(connection, context: "Project DB")
            try litScenesSQLiteExecute(connection, "COMMIT;", context: "Project DB")
        } catch {
            try? litScenesSQLiteExecute(connection, "ROLLBACK;", context: "Project DB")
            throw error
        }
    }

    private static func migrateProjectSchemaV11IfNeeded(_ connection: OpaquePointer) throws {
        guard try !migrationApplied(
            connection,
            table: "project_schema_migrations",
            version: projectLensActiveRenderVersionSchemaVersion,
            context: "Project DB"
        ) else {
            return
        }

        try litScenesSQLiteExecute(connection, "BEGIN IMMEDIATE;", context: "Project DB")
        do {
            try ensureColumn(
                connection,
                table: "project_lens_hero_images",
                column: "is_active_render_version",
                definition: "is_active_render_version INTEGER NOT NULL DEFAULT 0 CHECK(is_active_render_version IN (0, 1))",
                context: "Project DB"
            )
            try litScenesSQLiteExecute(
                connection,
                "CREATE INDEX IF NOT EXISTS project_lens_hero_images_active_render_idx ON project_lens_hero_images(version_id, lens_id, render_version_group_id, is_active_render_version);",
                context: "Project DB"
            )
            try insertMigration(connection, table: "project_schema_migrations", version: projectLensActiveRenderVersionSchemaVersion, context: "Project DB")
            try runProjectIntegrityChecks(connection, context: "Project DB")
            try litScenesSQLiteExecute(connection, "COMMIT;", context: "Project DB")
        } catch {
            try? litScenesSQLiteExecute(connection, "ROLLBACK;", context: "Project DB")
            throw error
        }
    }

    /// Widens `media_items.kind` to admit 'audio'. Databases created before
    /// the audio-kind migration carry `CHECK(kind IN ('image', 'video'))`, so importing an mp3
    /// into an existing project failed with a CHECK constraint violation even
    /// though `MediaKind` had already grown the case. SQLite cannot alter a
    /// CHECK constraint, so the table is rebuilt.
    private static func migrateProjectSchemaV12IfNeeded(
        _ connection: OpaquePointer,
        project: ProjectRecord,
        projectLibrary: ProjectLibrary
    ) throws {
        guard try !migrationApplied(
            connection,
            table: "project_schema_migrations",
            version: projectAudioMediaKindSchemaVersion,
            context: "Project DB"
        ) else {
            return
        }

        // Freshly created databases already carry the widened CHECK from the V5
        // schema, so they only need the migration row.
        let needsRebuild = try mediaItemsKindCheckRejectsAudio(connection)
        if needsRebuild {
            try backupProjectDatabaseBeforeV12Migration(project: project, projectLibrary: projectLibrary)
        }

        try litScenesSQLiteExecute(connection, "BEGIN IMMEDIATE;", context: "Project DB")
        do {
            if needsRebuild {
                try rebuildMediaItemsForAudioKind(connection)
            }
            try insertMigration(connection, table: "project_schema_migrations", version: projectAudioMediaKindSchemaVersion, context: "Project DB")
            try runProjectIntegrityChecks(connection, context: "Project DB")
            try litScenesSQLiteExecute(connection, "COMMIT;", context: "Project DB")
        } catch {
            try? litScenesSQLiteExecute(connection, "ROLLBACK;", context: "Project DB")
            throw error
        }
    }

    private static func mediaItemsKindCheckRejectsAudio(_ connection: OpaquePointer) throws -> Bool {
        let sql = try scalarText(
            connection,
            sql: "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'media_items';",
            context: "Project DB"
        )
        guard !sql.isEmpty else { return false }
        return !sql.contains("'audio'")
    }

    /// Rebuilds `media_items` in place. Nothing foreign-key references this
    /// table — it is only ever a child of `project_identity` — so the copied
    /// rows stay valid and foreign keys can remain enabled throughout.
    private static func rebuildMediaItemsForAudioKind(_ connection: OpaquePointer) throws {
        let columns = """
        project_id, media_id, item_order, source_id, kind, filename, path, relative_path,
        byte_count, modified_at, width, height, duration_seconds, nominal_frame_rate,
        thumbnail_path, video_strip_path, scanned_at, scan_error, derivative_kind,
        source_media_id, source_timestamp_seconds, frame_index, content_fingerprint,
        record_revision
        """
        let statements = [
            """
            CREATE TABLE media_items_v12 (
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
            "INSERT INTO media_items_v12 (\(columns)) SELECT \(columns) FROM media_items;",
            "DROP TABLE media_items;",
            "ALTER TABLE media_items_v12 RENAME TO media_items;",
            "CREATE INDEX IF NOT EXISTS media_items_project_order_idx ON media_items(project_id, item_order);",
            "CREATE INDEX IF NOT EXISTS media_items_project_kind_idx ON media_items(project_id, kind);",
            "CREATE INDEX IF NOT EXISTS media_items_project_source_idx ON media_items(project_id, source_id);",
            "CREATE INDEX IF NOT EXISTS media_items_project_derivative_idx ON media_items(project_id, derivative_kind);",
            "CREATE INDEX IF NOT EXISTS media_items_project_source_media_idx ON media_items(project_id, source_media_id);"
        ]
        for statement in statements {
            try litScenesSQLiteExecute(connection, statement, context: "Project DB")
        }
    }

    /// Adds explicit ownership/provenance to media sources without touching
    /// file bytes. Every pre-existing external source remains linked; the
    /// synthetic Generated Media row is project-owned.
    private static func migrateProjectSchemaV13IfNeeded(_ connection: OpaquePointer) throws {
        guard try !migrationApplied(
            connection,
            table: "project_schema_migrations",
            version: projectMediaStorageSchemaVersion,
            context: "Project DB"
        ) else {
            return
        }

        try litScenesSQLiteExecute(connection, "BEGIN IMMEDIATE;", context: "Project DB")
        do {
            try ensureColumn(
                connection,
                table: "media_sources",
                column: "storage_mode",
                definition: "storage_mode TEXT NOT NULL DEFAULT 'linked' CHECK(storage_mode IN ('managed', 'linked'))",
                context: "Project DB"
            )
            try ensureColumn(
                connection,
                table: "media_sources",
                column: "original_path",
                definition: "original_path TEXT NOT NULL DEFAULT ''",
                context: "Project DB"
            )
            try ensureColumn(
                connection,
                table: "media_sources",
                column: "original_bookmark_data_base64",
                definition: "original_bookmark_data_base64 TEXT NOT NULL DEFAULT ''",
                context: "Project DB"
            )
            try litScenesSQLiteExecute(
                connection,
                "UPDATE media_sources SET original_path = path WHERE original_path = '' AND source_id != 'source_generated_media';",
                context: "Project DB"
            )
            try litScenesSQLiteExecute(
                connection,
                "UPDATE media_sources SET storage_mode = 'managed' WHERE source_id = 'source_generated_media';",
                context: "Project DB"
            )
            try insertMigration(
                connection,
                table: "project_schema_migrations",
                version: projectMediaStorageSchemaVersion,
                context: "Project DB"
            )
            try runProjectIntegrityChecks(connection, context: "Project DB")
            try litScenesSQLiteExecute(connection, "COMMIT;", context: "Project DB")
        } catch {
            try? litScenesSQLiteExecute(connection, "ROLLBACK;", context: "Project DB")
            throw error
        }
    }

    /// Media items gain a content hash (sha256 of the original bytes) so a copied,
    /// renamed, or re-imported file is recognized as the same image. Legacy rows keep
    /// an empty hash; the V12 rebuild lists no such column, so this must follow it.
    private static func migrateProjectSchemaV14IfNeeded(_ connection: OpaquePointer) throws {
        // Idempotent on the column itself, not only on the migration row: a
        // rebuild that predates the column (V12 on a downgraded table) must not
        // strand a database that already recorded this version.
        let applied = try migrationApplied(
            connection,
            table: "project_schema_migrations",
            version: projectMediaContentHashSchemaVersion,
            context: "Project DB"
        )
        let hasColumn = try columnExists(connection, table: "media_items", column: "content_sha256", context: "Project DB")
        guard !(applied && hasColumn) else { return }

        try litScenesSQLiteExecute(connection, "BEGIN IMMEDIATE;", context: "Project DB")
        do {
            try ensureColumn(
                connection,
                table: "media_items",
                column: "content_sha256",
                definition: "content_sha256 TEXT NOT NULL DEFAULT ''",
                context: "Project DB"
            )
            try litScenesSQLiteExecute(
                connection,
                "CREATE INDEX IF NOT EXISTS media_items_project_content_sha_idx ON media_items(project_id, content_sha256);",
                context: "Project DB"
            )
            try insertMigration(
                connection,
                table: "project_schema_migrations",
                version: projectMediaContentHashSchemaVersion,
                context: "Project DB"
            )
            try runProjectIntegrityChecks(connection, context: "Project DB")
            try litScenesSQLiteExecute(connection, "COMMIT;", context: "Project DB")
        } catch {
            try? litScenesSQLiteExecute(connection, "ROLLBACK;", context: "Project DB")
            throw error
        }
    }

    private static func createCanonicalProjectDocumentSchemaV3(_ connection: OpaquePointer) throws {
        try litScenesSQLiteExecute(connection, """
        CREATE TABLE IF NOT EXISTS project_documents (
            project_id TEXT NOT NULL,
            document_type TEXT NOT NULL,
            document_id TEXT NOT NULL,
            schema_version TEXT NOT NULL DEFAULT '',
            payload_json TEXT NOT NULL,
            content_fingerprint TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            record_revision INTEGER NOT NULL DEFAULT 1 CHECK(record_revision > 0),
            PRIMARY KEY(project_id, document_type, document_id),
            FOREIGN KEY(project_id) REFERENCES project_identity(project_id) ON DELETE CASCADE
        );
        """, context: "Project DB")
        try litScenesSQLiteExecute(
            connection,
            "CREATE INDEX IF NOT EXISTS project_documents_type_idx ON project_documents(project_id, document_type, updated_at);",
            context: "Project DB"
        )
    }

    private static func createGoalThemeSchemaV4(_ connection: OpaquePointer) throws {
        let statements = [
            """
            CREATE TABLE IF NOT EXISTS project_goal_state (
                project_id TEXT PRIMARY KEY,
                schema_version TEXT NOT NULL,
                active_version_id TEXT NOT NULL DEFAULT '',
                updated_at TEXT NOT NULL,
                record_revision INTEGER NOT NULL DEFAULT 1 CHECK(record_revision > 0),
                FOREIGN KEY(project_id) REFERENCES project_identity(project_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS project_goal_messages (
                message_id TEXT PRIMARY KEY,
                project_id TEXT NOT NULL,
                message_order INTEGER NOT NULL CHECK(message_order >= 0),
                role TEXT NOT NULL CHECK(role IN ('user', 'assistant')),
                text TEXT NOT NULL,
                created_at TEXT NOT NULL,
                FOREIGN KEY(project_id) REFERENCES project_goal_state(project_id) ON DELETE CASCADE,
                UNIQUE(project_id, message_order)
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS project_goal_message_media (
                message_id TEXT NOT NULL,
                media_order INTEGER NOT NULL CHECK(media_order >= 0),
                media_id TEXT NOT NULL,
                PRIMARY KEY(message_id, media_order),
                FOREIGN KEY(message_id) REFERENCES project_goal_messages(message_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS project_goal_versions (
                version_id TEXT PRIMARY KEY,
                project_id TEXT NOT NULL,
                version_order INTEGER NOT NULL CHECK(version_order >= 0),
                turn_index INTEGER NOT NULL CHECK(turn_index >= 0),
                content_type TEXT,
                goal TEXT NOT NULL DEFAULT '',
                audience TEXT NOT NULL DEFAULT '',
                desired_response TEXT NOT NULL DEFAULT '',
                viewer_experience TEXT NOT NULL DEFAULT '',
                moodboard_articulation TEXT NOT NULL DEFAULT '',
                theme_seed_summary TEXT NOT NULL DEFAULT '',
                change_summary TEXT NOT NULL DEFAULT '',
                model TEXT NOT NULL DEFAULT '',
                created_at TEXT NOT NULL,
                content_fingerprint TEXT NOT NULL DEFAULT '',
                FOREIGN KEY(project_id) REFERENCES project_goal_state(project_id) ON DELETE CASCADE,
                UNIQUE(project_id, version_order)
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS project_goal_brief_list_items (
                version_id TEXT NOT NULL,
                list_kind TEXT NOT NULL,
                item_order INTEGER NOT NULL CHECK(item_order >= 0),
                value TEXT NOT NULL,
                PRIMARY KEY(version_id, list_kind, item_order),
                FOREIGN KEY(version_id) REFERENCES project_goal_versions(version_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS project_goal_required_entities (
                version_id TEXT NOT NULL,
                entity_order INTEGER NOT NULL CHECK(entity_order >= 0),
                name TEXT NOT NULL,
                role TEXT NOT NULL DEFAULT '',
                required INTEGER NOT NULL DEFAULT 1 CHECK(required IN (0, 1)),
                PRIMARY KEY(version_id, entity_order),
                FOREIGN KEY(version_id) REFERENCES project_goal_versions(version_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS project_goal_meaning_node_refs (
                version_id TEXT NOT NULL,
                ref_order INTEGER NOT NULL CHECK(ref_order >= 0),
                slug TEXT NOT NULL,
                kind TEXT NOT NULL,
                name TEXT NOT NULL,
                role TEXT NOT NULL,
                source TEXT NOT NULL,
                evidence TEXT NOT NULL DEFAULT '',
                PRIMARY KEY(version_id, ref_order),
                FOREIGN KEY(version_id) REFERENCES project_goal_versions(version_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS project_goal_aesthetic_term_refs (
                version_id TEXT NOT NULL,
                ref_order INTEGER NOT NULL CHECK(ref_order >= 0),
                facet_type TEXT NOT NULL,
                slug TEXT NOT NULL,
                display_name TEXT NOT NULL,
                role TEXT NOT NULL,
                source TEXT NOT NULL,
                evidence TEXT NOT NULL DEFAULT '',
                PRIMARY KEY(version_id, ref_order),
                FOREIGN KEY(version_id) REFERENCES project_goal_versions(version_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS project_goal_style_term_refs (
                version_id TEXT NOT NULL,
                ref_order INTEGER NOT NULL CHECK(ref_order >= 0),
                term TEXT NOT NULL,
                kind TEXT NOT NULL,
                weight REAL NOT NULL DEFAULT 1,
                rationale TEXT NOT NULL DEFAULT '',
                PRIMARY KEY(version_id, ref_order),
                FOREIGN KEY(version_id) REFERENCES project_goal_versions(version_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS project_goal_validation_warnings (
                version_id TEXT NOT NULL,
                warning_order INTEGER NOT NULL CHECK(warning_order >= 0),
                warning TEXT NOT NULL,
                PRIMARY KEY(version_id, warning_order),
                FOREIGN KEY(version_id) REFERENCES project_goal_versions(version_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS project_theme_state (
                project_id TEXT PRIMARY KEY,
                schema_version TEXT NOT NULL,
                active_version_id TEXT NOT NULL DEFAULT '',
                updated_at TEXT NOT NULL,
                record_revision INTEGER NOT NULL DEFAULT 1 CHECK(record_revision > 0),
                FOREIGN KEY(project_id) REFERENCES project_identity(project_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS project_theme_messages (
                message_id TEXT PRIMARY KEY,
                project_id TEXT NOT NULL,
                message_order INTEGER NOT NULL CHECK(message_order >= 0),
                role TEXT NOT NULL CHECK(role IN ('user', 'assistant')),
                text TEXT NOT NULL,
                target_scratch_id TEXT,
                target_theme_id TEXT,
                created_at TEXT NOT NULL,
                FOREIGN KEY(project_id) REFERENCES project_theme_state(project_id) ON DELETE CASCADE,
                UNIQUE(project_id, message_order)
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS project_theme_message_media (
                message_id TEXT NOT NULL,
                media_order INTEGER NOT NULL CHECK(media_order >= 0),
                media_id TEXT NOT NULL,
                PRIMARY KEY(message_id, media_order),
                FOREIGN KEY(message_id) REFERENCES project_theme_messages(message_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS project_theme_versions (
                version_id TEXT PRIMARY KEY,
                project_id TEXT NOT NULL,
                version_order INTEGER NOT NULL CHECK(version_order >= 0),
                turn_index INTEGER NOT NULL CHECK(turn_index >= 0),
                selected_theme_id TEXT,
                selected_scratch_id TEXT,
                change_summary TEXT NOT NULL DEFAULT '',
                model TEXT NOT NULL DEFAULT '',
                created_at TEXT NOT NULL,
                content_fingerprint TEXT NOT NULL DEFAULT '',
                FOREIGN KEY(project_id) REFERENCES project_theme_state(project_id) ON DELETE CASCADE,
                UNIQUE(project_id, version_order)
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS project_theme_version_themes (
                version_id TEXT NOT NULL,
                theme_id TEXT NOT NULL,
                theme_order INTEGER NOT NULL CHECK(theme_order >= 0),
                status TEXT NOT NULL DEFAULT '',
                enabled INTEGER NOT NULL DEFAULT 0 CHECK(enabled IN (0, 1)),
                title TEXT NOT NULL DEFAULT '',
                claim TEXT NOT NULL DEFAULT '',
                visual_summary TEXT NOT NULL DEFAULT '',
                generation_run_id TEXT NOT NULL DEFAULT '',
                generation_phase TEXT NOT NULL DEFAULT '',
                generation_error TEXT NOT NULL DEFAULT '',
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                payload_json TEXT NOT NULL,
                PRIMARY KEY(version_id, theme_id),
                FOREIGN KEY(version_id) REFERENCES project_theme_versions(version_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS project_theme_terms (
                version_id TEXT NOT NULL,
                theme_id TEXT NOT NULL,
                term_kind TEXT NOT NULL,
                item_order INTEGER NOT NULL CHECK(item_order >= 0),
                value TEXT NOT NULL,
                PRIMARY KEY(version_id, theme_id, term_kind, item_order),
                FOREIGN KEY(version_id, theme_id) REFERENCES project_theme_version_themes(version_id, theme_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS project_theme_style_ingredients (
                version_id TEXT NOT NULL,
                theme_id TEXT NOT NULL,
                ingredient_id TEXT NOT NULL,
                ingredient_order INTEGER NOT NULL CHECK(ingredient_order >= 0),
                enabled INTEGER NOT NULL DEFAULT 1 CHECK(enabled IN (0, 1)),
                title TEXT NOT NULL DEFAULT '',
                role TEXT NOT NULL DEFAULT '',
                narrative_use TEXT NOT NULL DEFAULT '',
                presentation_use TEXT NOT NULL DEFAULT '',
                notes TEXT NOT NULL DEFAULT '',
                source_recipe_id TEXT,
                source_recipe_version TEXT,
                updated_at TEXT NOT NULL,
                PRIMARY KEY(version_id, theme_id, ingredient_id),
                FOREIGN KEY(version_id, theme_id) REFERENCES project_theme_version_themes(version_id, theme_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS project_theme_ingredient_terms (
                version_id TEXT NOT NULL,
                theme_id TEXT NOT NULL,
                ingredient_id TEXT NOT NULL,
                term_kind TEXT NOT NULL,
                item_order INTEGER NOT NULL CHECK(item_order >= 0),
                value TEXT NOT NULL,
                PRIMARY KEY(version_id, theme_id, ingredient_id, term_kind, item_order),
                FOREIGN KEY(version_id, theme_id, ingredient_id) REFERENCES project_theme_style_ingredients(version_id, theme_id, ingredient_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS project_theme_hero_images (
                version_id TEXT NOT NULL,
                theme_id TEXT NOT NULL,
                image_order INTEGER NOT NULL CHECK(image_order >= 0),
                image_index INTEGER NOT NULL DEFAULT 0,
                provider TEXT NOT NULL DEFAULT '',
                status TEXT NOT NULL DEFAULT '',
                image_path TEXT NOT NULL DEFAULT '',
                prompt TEXT NOT NULL DEFAULT '',
                generated_at TEXT NOT NULL DEFAULT '',
                updated_at TEXT NOT NULL DEFAULT '',
                payload_json TEXT NOT NULL,
                PRIMARY KEY(version_id, theme_id, image_order),
                FOREIGN KEY(version_id, theme_id) REFERENCES project_theme_version_themes(version_id, theme_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS project_theme_scratch_drafts (
                version_id TEXT NOT NULL,
                scratch_id TEXT NOT NULL,
                scratch_order INTEGER NOT NULL CHECK(scratch_order >= 0),
                title TEXT NOT NULL DEFAULT '',
                claim TEXT NOT NULL DEFAULT '',
                visual_summary TEXT NOT NULL DEFAULT '',
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                payload_json TEXT NOT NULL,
                PRIMARY KEY(version_id, scratch_id),
                FOREIGN KEY(version_id) REFERENCES project_theme_versions(version_id) ON DELETE CASCADE
            );
            """
        ]
        for statement in statements {
            try litScenesSQLiteExecute(connection, statement, context: "Project DB")
        }

        let indexes = [
            "CREATE INDEX IF NOT EXISTS project_goal_messages_project_idx ON project_goal_messages(project_id, message_order);",
            "CREATE INDEX IF NOT EXISTS project_goal_versions_project_idx ON project_goal_versions(project_id, version_order);",
            "CREATE INDEX IF NOT EXISTS project_theme_messages_project_idx ON project_theme_messages(project_id, message_order);",
            "CREATE INDEX IF NOT EXISTS project_theme_versions_project_idx ON project_theme_versions(project_id, version_order);",
            "CREATE INDEX IF NOT EXISTS project_theme_version_themes_version_idx ON project_theme_version_themes(version_id, theme_order);",
            "CREATE INDEX IF NOT EXISTS project_theme_scratch_drafts_version_idx ON project_theme_scratch_drafts(version_id, scratch_order);"
        ]
        for index in indexes {
            try litScenesSQLiteExecute(connection, index, context: "Project DB")
        }
    }

    private static func createProjectMediaSchemaV5(_ connection: OpaquePointer) throws {
        let statements = [
            """
            CREATE TABLE IF NOT EXISTS project_media_state (
                project_id TEXT PRIMARY KEY,
                schema_version TEXT NOT NULL,
                inventory_scanned_at TEXT NOT NULL DEFAULT '',
                observations_generated_at TEXT NOT NULL DEFAULT '',
                updated_at TEXT NOT NULL,
                record_revision INTEGER NOT NULL DEFAULT 1 CHECK(record_revision > 0),
                FOREIGN KEY(project_id) REFERENCES project_identity(project_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS media_sources (
                project_id TEXT NOT NULL,
                source_id TEXT NOT NULL,
                source_order INTEGER NOT NULL DEFAULT 0 CHECK(source_order >= 0),
                display_name TEXT NOT NULL,
                path TEXT NOT NULL,
                source_kind TEXT NOT NULL DEFAULT '',
                bookmark_data_base64 TEXT NOT NULL DEFAULT '',
                storage_mode TEXT NOT NULL DEFAULT 'linked' CHECK(storage_mode IN ('managed', 'linked')),
                original_path TEXT NOT NULL DEFAULT '',
                original_bookmark_data_base64 TEXT NOT NULL DEFAULT '',
                added_at TEXT NOT NULL DEFAULT '',
                last_scanned_at TEXT,
                record_revision INTEGER NOT NULL DEFAULT 1 CHECK(record_revision > 0),
                PRIMARY KEY(project_id, source_id),
                FOREIGN KEY(project_id) REFERENCES project_identity(project_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS media_items (
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
                content_sha256 TEXT NOT NULL DEFAULT '',
                PRIMARY KEY(project_id, media_id),
                FOREIGN KEY(project_id) REFERENCES project_identity(project_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS media_curation (
                project_id TEXT NOT NULL,
                media_id TEXT NOT NULL,
                rejected INTEGER NOT NULL DEFAULT 0 CHECK(rejected IN (0, 1)),
                notes TEXT NOT NULL DEFAULT '',
                updated_at TEXT NOT NULL,
                record_revision INTEGER NOT NULL DEFAULT 1 CHECK(record_revision > 0),
                PRIMARY KEY(project_id, media_id),
                FOREIGN KEY(project_id) REFERENCES project_identity(project_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS media_curation_tags (
                project_id TEXT NOT NULL,
                media_id TEXT NOT NULL,
                tag_order INTEGER NOT NULL CHECK(tag_order >= 0),
                tag TEXT NOT NULL,
                PRIMARY KEY(project_id, media_id, tag_order),
                FOREIGN KEY(project_id, media_id) REFERENCES media_curation(project_id, media_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS media_observations (
                project_id TEXT NOT NULL,
                media_id TEXT NOT NULL,
                schema_version TEXT NOT NULL DEFAULT '',
                frame_id TEXT NOT NULL DEFAULT '',
                source_path TEXT NOT NULL DEFAULT '',
                image_hash TEXT NOT NULL DEFAULT '',
                observation_provider TEXT NOT NULL DEFAULT '',
                model TEXT NOT NULL DEFAULT '',
                prompt_version TEXT NOT NULL DEFAULT '',
                created_at TEXT NOT NULL DEFAULT '',
                plain_caption TEXT NOT NULL DEFAULT '',
                literal_description TEXT NOT NULL DEFAULT '',
                people_visible INTEGER NOT NULL DEFAULT 0 CHECK(people_visible IN (0, 1)),
                people_count_estimate INTEGER,
                setting TEXT NOT NULL DEFAULT '',
                lighting TEXT NOT NULL DEFAULT '',
                media_role TEXT NOT NULL DEFAULT '',
                media_role_assessment_role TEXT NOT NULL DEFAULT '',
                media_role_assessment_why TEXT NOT NULL DEFAULT '',
                media_role_assessment_confidence REAL NOT NULL DEFAULT 0,
                source_kind_notes TEXT NOT NULL DEFAULT '',
                detail_pass_used INTEGER NOT NULL DEFAULT 0 CHECK(detail_pass_used IN (0, 1)),
                detail_pass_reason TEXT NOT NULL DEFAULT '',
                detail_observation_notes TEXT NOT NULL DEFAULT '',
                object_description_pass_used INTEGER NOT NULL DEFAULT 0 CHECK(object_description_pass_used IN (0, 1)),
                object_description_prompt_version TEXT NOT NULL DEFAULT '',
                source_image_path TEXT NOT NULL DEFAULT '',
                source_image_sha256 TEXT NOT NULL DEFAULT '',
                vision_input_kind TEXT NOT NULL DEFAULT '',
                vision_input_path TEXT NOT NULL DEFAULT '',
                vision_input_sha256 TEXT NOT NULL DEFAULT '',
                vision_input_width INTEGER NOT NULL DEFAULT 0,
                vision_input_height INTEGER NOT NULL DEFAULT 0,
                vision_input_bytes INTEGER NOT NULL DEFAULT 0,
                vision_thumbnail_profile TEXT NOT NULL DEFAULT '',
                fullres_vision_allowed INTEGER NOT NULL DEFAULT 0 CHECK(fullres_vision_allowed IN (0, 1)),
                thumbnail_policy_version TEXT NOT NULL DEFAULT '',
                detail_vision_input_kind TEXT NOT NULL DEFAULT '',
                detail_vision_input_path TEXT NOT NULL DEFAULT '',
                detail_vision_input_sha256 TEXT NOT NULL DEFAULT '',
                detail_vision_input_width INTEGER NOT NULL DEFAULT 0,
                detail_vision_input_height INTEGER NOT NULL DEFAULT 0,
                detail_vision_input_bytes INTEGER NOT NULL DEFAULT 0,
                detail_vision_thumbnail_profile TEXT NOT NULL DEFAULT '',
                event_type TEXT NOT NULL DEFAULT '',
                event_name_guess TEXT NOT NULL DEFAULT '',
                event_competition_or_program_guess TEXT NOT NULL DEFAULT '',
                event_why TEXT NOT NULL DEFAULT '',
                event_confidence REAL NOT NULL DEFAULT 0,
                human_review_needs_review INTEGER NOT NULL DEFAULT 0 CHECK(human_review_needs_review IN (0, 1)),
                human_review_reason TEXT NOT NULL DEFAULT '',
                human_review_suggested_question TEXT NOT NULL DEFAULT '',
                user_known_context TEXT NOT NULL DEFAULT '',
                user_preferred_media_role TEXT NOT NULL DEFAULT '',
                user_notes TEXT NOT NULL DEFAULT '',
                raw_payload_json TEXT NOT NULL DEFAULT '',
                content_fingerprint TEXT NOT NULL DEFAULT '',
                updated_at TEXT NOT NULL,
                record_revision INTEGER NOT NULL DEFAULT 1 CHECK(record_revision > 0),
                PRIMARY KEY(project_id, media_id),
                FOREIGN KEY(project_id) REFERENCES project_identity(project_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS media_observation_terms (
                project_id TEXT NOT NULL,
                media_id TEXT NOT NULL,
                term_kind TEXT NOT NULL,
                item_order INTEGER NOT NULL CHECK(item_order >= 0),
                value TEXT NOT NULL,
                PRIMARY KEY(project_id, media_id, term_kind, item_order),
                FOREIGN KEY(project_id, media_id) REFERENCES media_observations(project_id, media_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS media_observation_object_descriptions (
                project_id TEXT NOT NULL,
                media_id TEXT NOT NULL,
                item_order INTEGER NOT NULL CHECK(item_order >= 0),
                accurate_title TEXT NOT NULL DEFAULT '',
                thorough_description TEXT NOT NULL DEFAULT '',
                PRIMARY KEY(project_id, media_id, item_order),
                FOREIGN KEY(project_id, media_id) REFERENCES media_observations(project_id, media_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS media_observation_visible_text (
                project_id TEXT NOT NULL,
                media_id TEXT NOT NULL,
                item_order INTEGER NOT NULL CHECK(item_order >= 0),
                text TEXT NOT NULL DEFAULT '',
                where_seen TEXT NOT NULL DEFAULT '',
                confidence0_to1 REAL NOT NULL DEFAULT 0,
                PRIMARY KEY(project_id, media_id, item_order),
                FOREIGN KEY(project_id, media_id) REFERENCES media_observations(project_id, media_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS media_observation_domain_entities (
                project_id TEXT NOT NULL,
                media_id TEXT NOT NULL,
                entity_scope TEXT NOT NULL,
                item_order INTEGER NOT NULL CHECK(item_order >= 0),
                name TEXT NOT NULL DEFAULT '',
                kind TEXT NOT NULL DEFAULT '',
                visible_evidence TEXT NOT NULL DEFAULT '',
                confidence0_to1 REAL NOT NULL DEFAULT 0,
                PRIMARY KEY(project_id, media_id, entity_scope, item_order),
                FOREIGN KEY(project_id, media_id) REFERENCES media_observations(project_id, media_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS media_observation_flags_symbols (
                project_id TEXT NOT NULL,
                media_id TEXT NOT NULL,
                item_order INTEGER NOT NULL CHECK(item_order >= 0),
                name TEXT NOT NULL DEFAULT '',
                kind TEXT NOT NULL DEFAULT '',
                visible_evidence TEXT NOT NULL DEFAULT '',
                confidence0_to1 REAL NOT NULL DEFAULT 0,
                PRIMARY KEY(project_id, media_id, item_order),
                FOREIGN KEY(project_id, media_id) REFERENCES media_observations(project_id, media_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS media_observation_uncertainties (
                project_id TEXT NOT NULL,
                media_id TEXT NOT NULL,
                item_order INTEGER NOT NULL CHECK(item_order >= 0),
                field TEXT NOT NULL DEFAULT '',
                question TEXT NOT NULL DEFAULT '',
                why_uncertain TEXT NOT NULL DEFAULT '',
                PRIMARY KEY(project_id, media_id, item_order),
                FOREIGN KEY(project_id, media_id) REFERENCES media_observations(project_id, media_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS media_observation_user_context_tags (
                project_id TEXT NOT NULL,
                media_id TEXT NOT NULL,
                tag_order INTEGER NOT NULL CHECK(tag_order >= 0),
                tag TEXT NOT NULL,
                PRIMARY KEY(project_id, media_id, tag_order),
                FOREIGN KEY(project_id, media_id) REFERENCES media_observations(project_id, media_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS media_import_warnings (
                project_id TEXT NOT NULL,
                warning_order INTEGER NOT NULL CHECK(warning_order >= 0),
                warning TEXT NOT NULL,
                created_at TEXT NOT NULL,
                PRIMARY KEY(project_id, warning_order),
                FOREIGN KEY(project_id) REFERENCES project_identity(project_id) ON DELETE CASCADE
            );
            """
        ]
        for statement in statements {
            try litScenesSQLiteExecute(connection, statement, context: "Project DB")
        }

        let indexes = [
            "CREATE INDEX IF NOT EXISTS media_sources_project_order_idx ON media_sources(project_id, source_order);",
            "CREATE INDEX IF NOT EXISTS media_sources_project_path_idx ON media_sources(project_id, path);",
            "CREATE INDEX IF NOT EXISTS media_items_project_order_idx ON media_items(project_id, item_order);",
            "CREATE INDEX IF NOT EXISTS media_items_project_kind_idx ON media_items(project_id, kind);",
            "CREATE INDEX IF NOT EXISTS media_items_project_source_idx ON media_items(project_id, source_id);",
            "CREATE INDEX IF NOT EXISTS media_items_project_derivative_idx ON media_items(project_id, derivative_kind);",
            "CREATE INDEX IF NOT EXISTS media_items_project_source_media_idx ON media_items(project_id, source_media_id);",
            "CREATE INDEX IF NOT EXISTS media_items_project_content_sha_idx ON media_items(project_id, content_sha256);",
            "CREATE INDEX IF NOT EXISTS media_curation_project_rejected_idx ON media_curation(project_id, rejected);",
            "CREATE INDEX IF NOT EXISTS media_curation_tags_project_tag_idx ON media_curation_tags(project_id, tag);",
            "CREATE INDEX IF NOT EXISTS media_observations_project_created_idx ON media_observations(project_id, created_at);",
            "CREATE INDEX IF NOT EXISTS media_observations_project_hash_idx ON media_observations(project_id, image_hash);",
            "CREATE INDEX IF NOT EXISTS media_observations_project_vision_hash_idx ON media_observations(project_id, vision_input_sha256);",
            "CREATE INDEX IF NOT EXISTS media_observation_terms_project_kind_value_idx ON media_observation_terms(project_id, term_kind, value);",
            "CREATE INDEX IF NOT EXISTS media_observation_domain_entities_project_name_idx ON media_observation_domain_entities(project_id, entity_scope, name);",
            "CREATE INDEX IF NOT EXISTS media_import_warnings_project_idx ON media_import_warnings(project_id, warning_order);"
        ]
        for index in indexes {
            try litScenesSQLiteExecute(connection, index, context: "Project DB")
        }
    }

    private static func createProjectLensVersioningSchemaV6(_ connection: OpaquePointer) throws {
        let statements = [
            """
            CREATE TABLE IF NOT EXISTS project_theme_color_swatches (
                version_id TEXT NOT NULL,
                theme_id TEXT NOT NULL,
                swatch_order INTEGER NOT NULL CHECK(swatch_order >= 0),
                name TEXT NOT NULL DEFAULT '',
                hex TEXT NOT NULL DEFAULT '',
                role TEXT NOT NULL DEFAULT '',
                note TEXT NOT NULL DEFAULT '',
                PRIMARY KEY(version_id, theme_id, swatch_order),
                FOREIGN KEY(version_id, theme_id) REFERENCES project_theme_version_themes(version_id, theme_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS project_theme_edit_messages (
                message_id TEXT PRIMARY KEY,
                project_id TEXT NOT NULL,
                theme_id TEXT NOT NULL,
                message_order INTEGER NOT NULL CHECK(message_order >= 0),
                role TEXT NOT NULL CHECK(role IN ('user', 'assistant')),
                text TEXT NOT NULL,
                created_at TEXT NOT NULL,
                FOREIGN KEY(project_id) REFERENCES project_theme_state(project_id) ON DELETE CASCADE,
                UNIQUE(project_id, theme_id, message_order)
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS project_theme_edit_message_media (
                message_id TEXT NOT NULL,
                media_order INTEGER NOT NULL CHECK(media_order >= 0),
                media_id TEXT NOT NULL,
                PRIMARY KEY(message_id, media_order),
                FOREIGN KEY(message_id) REFERENCES project_theme_edit_messages(message_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS project_theme_body_versions (
                version_id TEXT PRIMARY KEY,
                project_id TEXT NOT NULL,
                theme_id TEXT NOT NULL,
                version_order INTEGER NOT NULL CHECK(version_order >= 0),
                source_theme_set_version_id TEXT NOT NULL,
                turn_index INTEGER NOT NULL CHECK(turn_index >= 0),
                change_summary TEXT NOT NULL DEFAULT '',
                model TEXT NOT NULL DEFAULT '',
                created_at TEXT NOT NULL,
                content_fingerprint TEXT NOT NULL DEFAULT '',
                is_active INTEGER NOT NULL DEFAULT 0 CHECK(is_active IN (0, 1)),
                FOREIGN KEY(project_id) REFERENCES project_theme_state(project_id) ON DELETE CASCADE,
                FOREIGN KEY(source_theme_set_version_id, theme_id) REFERENCES project_theme_version_themes(version_id, theme_id) ON DELETE CASCADE,
                UNIQUE(project_id, theme_id, version_order)
            );
            """
        ]
        for statement in statements {
            try litScenesSQLiteExecute(connection, statement, context: "Project DB")
        }

        let indexes = [
            "CREATE INDEX IF NOT EXISTS project_theme_color_swatches_theme_idx ON project_theme_color_swatches(version_id, theme_id, swatch_order);",
            "CREATE INDEX IF NOT EXISTS project_theme_edit_messages_project_theme_idx ON project_theme_edit_messages(project_id, theme_id, message_order);",
            "CREATE INDEX IF NOT EXISTS project_theme_body_versions_project_theme_idx ON project_theme_body_versions(project_id, theme_id, version_order);",
            "CREATE INDEX IF NOT EXISTS project_theme_body_versions_active_idx ON project_theme_body_versions(project_id, theme_id, is_active);"
        ]
        for index in indexes {
            try litScenesSQLiteExecute(connection, index, context: "Project DB")
        }
    }

    private static func createProjectLensSchemaV7(_ connection: OpaquePointer) throws {
        try ensureColumn(
            connection,
            table: "project_goal_versions",
            column: "moodboard_articulation",
            definition: "moodboard_articulation TEXT NOT NULL DEFAULT ''",
            context: "Project DB"
        )
        try ensureColumn(
            connection,
            table: "project_goal_versions",
            column: "lens_seed_summary",
            definition: "lens_seed_summary TEXT NOT NULL DEFAULT ''",
            context: "Project DB"
        )
        try ensureColumn(
            connection,
            table: "project_stories",
            column: "lens_ids_json",
            definition: "lens_ids_json TEXT NOT NULL DEFAULT '[]'",
            context: "Project DB"
        )

        let statements = [
            """
            CREATE TABLE IF NOT EXISTS project_lens_state (
                project_id TEXT PRIMARY KEY,
                schema_version TEXT NOT NULL,
                active_version_id TEXT NOT NULL DEFAULT '',
                updated_at TEXT NOT NULL,
                record_revision INTEGER NOT NULL DEFAULT 1 CHECK(record_revision > 0),
                FOREIGN KEY(project_id) REFERENCES project_identity(project_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS project_lens_messages (
                message_id TEXT PRIMARY KEY,
                project_id TEXT NOT NULL,
                message_order INTEGER NOT NULL CHECK(message_order >= 0),
                role TEXT NOT NULL CHECK(role IN ('user', 'assistant')),
                text TEXT NOT NULL,
                target_scratch_id TEXT,
                target_lens_id TEXT,
                created_at TEXT NOT NULL,
                FOREIGN KEY(project_id) REFERENCES project_lens_state(project_id) ON DELETE CASCADE,
                UNIQUE(project_id, message_order)
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS project_lens_message_media (
                message_id TEXT NOT NULL,
                media_order INTEGER NOT NULL CHECK(media_order >= 0),
                media_id TEXT NOT NULL,
                PRIMARY KEY(message_id, media_order),
                FOREIGN KEY(message_id) REFERENCES project_lens_messages(message_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS project_lens_versions (
                version_id TEXT PRIMARY KEY,
                project_id TEXT NOT NULL,
                version_order INTEGER NOT NULL CHECK(version_order >= 0),
                turn_index INTEGER NOT NULL CHECK(turn_index >= 0),
                selected_lens_id TEXT,
                selected_scratch_id TEXT,
                change_summary TEXT NOT NULL DEFAULT '',
                model TEXT NOT NULL DEFAULT '',
                created_at TEXT NOT NULL,
                content_fingerprint TEXT NOT NULL DEFAULT '',
                FOREIGN KEY(project_id) REFERENCES project_lens_state(project_id) ON DELETE CASCADE,
                UNIQUE(project_id, version_order)
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS project_lens_version_lenses (
                version_id TEXT NOT NULL,
                lens_id TEXT NOT NULL,
                lens_order INTEGER NOT NULL CHECK(lens_order >= 0),
                status TEXT NOT NULL DEFAULT '',
                enabled INTEGER NOT NULL DEFAULT 0 CHECK(enabled IN (0, 1)),
                title TEXT NOT NULL DEFAULT '',
                claim TEXT NOT NULL DEFAULT '',
                visual_summary TEXT NOT NULL DEFAULT '',
                generation_run_id TEXT NOT NULL DEFAULT '',
                generation_phase TEXT NOT NULL DEFAULT '',
                generation_error TEXT NOT NULL DEFAULT '',
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                payload_json TEXT NOT NULL,
                PRIMARY KEY(version_id, lens_id),
                FOREIGN KEY(version_id) REFERENCES project_lens_versions(version_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS project_lens_terms (
                version_id TEXT NOT NULL,
                lens_id TEXT NOT NULL,
                term_kind TEXT NOT NULL,
                item_order INTEGER NOT NULL CHECK(item_order >= 0),
                value TEXT NOT NULL,
                PRIMARY KEY(version_id, lens_id, term_kind, item_order),
                FOREIGN KEY(version_id, lens_id) REFERENCES project_lens_version_lenses(version_id, lens_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS project_lens_style_ingredients (
                version_id TEXT NOT NULL,
                lens_id TEXT NOT NULL,
                ingredient_id TEXT NOT NULL,
                ingredient_order INTEGER NOT NULL CHECK(ingredient_order >= 0),
                enabled INTEGER NOT NULL DEFAULT 1 CHECK(enabled IN (0, 1)),
                title TEXT NOT NULL DEFAULT '',
                role TEXT NOT NULL DEFAULT '',
                narrative_use TEXT NOT NULL DEFAULT '',
                presentation_use TEXT NOT NULL DEFAULT '',
                notes TEXT NOT NULL DEFAULT '',
                source_recipe_id TEXT,
                source_recipe_version TEXT,
                updated_at TEXT NOT NULL,
                PRIMARY KEY(version_id, lens_id, ingredient_id),
                FOREIGN KEY(version_id, lens_id) REFERENCES project_lens_version_lenses(version_id, lens_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS project_lens_ingredient_terms (
                version_id TEXT NOT NULL,
                lens_id TEXT NOT NULL,
                ingredient_id TEXT NOT NULL,
                term_kind TEXT NOT NULL,
                item_order INTEGER NOT NULL CHECK(item_order >= 0),
                value TEXT NOT NULL,
                PRIMARY KEY(version_id, lens_id, ingredient_id, term_kind, item_order),
                FOREIGN KEY(version_id, lens_id, ingredient_id) REFERENCES project_lens_style_ingredients(version_id, lens_id, ingredient_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS project_lens_hero_images (
                version_id TEXT NOT NULL,
                lens_id TEXT NOT NULL,
                image_order INTEGER NOT NULL CHECK(image_order >= 0),
                image_index INTEGER NOT NULL DEFAULT 0,
                provider TEXT NOT NULL DEFAULT '',
                status TEXT NOT NULL DEFAULT '',
                image_path TEXT NOT NULL DEFAULT '',
                prompt TEXT NOT NULL DEFAULT '',
                generated_at TEXT NOT NULL DEFAULT '',
                updated_at TEXT NOT NULL DEFAULT '',
                render_version_id TEXT NOT NULL DEFAULT '',
                render_target_id TEXT NOT NULL DEFAULT '',
                render_stack_fingerprint TEXT NOT NULL DEFAULT '',
                render_version_group_id TEXT NOT NULL DEFAULT '',
                version_number INTEGER NOT NULL DEFAULT 0,
                seed TEXT NOT NULL DEFAULT '',
                final_prompt_fingerprint TEXT NOT NULL DEFAULT '',
                render_params_fingerprint TEXT NOT NULL DEFAULT '',
                is_active_render_version INTEGER NOT NULL DEFAULT 0 CHECK(is_active_render_version IN (0, 1)),
                payload_json TEXT NOT NULL,
                PRIMARY KEY(version_id, lens_id, image_order),
                FOREIGN KEY(version_id, lens_id) REFERENCES project_lens_version_lenses(version_id, lens_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS project_lens_scratch_drafts (
                version_id TEXT NOT NULL,
                scratch_id TEXT NOT NULL,
                scratch_order INTEGER NOT NULL CHECK(scratch_order >= 0),
                title TEXT NOT NULL DEFAULT '',
                claim TEXT NOT NULL DEFAULT '',
                visual_summary TEXT NOT NULL DEFAULT '',
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                payload_json TEXT NOT NULL,
                PRIMARY KEY(version_id, scratch_id),
                FOREIGN KEY(version_id) REFERENCES project_lens_versions(version_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS project_lens_color_swatches (
                version_id TEXT NOT NULL,
                lens_id TEXT NOT NULL,
                swatch_order INTEGER NOT NULL CHECK(swatch_order >= 0),
                name TEXT NOT NULL DEFAULT '',
                hex TEXT NOT NULL DEFAULT '',
                role TEXT NOT NULL DEFAULT '',
                note TEXT NOT NULL DEFAULT '',
                PRIMARY KEY(version_id, lens_id, swatch_order),
                FOREIGN KEY(version_id, lens_id) REFERENCES project_lens_version_lenses(version_id, lens_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS project_lens_edit_messages (
                message_id TEXT PRIMARY KEY,
                project_id TEXT NOT NULL,
                lens_id TEXT NOT NULL,
                message_order INTEGER NOT NULL CHECK(message_order >= 0),
                role TEXT NOT NULL CHECK(role IN ('user', 'assistant')),
                text TEXT NOT NULL,
                created_at TEXT NOT NULL,
                FOREIGN KEY(project_id) REFERENCES project_lens_state(project_id) ON DELETE CASCADE,
                UNIQUE(project_id, lens_id, message_order)
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS project_lens_edit_message_media (
                message_id TEXT NOT NULL,
                media_order INTEGER NOT NULL CHECK(media_order >= 0),
                media_id TEXT NOT NULL,
                PRIMARY KEY(message_id, media_order),
                FOREIGN KEY(message_id) REFERENCES project_lens_edit_messages(message_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS project_lens_body_versions (
                version_id TEXT PRIMARY KEY,
                project_id TEXT NOT NULL,
                lens_id TEXT NOT NULL,
                version_order INTEGER NOT NULL CHECK(version_order >= 0),
                source_lens_set_version_id TEXT NOT NULL,
                turn_index INTEGER NOT NULL CHECK(turn_index >= 0),
                change_summary TEXT NOT NULL DEFAULT '',
                model TEXT NOT NULL DEFAULT '',
                created_at TEXT NOT NULL,
                content_fingerprint TEXT NOT NULL DEFAULT '',
                is_active INTEGER NOT NULL DEFAULT 0 CHECK(is_active IN (0, 1)),
                FOREIGN KEY(project_id) REFERENCES project_lens_state(project_id) ON DELETE CASCADE,
                FOREIGN KEY(source_lens_set_version_id, lens_id) REFERENCES project_lens_version_lenses(version_id, lens_id) ON DELETE CASCADE,
                UNIQUE(project_id, lens_id, version_order)
            );
            """
        ]
        for statement in statements {
            try litScenesSQLiteExecute(connection, statement, context: "Project DB")
        }

        let indexes = [
            "CREATE INDEX IF NOT EXISTS project_lens_messages_project_idx ON project_lens_messages(project_id, message_order);",
            "CREATE INDEX IF NOT EXISTS project_lens_versions_project_idx ON project_lens_versions(project_id, version_order);",
            "CREATE INDEX IF NOT EXISTS project_lens_version_lenses_version_idx ON project_lens_version_lenses(version_id, lens_order);",
            "CREATE INDEX IF NOT EXISTS project_lens_scratch_drafts_version_idx ON project_lens_scratch_drafts(version_id, scratch_order);",
            "CREATE INDEX IF NOT EXISTS project_lens_hero_images_render_group_idx ON project_lens_hero_images(version_id, lens_id, render_version_group_id, version_number);",
            "CREATE INDEX IF NOT EXISTS project_lens_hero_images_render_target_stack_idx ON project_lens_hero_images(version_id, lens_id, render_target_id, render_stack_fingerprint);",
            "CREATE INDEX IF NOT EXISTS project_lens_hero_images_active_render_idx ON project_lens_hero_images(version_id, lens_id, render_version_group_id, is_active_render_version);",
            "CREATE INDEX IF NOT EXISTS project_lens_color_swatches_lens_idx ON project_lens_color_swatches(version_id, lens_id, swatch_order);",
            "CREATE INDEX IF NOT EXISTS project_lens_edit_messages_project_lens_idx ON project_lens_edit_messages(project_id, lens_id, message_order);",
            "CREATE INDEX IF NOT EXISTS project_lens_body_versions_project_lens_idx ON project_lens_body_versions(project_id, lens_id, version_order);",
            "CREATE INDEX IF NOT EXISTS project_lens_body_versions_active_idx ON project_lens_body_versions(project_id, lens_id, is_active);"
        ]
        for index in indexes {
            try litScenesSQLiteExecute(connection, index, context: "Project DB")
        }
    }

    private static func backfillProjectLensSchemaV7(_ connection: OpaquePointer) throws {
        try litScenesSQLiteExecute(
            connection,
            "UPDATE project_goal_versions SET lens_seed_summary = theme_seed_summary WHERE lens_seed_summary = '' AND theme_seed_summary != '';",
            context: "Project DB"
        )
        if try columnExists(connection, table: "project_stories", column: "theme_ids_json", context: "Project DB") {
            try litScenesSQLiteExecute(
                connection,
                "UPDATE project_stories SET lens_ids_json = theme_ids_json WHERE lens_ids_json = '[]' AND theme_ids_json != '[]';",
                context: "Project DB"
            )
        }
        try litScenesSQLiteExecute(
            connection,
            "UPDATE project_goal_state SET schema_version = 'litscenes.project_goal.v0.3' WHERE schema_version = 'litscenes.project_goal.v0.2';",
            context: "Project DB"
        )
        try litScenesSQLiteExecute(
            connection,
            """
            INSERT OR IGNORE INTO project_goal_brief_list_items (version_id, list_kind, item_order, value)
            SELECT version_id, 'lens_seed_terms', item_order, value
            FROM project_goal_brief_list_items
            WHERE list_kind = 'theme_seed_terms';
            """,
            context: "Project DB"
        )

        let lensPayload = legacyThemePayloadToLensSQL("payload_json")
        try litScenesSQLiteExecute(connection, """
        INSERT OR IGNORE INTO project_lens_state (
            project_id, schema_version, active_version_id, updated_at, record_revision
        )
        SELECT project_id, replace(schema_version, 'project_theme_set', 'project_lens_set'),
               active_version_id, updated_at, record_revision
        FROM project_theme_state;
        """, context: "Project DB")
        try litScenesSQLiteExecute(connection, """
        INSERT OR IGNORE INTO project_lens_messages (
            message_id, project_id, message_order, role, text, target_scratch_id, target_lens_id, created_at
        )
        SELECT message_id, project_id, message_order, role, text, target_scratch_id, target_theme_id, created_at
        FROM project_theme_messages;
        """, context: "Project DB")
        try litScenesSQLiteExecute(connection, """
        INSERT OR IGNORE INTO project_lens_message_media (message_id, media_order, media_id)
        SELECT message_id, media_order, media_id FROM project_theme_message_media;
        """, context: "Project DB")
        try litScenesSQLiteExecute(connection, """
        INSERT OR IGNORE INTO project_lens_versions (
            version_id, project_id, version_order, turn_index, selected_lens_id, selected_scratch_id,
            change_summary, model, created_at, content_fingerprint
        )
        SELECT version_id, project_id, version_order, turn_index, selected_theme_id, selected_scratch_id,
               change_summary, model, created_at, content_fingerprint
        FROM project_theme_versions;
        """, context: "Project DB")
        try litScenesSQLiteExecute(connection, """
        INSERT OR IGNORE INTO project_lens_version_lenses (
            version_id, lens_id, lens_order, status, enabled, title, claim, visual_summary,
            generation_run_id, generation_phase, generation_error, created_at, updated_at, payload_json
        )
        SELECT version_id, theme_id, theme_order, status, enabled, title, claim, visual_summary,
               generation_run_id, generation_phase, generation_error, created_at, updated_at, \(lensPayload)
        FROM project_theme_version_themes;
        """, context: "Project DB")
        try litScenesSQLiteExecute(connection, """
        INSERT OR IGNORE INTO project_lens_terms (version_id, lens_id, term_kind, item_order, value)
        SELECT version_id, theme_id, term_kind, item_order, value FROM project_theme_terms;
        """, context: "Project DB")
        try litScenesSQLiteExecute(connection, """
        INSERT OR IGNORE INTO project_lens_style_ingredients (
            version_id, lens_id, ingredient_id, ingredient_order, enabled, title, role,
            narrative_use, presentation_use, notes, source_recipe_id, source_recipe_version, updated_at
        )
        SELECT version_id, theme_id, ingredient_id, ingredient_order, enabled, title, role,
               narrative_use, presentation_use, notes, source_recipe_id, source_recipe_version, updated_at
        FROM project_theme_style_ingredients;
        """, context: "Project DB")
        try litScenesSQLiteExecute(connection, """
        INSERT OR IGNORE INTO project_lens_ingredient_terms (
            version_id, lens_id, ingredient_id, term_kind, item_order, value
        )
        SELECT version_id, theme_id, ingredient_id, term_kind, item_order, value
        FROM project_theme_ingredient_terms;
        """, context: "Project DB")
        try litScenesSQLiteExecute(connection, """
        INSERT OR IGNORE INTO project_lens_hero_images (
            version_id, lens_id, image_order, image_index, provider, status, image_path,
            prompt, generated_at, updated_at, payload_json
        )
        SELECT version_id, theme_id, image_order, image_index, provider, status, image_path,
               prompt, generated_at, updated_at, \(lensPayload)
        FROM project_theme_hero_images;
        """, context: "Project DB")
        try litScenesSQLiteExecute(connection, """
        INSERT OR IGNORE INTO project_lens_scratch_drafts (
            version_id, scratch_id, scratch_order, title, claim, visual_summary, created_at, updated_at, payload_json
        )
        SELECT version_id, scratch_id, scratch_order, title, claim, visual_summary, created_at, updated_at, \(lensPayload)
        FROM project_theme_scratch_drafts;
        """, context: "Project DB")
        try litScenesSQLiteExecute(connection, """
        INSERT OR IGNORE INTO project_lens_color_swatches (
            version_id, lens_id, swatch_order, name, hex, role, note
        )
        SELECT version_id, theme_id, swatch_order, name, hex, role, note
        FROM project_theme_color_swatches;
        """, context: "Project DB")
        try litScenesSQLiteExecute(connection, """
        INSERT OR IGNORE INTO project_lens_edit_messages (
            message_id, project_id, lens_id, message_order, role, text, created_at
        )
        SELECT message_id, project_id, theme_id, message_order, role, text, created_at
        FROM project_theme_edit_messages;
        """, context: "Project DB")
        try litScenesSQLiteExecute(connection, """
        INSERT OR IGNORE INTO project_lens_edit_message_media (message_id, media_order, media_id)
        SELECT message_id, media_order, media_id FROM project_theme_edit_message_media;
        """, context: "Project DB")
        try litScenesSQLiteExecute(connection, """
        INSERT OR IGNORE INTO project_lens_body_versions (
            version_id, project_id, lens_id, version_order, source_lens_set_version_id,
            turn_index, change_summary, model, created_at, content_fingerprint, is_active
        )
        SELECT version_id, project_id, theme_id, version_order, source_theme_set_version_id,
               turn_index, change_summary, model, created_at, content_fingerprint, is_active
        FROM project_theme_body_versions;
        """, context: "Project DB")
    }

    private static func legacyThemePayloadToLensSQL(_ column: String) -> String {
        var expression = column
        for (old, new) in [
            ("\"theme_id\"", "\"lens_id\""),
            ("\"target_theme_id\"", "\"target_lens_id\""),
            ("\"selected_theme_id\"", "\"selected_lens_id\""),
            ("\"source_theme_set_version_id\"", "\"source_lens_set_version_id\""),
            ("\"themes\"", "\"lenses\""),
            ("\"theme_edit_messages\"", "\"lens_edit_messages\""),
            ("\"theme_body_versions\"", "\"lens_body_versions\""),
            ("\"theme_status_at_generation\"", "\"lens_status_at_generation\""),
            ("\"theme_title\"", "\"lens_title\"")
        ] {
            expression = "replace(\(expression), '\(old)', '\(new)')"
        }
        return expression
    }

    private static func createProjectStorySchemaV2(_ connection: OpaquePointer) throws {
        let statements = [
            """
            CREATE TABLE project_content_imports (
                import_id TEXT PRIMARY KEY,
                project_id TEXT NOT NULL,
                source_summary_json TEXT NOT NULL,
                warnings_json TEXT NOT NULL,
                completed_at TEXT NOT NULL,
                FOREIGN KEY(project_id) REFERENCES project_identity(project_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE project_projection_rebuilds (
                rebuild_id TEXT PRIMARY KEY,
                project_id TEXT NOT NULL,
                projection_kind TEXT NOT NULL,
                status TEXT NOT NULL CHECK(status IN ('succeeded', 'failed')),
                details_json TEXT NOT NULL,
                completed_at TEXT NOT NULL,
                FOREIGN KEY(project_id) REFERENCES project_identity(project_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE scene_story_imports (
                import_row_id TEXT PRIMARY KEY,
                project_id TEXT NOT NULL,
                source_kind TEXT NOT NULL,
                source_id TEXT NOT NULL,
                source_path TEXT NOT NULL,
                source_sha256 TEXT NOT NULL,
                source_json TEXT NOT NULL,
                imported_at TEXT NOT NULL,
                UNIQUE(project_id, source_kind, source_id, source_sha256),
                FOREIGN KEY(project_id) REFERENCES project_identity(project_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE project_story_library_state (
                project_id TEXT PRIMARY KEY,
                active_story_id TEXT NOT NULL DEFAULT '',
                updated_at TEXT NOT NULL,
                record_revision INTEGER NOT NULL DEFAULT 1 CHECK(record_revision > 0),
                FOREIGN KEY(project_id) REFERENCES project_identity(project_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE project_story_documents (
                project_id TEXT PRIMARY KEY,
                accepted_story_id TEXT NOT NULL DEFAULT '',
                project_story_id TEXT NOT NULL DEFAULT '',
                story_json TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                record_revision INTEGER NOT NULL DEFAULT 1 CHECK(record_revision > 0),
                FOREIGN KEY(project_id) REFERENCES project_identity(project_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE project_stories (
                project_story_id TEXT PRIMARY KEY,
                project_id TEXT NOT NULL,
                library_entry_id TEXT UNIQUE,
                source_scene_story_set_id TEXT NOT NULL DEFAULT '',
                source_story_id TEXT NOT NULL DEFAULT '',
                current_story_version_id TEXT,
                story_signature_id TEXT NOT NULL DEFAULT '',
                editorial_state TEXT NOT NULL CHECK(editorial_state IN ('suggestion', 'kept', 'dismissed', 'archived')),
                production_state TEXT NOT NULL CHECK(production_state IN ('not_started', 'developing', 'in_production', 'complete')),
                title TEXT NOT NULL,
                lens_ids_json TEXT NOT NULL,
                payload_json TEXT NOT NULL,
                record_revision INTEGER NOT NULL DEFAULT 1 CHECK(record_revision > 0),
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                FOREIGN KEY(project_id) REFERENCES project_identity(project_id) ON DELETE CASCADE,
                FOREIGN KEY(current_story_version_id) REFERENCES story_versions(story_version_id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED
            );
            """,
            """
            CREATE TABLE story_versions (
                story_version_id TEXT PRIMARY KEY,
                project_story_id TEXT NOT NULL,
                version_number INTEGER NOT NULL CHECK(version_number > 0),
                lifecycle_state TEXT NOT NULL CHECK(lifecycle_state IN ('draft', 'published')),
                parent_story_version_id TEXT,
                source_story_suggestion_id TEXT NOT NULL DEFAULT '',
                reason TEXT NOT NULL,
                story_payload_json TEXT NOT NULL,
                lock_manifest_json TEXT NOT NULL,
                content_fingerprint TEXT NOT NULL,
                record_revision INTEGER NOT NULL DEFAULT 1 CHECK(record_revision > 0),
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                UNIQUE(project_story_id, version_number),
                FOREIGN KEY(project_story_id) REFERENCES project_stories(project_story_id) ON DELETE CASCADE,
                FOREIGN KEY(parent_story_version_id) REFERENCES story_versions(story_version_id) ON DELETE RESTRICT
            );
            """,
            """
            CREATE TABLE story_scenes (
                scene_row_id TEXT PRIMARY KEY,
                story_version_id TEXT NOT NULL,
                source_scene_id TEXT NOT NULL,
                scene_order INTEGER NOT NULL CHECK(scene_order > 0),
                title TEXT NOT NULL,
                scene_function TEXT NOT NULL,
                support_status TEXT NOT NULL,
                locked INTEGER NOT NULL DEFAULT 0 CHECK(locked IN (0, 1)),
                scene_payload_json TEXT NOT NULL,
                content_fingerprint TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                UNIQUE(story_version_id, scene_order),
                UNIQUE(story_version_id, source_scene_id),
                FOREIGN KEY(story_version_id) REFERENCES story_versions(story_version_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE story_beats (
                beat_row_id TEXT PRIMARY KEY,
                scene_row_id TEXT NOT NULL,
                source_beat_id TEXT NOT NULL,
                beat_order INTEGER NOT NULL CHECK(beat_order > 0),
                title TEXT NOT NULL,
                beat_description TEXT NOT NULL,
                shot_type TEXT NOT NULL,
                support_status TEXT NOT NULL,
                evidence_basis TEXT,
                locked INTEGER NOT NULL DEFAULT 0 CHECK(locked IN (0, 1)),
                prompt_intent TEXT,
                continuity_in TEXT,
                continuity_out TEXT,
                beat_payload_json TEXT NOT NULL,
                production_contract_json TEXT NOT NULL,
                content_fingerprint TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                UNIQUE(scene_row_id, beat_order),
                UNIQUE(scene_row_id, source_beat_id),
                FOREIGN KEY(scene_row_id) REFERENCES story_scenes(scene_row_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE story_signatures (
                story_signature_id TEXT PRIMARY KEY,
                project_id TEXT NOT NULL,
                project_story_id TEXT NOT NULL DEFAULT '',
                story_version_id TEXT NOT NULL DEFAULT '',
                title TEXT NOT NULL,
                context_class TEXT NOT NULL,
                signature_json TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                FOREIGN KEY(project_id) REFERENCES project_identity(project_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE story_generation_sessions (
                generation_session_id TEXT PRIMARY KEY,
                project_id TEXT NOT NULL,
                status TEXT NOT NULL,
                started_at TEXT NOT NULL,
                completed_at TEXT NOT NULL,
                session_json TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                FOREIGN KEY(project_id) REFERENCES project_identity(project_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE reference_sets (
                reference_set_row_id TEXT PRIMARY KEY,
                story_version_id TEXT NOT NULL,
                reference_set_id TEXT NOT NULL,
                label TEXT NOT NULL,
                status TEXT NOT NULL CHECK(status IN ('resolved', 'unresolved', 'provisional')),
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                UNIQUE(story_version_id, reference_set_id),
                FOREIGN KEY(story_version_id) REFERENCES story_versions(story_version_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE reference_assets (
                reference_asset_row_id TEXT PRIMARY KEY,
                reference_set_row_id TEXT NOT NULL,
                media_id TEXT NOT NULL,
                frame_id TEXT NOT NULL DEFAULT '',
                role TEXT NOT NULL,
                notes TEXT NOT NULL DEFAULT '',
                created_at TEXT NOT NULL,
                UNIQUE(reference_set_row_id, media_id, frame_id, role),
                FOREIGN KEY(reference_set_row_id) REFERENCES reference_sets(reference_set_row_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE story_entities (
                entity_row_id TEXT PRIMARY KEY,
                story_version_id TEXT NOT NULL,
                entity_id TEXT NOT NULL,
                kind TEXT NOT NULL,
                display_label TEXT NOT NULL,
                resolution_status TEXT NOT NULL CHECK(resolution_status IN ('resolved', 'provisional', 'unresolved')),
                resolution_basis TEXT NOT NULL,
                reference_set_row_id TEXT,
                appearance_invariants_json TEXT NOT NULL,
                initial_state_json TEXT NOT NULL,
                final_state_json TEXT NOT NULL,
                allowed_variation_json TEXT NOT NULL,
                forbidden_transformations_json TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                UNIQUE(story_version_id, entity_id),
                FOREIGN KEY(story_version_id) REFERENCES story_versions(story_version_id) ON DELETE CASCADE,
                FOREIGN KEY(reference_set_row_id) REFERENCES reference_sets(reference_set_row_id) ON DELETE SET NULL
            );
            """,
            """
            CREATE TABLE beat_entity_refs (
                beat_row_id TEXT NOT NULL,
                entity_row_id TEXT NOT NULL,
                role TEXT NOT NULL,
                visibility TEXT NOT NULL DEFAULT '',
                state_json TEXT NOT NULL,
                PRIMARY KEY(beat_row_id, entity_row_id, role),
                FOREIGN KEY(beat_row_id) REFERENCES story_beats(beat_row_id) ON DELETE CASCADE,
                FOREIGN KEY(entity_row_id) REFERENCES story_entities(entity_row_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE beat_events (
                event_row_id TEXT PRIMARY KEY,
                beat_row_id TEXT NOT NULL,
                event_id TEXT NOT NULL,
                start_value INTEGER NOT NULL CHECK(start_value >= 0),
                duration_value INTEGER NOT NULL CHECK(duration_value > 0),
                rate_num INTEGER NOT NULL CHECK(rate_num > 0),
                rate_den INTEGER NOT NULL CHECK(rate_den > 0),
                actor_entity_row_id TEXT,
                object_entity_row_id TEXT,
                action TEXT NOT NULL,
                attention_track TEXT NOT NULL DEFAULT '',
                hold_duration_value INTEGER NOT NULL DEFAULT 0 CHECK(hold_duration_value >= 0),
                easing TEXT NOT NULL DEFAULT '',
                payload_json TEXT NOT NULL,
                UNIQUE(beat_row_id, event_id),
                FOREIGN KEY(beat_row_id) REFERENCES story_beats(beat_row_id) ON DELETE CASCADE,
                FOREIGN KEY(actor_entity_row_id) REFERENCES story_entities(entity_row_id) ON DELETE SET NULL,
                FOREIGN KEY(object_entity_row_id) REFERENCES story_entities(entity_row_id) ON DELETE SET NULL
            );
            """,
            """
            CREATE TABLE beat_event_dependencies (
                event_row_id TEXT NOT NULL,
                depends_on_event_row_id TEXT NOT NULL,
                dependency_kind TEXT NOT NULL,
                PRIMARY KEY(event_row_id, depends_on_event_row_id, dependency_kind),
                CHECK(event_row_id != depends_on_event_row_id),
                FOREIGN KEY(event_row_id) REFERENCES beat_events(event_row_id) ON DELETE CASCADE,
                FOREIGN KEY(depends_on_event_row_id) REFERENCES beat_events(event_row_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE beat_world_state_deltas (
                delta_row_id TEXT PRIMARY KEY,
                beat_row_id TEXT NOT NULL,
                entity_row_id TEXT NOT NULL,
                property_path TEXT NOT NULL,
                from_json TEXT NOT NULL,
                to_json TEXT NOT NULL,
                confidence REAL NOT NULL DEFAULT 1 CHECK(confidence >= 0 AND confidence <= 1),
                source TEXT NOT NULL,
                FOREIGN KEY(beat_row_id) REFERENCES story_beats(beat_row_id) ON DELETE CASCADE,
                FOREIGN KEY(entity_row_id) REFERENCES story_entities(entity_row_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE editorial_shots (
                shot_row_id TEXT PRIMARY KEY,
                beat_row_id TEXT NOT NULL,
                shot_id TEXT NOT NULL,
                shot_order INTEGER NOT NULL CHECK(shot_order > 0),
                duration_value INTEGER NOT NULL CHECK(duration_value > 0),
                rate_num INTEGER NOT NULL CHECK(rate_num > 0),
                rate_den INTEGER NOT NULL CHECK(rate_den > 0),
                continuity_mode TEXT NOT NULL,
                camera_json TEXT NOT NULL,
                lighting_json TEXT NOT NULL,
                audio_json TEXT NOT NULL,
                performance_json TEXT NOT NULL,
                spatial_blocking_json TEXT NOT NULL,
                field_policies_json TEXT NOT NULL,
                generation_policy_json TEXT NOT NULL,
                payload_json TEXT NOT NULL,
                UNIQUE(beat_row_id, shot_order),
                UNIQUE(beat_row_id, shot_id),
                FOREIGN KEY(beat_row_id) REFERENCES story_beats(beat_row_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE shot_event_spans (
                shot_row_id TEXT NOT NULL,
                event_row_id TEXT NOT NULL,
                start_value INTEGER NOT NULL CHECK(start_value >= 0),
                duration_value INTEGER NOT NULL CHECK(duration_value > 0),
                rate_num INTEGER NOT NULL CHECK(rate_num > 0),
                rate_den INTEGER NOT NULL CHECK(rate_den > 0),
                PRIMARY KEY(shot_row_id, event_row_id),
                FOREIGN KEY(shot_row_id) REFERENCES editorial_shots(shot_row_id) ON DELETE CASCADE,
                FOREIGN KEY(event_row_id) REFERENCES beat_events(event_row_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE shot_constraints (
                constraint_row_id TEXT PRIMARY KEY,
                shot_row_id TEXT NOT NULL,
                rule TEXT NOT NULL,
                strength TEXT NOT NULL CHECK(strength IN ('hard', 'soft', 'exploratory', 'forbidden')),
                priority INTEGER NOT NULL CHECK(priority >= 0 AND priority <= 100),
                scope TEXT NOT NULL,
                source TEXT NOT NULL,
                failure_action TEXT NOT NULL,
                FOREIGN KEY(shot_row_id) REFERENCES editorial_shots(shot_row_id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE shot_acceptance_criteria (
                criterion_row_id TEXT PRIMARY KEY,
                shot_row_id TEXT NOT NULL,
                criterion TEXT NOT NULL,
                severity TEXT NOT NULL CHECK(severity IN ('reject', 'repairable', 'advisory')),
                method TEXT NOT NULL,
                repair_action TEXT NOT NULL DEFAULT '',
                FOREIGN KEY(shot_row_id) REFERENCES editorial_shots(shot_row_id) ON DELETE CASCADE
            );
            """
        ]
        for statement in statements {
            try litScenesSQLiteExecute(connection, statement, context: "Project DB")
        }

        let indexes = [
            "CREATE INDEX project_stories_project_idx ON project_stories(project_id, updated_at);",
            "CREATE INDEX story_versions_story_idx ON story_versions(project_story_id, version_number);",
            "CREATE INDEX story_scenes_version_idx ON story_scenes(story_version_id, scene_order);",
            "CREATE INDEX story_beats_scene_idx ON story_beats(scene_row_id, beat_order);",
            "CREATE INDEX story_signatures_project_idx ON story_signatures(project_id, updated_at);",
            "CREATE INDEX story_generation_sessions_project_idx ON story_generation_sessions(project_id, started_at);",
            "CREATE INDEX scene_story_imports_project_idx ON scene_story_imports(project_id, source_kind, source_id);",
            "CREATE INDEX story_entities_version_idx ON story_entities(story_version_id, entity_id);",
            "CREATE INDEX beat_events_beat_idx ON beat_events(beat_row_id, event_id);",
            "CREATE INDEX editorial_shots_beat_idx ON editorial_shots(beat_row_id, shot_order);"
        ]
        for index in indexes {
            try litScenesSQLiteExecute(connection, index, context: "Project DB")
        }
    }

    private static func runProjectIntegrityChecks(_ connection: OpaquePointer, context: String) throws {
        let quickCheck = try scalarText(connection, sql: "PRAGMA quick_check;", context: context)
        guard quickCheck == "ok" else {
            throw ScreenGraphError.capture("\(context) quick_check failed: \(quickCheck)")
        }
        let foreignKeyFailures = try foreignKeyViolationCount(connection, context: context)
        guard foreignKeyFailures == 0 else {
            throw ScreenGraphError.capture("\(context) foreign_key_check failed: \(foreignKeyFailures) violation(s)")
        }
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

    private static func scalarText(_ connection: OpaquePointer, sql: String, context: String) throws -> String {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ScreenGraphError.capture("\(context) scalar text prepare failed: \(litScenesSQLiteMessage(connection))")
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return "" }
        return litScenesSQLiteColumnText(statement, 0)
    }

    private static func scalarInt(_ connection: OpaquePointer, sql: String, context: String) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ScreenGraphError.capture("\(context) scalar int prepare failed: \(litScenesSQLiteMessage(connection))")
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(statement, 0))
    }

    private static func backupProjectDatabaseBeforeV2Migration(
        project: ProjectRecord,
        projectLibrary: ProjectLibrary
    ) throws {
        let sourceURL = projectDatabaseURL(for: project, projectLibrary: projectLibrary)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else { return }
        let backupDirectory = sourceURL.deletingLastPathComponent().appendingPathComponent(".backups", isDirectory: true)
        try ensureDirectory(backupDirectory)
        let timestamp = safeIdentifier(DateFormats.now())
        let destinationURL = backupDirectory.appendingPathComponent("LitScenes.db.before_story_scene_beat_v2_\(timestamp).sqlite")
        guard !FileManager.default.fileExists(atPath: destinationURL.path) else { return }
        try backupDatabase(from: sourceURL, to: destinationURL)
    }

    private static func backupProjectDatabaseBeforeV4Migration(
        project: ProjectRecord,
        projectLibrary: ProjectLibrary
    ) throws {
        let sourceURL = projectDatabaseURL(for: project, projectLibrary: projectLibrary)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else { return }
        let backupDirectory = sourceURL.deletingLastPathComponent().appendingPathComponent(".backups", isDirectory: true)
        try ensureDirectory(backupDirectory)
        let timestamp = safeIdentifier(DateFormats.now())
        let destinationURL = backupDirectory.appendingPathComponent("LitScenes.db.before_goal_theme_v4_\(timestamp).sqlite")
        guard !FileManager.default.fileExists(atPath: destinationURL.path) else { return }
        try backupDatabase(from: sourceURL, to: destinationURL)
    }

    private static func backupProjectDatabaseBeforeV5Migration(
        project: ProjectRecord,
        projectLibrary: ProjectLibrary
    ) throws {
        let sourceURL = projectDatabaseURL(for: project, projectLibrary: projectLibrary)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else { return }
        let backupDirectory = sourceURL.deletingLastPathComponent().appendingPathComponent(".backups", isDirectory: true)
        try ensureDirectory(backupDirectory)
        let timestamp = safeIdentifier(DateFormats.now())
        let destinationURL = backupDirectory.appendingPathComponent("LitScenes.db.before_media_v5_\(timestamp).sqlite")
        guard !FileManager.default.fileExists(atPath: destinationURL.path) else { return }
        try backupDatabase(from: sourceURL, to: destinationURL)
    }

    private static func backupProjectDatabaseBeforeV6Migration(
        project: ProjectRecord,
        projectLibrary: ProjectLibrary
    ) throws {
        let sourceURL = projectDatabaseURL(for: project, projectLibrary: projectLibrary)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else { return }
        let backupDirectory = sourceURL.deletingLastPathComponent().appendingPathComponent(".backups", isDirectory: true)
        try ensureDirectory(backupDirectory)
        let timestamp = safeIdentifier(DateFormats.now())
        let destinationURL = backupDirectory.appendingPathComponent("LitScenes.db.before_theme_versioning_v6_\(timestamp).sqlite")
        guard !FileManager.default.fileExists(atPath: destinationURL.path) else { return }
        try backupDatabase(from: sourceURL, to: destinationURL)
    }

    private static func backupProjectDatabaseBeforeV7Migration(
        project: ProjectRecord,
        projectLibrary: ProjectLibrary
    ) throws {
        let sourceURL = projectDatabaseURL(for: project, projectLibrary: projectLibrary)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else { return }
        let backupDirectory = sourceURL.deletingLastPathComponent().appendingPathComponent(".backups", isDirectory: true)
        try ensureDirectory(backupDirectory)
        let timestamp = safeIdentifier(DateFormats.now())
        let destinationURL = backupDirectory.appendingPathComponent("LitScenes.db.before_lens_rename_v7_\(timestamp).sqlite")
        guard !FileManager.default.fileExists(atPath: destinationURL.path) else { return }
        try backupDatabase(from: sourceURL, to: destinationURL)
    }

    private static func backupProjectDatabaseBeforeV12Migration(
        project: ProjectRecord,
        projectLibrary: ProjectLibrary
    ) throws {
        let sourceURL = projectDatabaseURL(for: project, projectLibrary: projectLibrary)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else { return }
        let backupDirectory = sourceURL.deletingLastPathComponent().appendingPathComponent(".backups", isDirectory: true)
        try ensureDirectory(backupDirectory)
        let timestamp = safeIdentifier(DateFormats.now())
        let destinationURL = backupDirectory.appendingPathComponent("LitScenes.db.before_audio_media_kind_v12_\(timestamp).sqlite")
        guard !FileManager.default.fileExists(atPath: destinationURL.path) else { return }
        try backupDatabase(from: sourceURL, to: destinationURL)
    }

    private static func backupDatabase(from sourceURL: URL, to destinationURL: URL) throws {
        var source: OpaquePointer?
        guard sqlite3_open_v2(sourceURL.path, &source, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let sourceConnection = source else {
            let message = source.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "could not open source"
            if let source {
                sqlite3_close(source)
            }
            throw ScreenGraphError.capture("Project DB backup source open failed: \(message)")
        }
        defer { sqlite3_close(sourceConnection) }

        var destination: OpaquePointer?
        guard sqlite3_open_v2(destinationURL.path, &destination, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let destinationConnection = destination else {
            let message = destination.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "could not open destination"
            if let destination {
                sqlite3_close(destination)
            }
            throw ScreenGraphError.capture("Project DB backup destination open failed: \(message)")
        }
        defer { sqlite3_close(destinationConnection) }

        guard let backup = sqlite3_backup_init(destinationConnection, "main", sourceConnection, "main") else {
            throw ScreenGraphError.capture("Project DB backup init failed: \(String(cString: sqlite3_errmsg(destinationConnection)))")
        }
        defer { sqlite3_backup_finish(backup) }

        let result = sqlite3_backup_step(backup, -1)
        guard result == SQLITE_DONE else {
            throw ScreenGraphError.capture("Project DB backup step failed: \(String(cString: sqlite3_errmsg(destinationConnection)))")
        }
    }

    private static func loadLegacySoundAssets(_ connection: OpaquePointer) throws -> [SoundSceneAsset] {
        let sql = """
        SELECT schema_version, sound_id, display_name, path, file_type, byte_count, modified_at,
               duration_seconds, discovered_at, updated_at
        FROM sound_assets;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ScreenGraphError.capture("Legacy sound asset query prepare failed: \(litScenesSQLiteMessage(connection))")
        }
        defer { sqlite3_finalize(statement) }
        var assets: [SoundSceneAsset] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            assets.append(SoundSceneAsset(
                schemaVersion: litScenesSQLiteColumnText(statement, 0),
                soundId: litScenesSQLiteColumnText(statement, 1),
                displayName: litScenesSQLiteColumnText(statement, 2),
                path: litScenesSQLiteColumnText(statement, 3),
                fileType: litScenesSQLiteColumnText(statement, 4),
                byteCount: sqlite3_column_int64(statement, 5),
                modifiedAt: litScenesSQLiteColumnText(statement, 6),
                durationSeconds: sqlite3_column_double(statement, 7),
                discoveredAt: litScenesSQLiteColumnText(statement, 8),
                updatedAt: litScenesSQLiteColumnText(statement, 9)
            ))
        }
        return assets
    }

    private static func loadLegacySoundScenePlans(_ connection: OpaquePointer) throws -> [SoundScenePlan] {
        let sql = """
        SELECT schema_version, plan_id, project_id, sound_id, start_seconds, duration_seconds,
               title, setup, turn, resolution, notes, created_at, updated_at
        FROM sound_scene_plans;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ScreenGraphError.capture("Legacy sound scene plan query prepare failed: \(litScenesSQLiteMessage(connection))")
        }
        defer { sqlite3_finalize(statement) }
        var plans: [SoundScenePlan] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            plans.append(SoundScenePlan(
                schemaVersion: litScenesSQLiteColumnText(statement, 0),
                planId: litScenesSQLiteColumnText(statement, 1),
                projectId: litScenesSQLiteColumnText(statement, 2),
                soundId: litScenesSQLiteColumnText(statement, 3),
                startSeconds: sqlite3_column_double(statement, 4),
                durationSeconds: sqlite3_column_double(statement, 5),
                title: litScenesSQLiteColumnText(statement, 6),
                setup: litScenesSQLiteColumnText(statement, 7),
                turn: litScenesSQLiteColumnText(statement, 8),
                resolution: litScenesSQLiteColumnText(statement, 9),
                notes: litScenesSQLiteColumnText(statement, 10),
                createdAt: litScenesSQLiteColumnText(statement, 11),
                updatedAt: litScenesSQLiteColumnText(statement, 12)
            ))
        }
        return plans
    }

    private static func upsertSoundAsset(_ asset: SoundSceneAsset, connection: OpaquePointer) throws {
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
            throw ScreenGraphError.capture("Migrated sound asset upsert prepare failed: \(litScenesSQLiteMessage(connection))")
        }
        defer { sqlite3_finalize(statement) }
        litScenesSQLiteBindText(asset.schemaVersion, to: 1, in: statement)
        litScenesSQLiteBindText(asset.soundId, to: 2, in: statement)
        litScenesSQLiteBindText(asset.displayName, to: 3, in: statement)
        litScenesSQLiteBindText(asset.path, to: 4, in: statement)
        litScenesSQLiteBindText(asset.fileType, to: 5, in: statement)
        sqlite3_bind_int64(statement, 6, asset.byteCount)
        litScenesSQLiteBindText(asset.modifiedAt, to: 7, in: statement)
        sqlite3_bind_double(statement, 8, asset.durationSeconds)
        litScenesSQLiteBindText(asset.discoveredAt, to: 9, in: statement)
        litScenesSQLiteBindText(asset.updatedAt, to: 10, in: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw ScreenGraphError.capture("Migrated sound asset upsert failed: \(litScenesSQLiteMessage(connection))")
        }
    }

    private static func upsertSoundScenePlan(_ plan: SoundScenePlan, connection: OpaquePointer) throws {
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
            throw ScreenGraphError.capture("Migrated sound scene plan upsert prepare failed: \(litScenesSQLiteMessage(connection))")
        }
        defer { sqlite3_finalize(statement) }
        litScenesSQLiteBindText(plan.schemaVersion, to: 1, in: statement)
        litScenesSQLiteBindText(plan.planId, to: 2, in: statement)
        litScenesSQLiteBindText(plan.projectId, to: 3, in: statement)
        litScenesSQLiteBindText(plan.soundId, to: 4, in: statement)
        sqlite3_bind_double(statement, 5, plan.startSeconds)
        sqlite3_bind_double(statement, 6, plan.durationSeconds)
        litScenesSQLiteBindText(plan.title, to: 7, in: statement)
        litScenesSQLiteBindText(plan.setup, to: 8, in: statement)
        litScenesSQLiteBindText(plan.turn, to: 9, in: statement)
        litScenesSQLiteBindText(plan.resolution, to: 10, in: statement)
        litScenesSQLiteBindText(plan.notes, to: 11, in: statement)
        litScenesSQLiteBindText(plan.createdAt, to: 12, in: statement)
        litScenesSQLiteBindText(plan.updatedAt, to: 13, in: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw ScreenGraphError.capture("Migrated sound scene plan upsert failed: \(litScenesSQLiteMessage(connection))")
        }
    }
}

func litScenesSQLiteExecute(_ connection: OpaquePointer, _ sql: String, context: String) throws {
    guard sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK else {
        throw ScreenGraphError.capture("\(context) SQL failed: \(litScenesSQLiteMessage(connection))")
    }
}

func litScenesSQLiteMessage(_ connection: OpaquePointer) -> String {
    String(cString: sqlite3_errmsg(connection))
}

func litScenesSQLiteBindText(_ value: String, to index: Int32, in statement: OpaquePointer) {
    _ = value.withCString { pointer in
        sqlite3_bind_text(statement, index, pointer, -1, litScenesSQLiteTransient)
    }
}

func litScenesSQLiteColumnText(_ statement: OpaquePointer, _ index: Int32) -> String {
    guard let pointer = sqlite3_column_text(statement, index) else { return "" }
    return String(cString: pointer)
}
