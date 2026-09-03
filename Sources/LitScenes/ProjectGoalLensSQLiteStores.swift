import Foundation
import SQLite3

private enum ProjectCreativeSQLite {
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
        let value = litScenesSQLiteColumnText(statement, index).trimmed
        return value.isEmpty ? nil : value
    }

    static func jsonString<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try JSONCoding.encoder.encode(value), as: UTF8.self)
    }

    static func decodeJSON<T: Decodable>(_ type: T.Type, from string: String) throws -> T {
        try JSONCoding.decoder.decode(type, from: Data(string.utf8))
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

struct ProjectGoalSQLiteStore {
    private static let queue = DispatchQueue(label: "local.litscenes.project-goal-sqlite-store")
    private let context = "Project Goal DB"
    let projectLibrary: ProjectLibrary

    init(projectLibrary: ProjectLibrary = ProjectLibrary()) {
        self.projectLibrary = projectLibrary
    }

    func goalExists(for project: ProjectRecord) -> Bool {
        (try? hasTypedGoal(for: project)) == true || legacyGoalData(for: project) != nil
    }

    func loadProjectGoal(for project: ProjectRecord) throws -> ProjectGoalDocumentV2? {
        try importLegacyGoalIfNeeded(for: project)
        return try ProjectCreativeSQLite.withProjectConnection(
            project,
            projectLibrary: projectLibrary,
            readOnly: true,
            context: context
        ) { connection in
            try loadTypedGoal(for: project, connection: connection)
        }
    }

    func saveProjectGoal(_ goal: ProjectGoalDocumentV2, for project: ProjectRecord) throws {
        var document = goal
        if document.projectId.trimmed.isEmpty {
            document.projectId = project.projectId
        }
        try Self.queue.sync {
            try ProjectCreativeSQLite.writeTransaction(
                project: project,
                projectLibrary: projectLibrary,
                context: context
            ) { connection in
                try replaceGoal(document, project: project, connection: connection)
            }
        }
    }

    private func importLegacyGoalIfNeeded(for project: ProjectRecord) throws {
        guard try !hasTypedGoal(for: project), let data = legacyGoalData(for: project) else { return }
        var document = try ProjectGoalDocumentV2.decode(from: data)
        if document.projectId.trimmed.isEmpty {
            document.projectId = project.projectId
        }
        try saveProjectGoal(document, for: project)
    }

    private func hasTypedGoal(for project: ProjectRecord) throws -> Bool {
        try ProjectCreativeSQLite.withProjectConnection(
            project,
            projectLibrary: projectLibrary,
            readOnly: true,
            context: context
        ) { connection in
            try ProjectCreativeSQLite.scalarInt(
                connection,
                sql: "SELECT COUNT(*) FROM project_goal_state WHERE project_id = ?;",
                bindings: [project.projectId],
                context: context
            ) > 0
        }
    }

    private func legacyGoalData(for project: ProjectRecord) -> Data? {
        try? ProjectCreativeSQLite.withProjectConnection(
            project,
            projectLibrary: projectLibrary,
            readOnly: true,
            context: context
        ) { connection in
            guard let json = try ProjectCreativeSQLite.optionalString(
                connection,
                sql: """
                SELECT payload_json FROM project_documents
                WHERE project_id = ? AND document_type = 'project_goal_v2' AND document_id = 'default'
                LIMIT 1;
                """,
                bindings: [project.projectId],
                context: context
            ) else {
                return nil
            }
            return Data(json.utf8)
        }
    }

    private func loadTypedGoal(
        for project: ProjectRecord,
        connection: OpaquePointer
    ) throws -> ProjectGoalDocumentV2? {
        let stateRows = try ProjectCreativeSQLite.query(
            connection,
            sql: """
            SELECT schema_version, active_version_id, updated_at
            FROM project_goal_state
            WHERE project_id = ?
            LIMIT 1;
            """,
            bindings: [project.projectId],
            context: context
        ) { statement in
            (
                ProjectCreativeSQLite.columnString(statement, 0),
                ProjectCreativeSQLite.columnString(statement, 1),
                ProjectCreativeSQLite.columnString(statement, 2)
            )
        }
        guard let state = stateRows.first else { return nil }

        let mediaByMessageId = try goalMessageMediaByMessageId(projectId: project.projectId, connection: connection)
        let messages = try ProjectCreativeSQLite.query(
            connection,
            sql: """
            SELECT message_id, role, text, created_at
            FROM project_goal_messages
            WHERE project_id = ?
            ORDER BY message_order ASC;
            """,
            bindings: [project.projectId],
            context: context
        ) { statement in
            let messageId = ProjectCreativeSQLite.columnString(statement, 0)
            return ProjectGoalMessageV2(
                messageId: messageId,
                role: ProjectGoalV2Role(rawValue: ProjectCreativeSQLite.columnString(statement, 1)) ?? .user,
                text: ProjectCreativeSQLite.columnString(statement, 2),
                mediaIds: mediaByMessageId[messageId] ?? [],
                createdAt: ProjectCreativeSQLite.columnString(statement, 3)
            )
        }

        let versions = try ProjectCreativeSQLite.query(
            connection,
            sql: """
            SELECT version_id, turn_index, content_type, goal, audience, desired_response,
                   viewer_experience, moodboard_articulation, lens_seed_summary, change_summary,
                   model, created_at
            FROM project_goal_versions
            WHERE project_id = ?
            ORDER BY version_order ASC;
            """,
            bindings: [project.projectId],
            context: context
        ) { statement in
            let versionId = ProjectCreativeSQLite.columnString(statement, 0)
            let brief = try goalBrief(versionId: versionId, statement: statement, connection: connection)
            return ProjectGoalBriefVersionV2(
                versionId: versionId,
                turnIndex: Int(sqlite3_column_int(statement, 1)),
                brief: brief,
                changeSummary: ProjectCreativeSQLite.columnString(statement, 9),
                createdAt: ProjectCreativeSQLite.columnString(statement, 11),
                model: ProjectCreativeSQLite.columnString(statement, 10),
                validationWarnings: try listItems(versionId: versionId, listKind: "validation_warnings", connection: connection)
            )
        }

        return ProjectGoalDocumentV2(
            schemaVersion: state.0.trimmed.isEmpty ? ProjectGoalDocumentV2.schemaVersion : state.0,
            projectId: project.projectId,
            messages: messages,
            versions: versions,
            activeVersionId: state.1,
            updatedAt: state.2
        )
    }

    private func goalBrief(
        versionId: String,
        statement: OpaquePointer,
        connection: OpaquePointer
    ) throws -> ProjectGoalBriefV2 {
        let contentTypeRaw = ProjectCreativeSQLite.optionalColumnString(statement, 2)
        return ProjectGoalBriefV2(
            contentType: contentTypeRaw.flatMap(ProjectIntent.init(rawValue:)),
            goal: ProjectCreativeSQLite.columnString(statement, 3),
            audience: ProjectCreativeSQLite.columnString(statement, 4),
            desiredResponse: ProjectCreativeSQLite.columnString(statement, 5),
            viewerExperience: ProjectCreativeSQLite.columnString(statement, 6),
            moodboardArticulation: ProjectCreativeSQLite.columnString(statement, 7),
            successCriteria: try listItems(versionId: versionId, listKind: "success_criteria", connection: connection),
            constraints: try listItems(versionId: versionId, listKind: "constraints", connection: connection),
            requiredEntities: try requiredEntities(versionId: versionId, connection: connection),
            openQuestions: try listItems(versionId: versionId, listKind: "open_questions", connection: connection),
            lensSeedSummary: ProjectCreativeSQLite.columnString(statement, 8),
            lensSeedTerms: try listItems(versionId: versionId, listKind: "lens_seed_terms", connection: connection),
            meaningNodeRefs: try meaningNodeRefs(versionId: versionId, connection: connection),
            aestheticTermRefs: try aestheticTermRefs(versionId: versionId, connection: connection),
            styleTermRefs: try styleTermRefs(versionId: versionId, connection: connection)
        ).normalized()
    }

    private func replaceGoal(
        _ document: ProjectGoalDocumentV2,
        project: ProjectRecord,
        connection: OpaquePointer
    ) throws {
        try ProjectCreativeSQLite.execute(
            "DELETE FROM project_goal_state WHERE project_id = ?;",
            connection: connection,
            bindings: [project.projectId],
            context: context
        )
        try ProjectCreativeSQLite.execute(
            """
            INSERT INTO project_goal_state (
                project_id, schema_version, active_version_id, updated_at
            ) VALUES (?, ?, ?, ?);
            """,
            connection: connection,
            bindings: [project.projectId, document.schemaVersion, document.activeVersionId, document.updatedAt],
            context: context
        )
        for (messageOrder, message) in document.messages.enumerated() {
            try insertGoalMessage(message, order: messageOrder, projectId: project.projectId, connection: connection)
        }
        for (versionOrder, version) in document.versions.enumerated() {
            try insertGoalVersion(version, order: versionOrder, projectId: project.projectId, connection: connection)
        }
    }

    private func insertGoalMessage(
        _ message: ProjectGoalMessageV2,
        order: Int,
        projectId: String,
        connection: OpaquePointer
    ) throws {
        try ProjectCreativeSQLite.execute(
            """
            INSERT INTO project_goal_messages (
                message_id, project_id, message_order, role, text, created_at
            ) VALUES (?, ?, ?, ?, ?, ?);
            """,
            connection: connection,
            bindings: [message.messageId, projectId, order, message.role.rawValue, message.text, message.createdAt],
            context: context
        )
        for (mediaOrder, mediaId) in message.mediaIds.enumerated() {
            try ProjectCreativeSQLite.execute(
                """
                INSERT INTO project_goal_message_media (
                    message_id, media_order, media_id
                ) VALUES (?, ?, ?);
                """,
                connection: connection,
                bindings: [message.messageId, mediaOrder, mediaId],
                context: context
            )
        }
    }

    private func insertGoalVersion(
        _ version: ProjectGoalBriefVersionV2,
        order: Int,
        projectId: String,
        connection: OpaquePointer
    ) throws {
        let brief = version.brief.normalized()
        let fingerprint = sha256Hex(try JSONCoding.encoder.encode(brief))
        try ProjectCreativeSQLite.execute(
            """
            INSERT INTO project_goal_versions (
                version_id, project_id, version_order, turn_index, content_type, goal, audience,
                desired_response, viewer_experience, moodboard_articulation, lens_seed_summary,
                change_summary, model, created_at, content_fingerprint
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            connection: connection,
            bindings: [
                version.versionId,
                projectId,
                order,
                version.turnIndex,
                brief.contentType?.rawValue,
                brief.goal,
                brief.audience,
                brief.desiredResponse,
                brief.viewerExperience,
                brief.moodboardArticulation,
                brief.lensSeedSummary,
                version.changeSummary,
                version.model,
                version.createdAt,
                fingerprint
            ],
            context: context
        )
        try insertListItems(brief.successCriteria, versionId: version.versionId, listKind: "success_criteria", connection: connection)
        try insertListItems(brief.constraints, versionId: version.versionId, listKind: "constraints", connection: connection)
        try insertListItems(brief.openQuestions, versionId: version.versionId, listKind: "open_questions", connection: connection)
        try insertListItems(brief.lensSeedTerms, versionId: version.versionId, listKind: "lens_seed_terms", connection: connection)
        try insertListItems(version.validationWarnings, versionId: version.versionId, listKind: "validation_warnings", connection: connection)
        for (entityOrder, entity) in brief.requiredEntities.enumerated() {
            try ProjectCreativeSQLite.execute(
                """
                INSERT INTO project_goal_required_entities (
                    version_id, entity_order, name, role, required
                ) VALUES (?, ?, ?, ?, ?);
                """,
                connection: connection,
                bindings: [version.versionId, entityOrder, entity.name, entity.role, entity.required],
                context: context
            )
        }
        for (refOrder, ref) in brief.meaningNodeRefs.enumerated() {
            try ProjectCreativeSQLite.execute(
                """
                INSERT INTO project_goal_meaning_node_refs (
                    version_id, ref_order, slug, kind, name, role, source, evidence
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
                """,
                connection: connection,
                bindings: [
                    version.versionId,
                    refOrder,
                    ref.slug,
                    ref.kind.rawValue,
                    ref.name,
                    ref.role.rawValue,
                    ref.source.rawValue,
                    ref.evidence
                ],
                context: context
            )
        }
        for (refOrder, ref) in brief.aestheticTermRefs.enumerated() {
            try ProjectCreativeSQLite.execute(
                """
                INSERT INTO project_goal_aesthetic_term_refs (
                    version_id, ref_order, facet_type, slug, display_name, role, source, evidence
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
                """,
                connection: connection,
                bindings: [
                    version.versionId,
                    refOrder,
                    ref.facetType.rawValue,
                    ref.slug,
                    ref.displayName,
                    ref.role.rawValue,
                    ref.source.rawValue,
                    ref.evidence
                ],
                context: context
            )
        }
        for (refOrder, ref) in brief.styleTermRefs.enumerated() {
            try ProjectCreativeSQLite.execute(
                """
                INSERT INTO project_goal_style_term_refs (
                    version_id, ref_order, term, kind, weight, rationale
                ) VALUES (?, ?, ?, ?, ?, ?);
                """,
                connection: connection,
                bindings: [
                    version.versionId,
                    refOrder,
                    ref.term,
                    ref.kind.rawValue,
                    ref.weight,
                    ref.rationale
                ],
                context: context
            )
        }
    }

    private func insertListItems(
        _ values: [String],
        versionId: String,
        listKind: String,
        connection: OpaquePointer
    ) throws {
        if listKind == "validation_warnings" {
            for (itemOrder, value) in uniqueNonEmpty(values).enumerated() {
                try ProjectCreativeSQLite.execute(
                    """
                    INSERT INTO project_goal_validation_warnings (
                        version_id, warning_order, warning
                    ) VALUES (?, ?, ?);
                    """,
                    connection: connection,
                    bindings: [versionId, itemOrder, value],
                    context: context
                )
            }
            return
        }
        for (itemOrder, value) in uniqueNonEmpty(values).enumerated() {
            try ProjectCreativeSQLite.execute(
                """
                INSERT INTO project_goal_brief_list_items (
                    version_id, list_kind, item_order, value
                ) VALUES (?, ?, ?, ?);
                """,
                connection: connection,
                bindings: [versionId, listKind, itemOrder, value],
                context: context
            )
        }
    }

    private func listItems(versionId: String, listKind: String, connection: OpaquePointer) throws -> [String] {
        if listKind == "validation_warnings" {
            return try ProjectCreativeSQLite.query(
                connection,
                sql: """
                SELECT warning FROM project_goal_validation_warnings
                WHERE version_id = ?
                ORDER BY warning_order ASC;
                """,
                bindings: [versionId],
                context: context
            ) { ProjectCreativeSQLite.columnString($0, 0) }
        }
        return try ProjectCreativeSQLite.query(
            connection,
            sql: """
            SELECT value FROM project_goal_brief_list_items
            WHERE version_id = ? AND list_kind = ?
            ORDER BY item_order ASC;
            """,
            bindings: [versionId, listKind],
            context: context
        ) { ProjectCreativeSQLite.columnString($0, 0) }
    }

    private func requiredEntities(versionId: String, connection: OpaquePointer) throws -> [ProjectGoalRequiredEntity] {
        try ProjectCreativeSQLite.query(
            connection,
            sql: """
            SELECT name, role, required FROM project_goal_required_entities
            WHERE version_id = ?
            ORDER BY entity_order ASC;
            """,
            bindings: [versionId],
            context: context
        ) { statement in
            ProjectGoalRequiredEntity(
                name: ProjectCreativeSQLite.columnString(statement, 0),
                role: ProjectCreativeSQLite.columnString(statement, 1),
                required: sqlite3_column_int(statement, 2) == 1
            )
        }
    }

    private func meaningNodeRefs(versionId: String, connection: OpaquePointer) throws -> [ProjectGoalMeaningNodeRef] {
        try ProjectCreativeSQLite.query(
            connection,
            sql: """
            SELECT slug, kind, name, role, source, evidence FROM project_goal_meaning_node_refs
            WHERE version_id = ?
            ORDER BY ref_order ASC;
            """,
            bindings: [versionId],
            context: context
        ) { statement in
            ProjectGoalMeaningNodeRef(
                slug: ProjectCreativeSQLite.columnString(statement, 0),
                kind: ProjectGoalMeaningNodeKind(rawValue: ProjectCreativeSQLite.columnString(statement, 1)) ?? .theme,
                name: ProjectCreativeSQLite.columnString(statement, 2),
                role: ProjectGoalMeaningNodeRefRole(rawValue: ProjectCreativeSQLite.columnString(statement, 3)) ?? .other,
                source: ProjectGoalMeaningRefSource(rawValue: ProjectCreativeSQLite.columnString(statement, 4)) ?? .goal,
                evidence: ProjectCreativeSQLite.columnString(statement, 5)
            )
        }
    }

    private func aestheticTermRefs(versionId: String, connection: OpaquePointer) throws -> [ProjectGoalAestheticTermRef] {
        try ProjectCreativeSQLite.query(
            connection,
            sql: """
            SELECT facet_type, slug, display_name, role, source, evidence FROM project_goal_aesthetic_term_refs
            WHERE version_id = ?
            ORDER BY ref_order ASC;
            """,
            bindings: [versionId],
            context: context
        ) { statement in
            ProjectGoalAestheticTermRef(
                facetType: ProjectGoalAestheticTermFacetType(rawValue: ProjectCreativeSQLite.columnString(statement, 0)) ?? .keyMotif,
                slug: ProjectCreativeSQLite.columnString(statement, 1),
                displayName: ProjectCreativeSQLite.columnString(statement, 2),
                role: ProjectGoalAestheticTermRefRole(rawValue: ProjectCreativeSQLite.columnString(statement, 3)) ?? .other,
                source: ProjectGoalMeaningRefSource(rawValue: ProjectCreativeSQLite.columnString(statement, 4)) ?? .goal,
                evidence: ProjectCreativeSQLite.columnString(statement, 5)
            )
        }
    }

    private func styleTermRefs(versionId: String, connection: OpaquePointer) throws -> [ProjectGoalStyleTermRef] {
        try ProjectCreativeSQLite.query(
            connection,
            sql: """
            SELECT term, kind, weight, rationale FROM project_goal_style_term_refs
            WHERE version_id = ?
            ORDER BY ref_order ASC;
            """,
            bindings: [versionId],
            context: context
        ) { statement in
            ProjectGoalStyleTermRef(
                term: ProjectCreativeSQLite.columnString(statement, 0),
                kind: ProjectGoalStyleTermKind(rawValue: ProjectCreativeSQLite.columnString(statement, 1)) ?? .phrase,
                weight: sqlite3_column_double(statement, 2),
                rationale: ProjectCreativeSQLite.columnString(statement, 3)
            )
        }
    }

    private func goalMessageMediaByMessageId(
        projectId: String,
        connection: OpaquePointer
    ) throws -> [String: [String]] {
        let rows = try ProjectCreativeSQLite.query(
            connection,
            sql: """
            SELECT m.message_id, mm.media_id
            FROM project_goal_messages m
            JOIN project_goal_message_media mm ON mm.message_id = m.message_id
            WHERE m.project_id = ?
            ORDER BY m.message_order ASC, mm.media_order ASC;
            """,
            bindings: [projectId],
            context: context
        ) { statement in
            (
                ProjectCreativeSQLite.columnString(statement, 0),
                ProjectCreativeSQLite.columnString(statement, 1)
            )
        }
        return Dictionary(grouping: rows, by: { $0.0 }).mapValues { rows in
            rows.map { $0.1 }
        }
    }
}

struct ProjectLensSQLiteStore {
    private static let queue = DispatchQueue(label: "local.litscenes.project-lens-sqlite-store")
    private let context = "Project Lens DB"
    let projectLibrary: ProjectLibrary

    init(projectLibrary: ProjectLibrary = ProjectLibrary()) {
        self.projectLibrary = projectLibrary
    }

    func lensSetExists(for project: ProjectRecord) -> Bool {
        (try? hasTypedLensSet(for: project)) == true || legacyLensData(for: project) != nil
    }

    func loadProjectLenses(for project: ProjectRecord) throws -> ProjectLensSetDocument? {
        try importLegacyLensesIfNeeded(for: project)
        return try ProjectCreativeSQLite.withProjectConnection(
            project,
            projectLibrary: projectLibrary,
            readOnly: true,
            context: context
        ) { connection in
            try loadTypedLenses(for: project, connection: connection)
        }
    }

    func saveProjectLenses(_ lenses: ProjectLensSetDocument, for project: ProjectRecord) throws {
        var document = lenses
        if document.projectId.trimmed.isEmpty {
            document.projectId = project.projectId
        }
        try Self.queue.sync {
            try ProjectCreativeSQLite.writeTransaction(
                project: project,
                projectLibrary: projectLibrary,
                context: context
            ) { connection in
                try replaceLenses(document, project: project, connection: connection)
            }
        }
    }

    private func importLegacyLensesIfNeeded(for project: ProjectRecord) throws {
        guard try !hasTypedLensSet(for: project), let data = legacyLensData(for: project) else { return }
        var document = try ProjectLensSetDocument.decode(from: data)
        if document.projectId.trimmed.isEmpty {
            document.projectId = project.projectId
        }
        try saveProjectLenses(document, for: project)
    }

    private func hasTypedLensSet(for project: ProjectRecord) throws -> Bool {
        try ProjectCreativeSQLite.withProjectConnection(
            project,
            projectLibrary: projectLibrary,
            readOnly: true,
            context: context
        ) { connection in
            try ProjectCreativeSQLite.scalarInt(
                connection,
                sql: "SELECT COUNT(*) FROM project_lens_state WHERE project_id = ?;",
                bindings: [project.projectId],
                context: context
            ) > 0
        }
    }

    private func legacyLensData(for project: ProjectRecord) -> Data? {
        try? ProjectCreativeSQLite.withProjectConnection(
            project,
            projectLibrary: projectLibrary,
            readOnly: true,
            context: context
        ) { connection in
            if let json = try ProjectCreativeSQLite.optionalString(
                connection,
                sql: """
                SELECT payload_json FROM project_documents
                WHERE project_id = ? AND document_type = 'project_lenses' AND document_id = 'default'
                LIMIT 1;
                """,
                bindings: [project.projectId],
                context: context
            ) {
                return Data(json.utf8)
            }

            guard let legacyJSON = try ProjectCreativeSQLite.optionalString(
                connection,
                sql: """
                SELECT payload_json FROM project_documents
                WHERE project_id = ? AND document_type = 'project_themes' AND document_id = 'default'
                LIMIT 1;
                """,
                bindings: [project.projectId],
                context: context
            ) else {
                return nil
            }
            return Data(Self.legacyThemeJSONToLensJSON(legacyJSON).utf8)
        }
    }

    private static func legacyThemeJSONToLensJSON(_ json: String) -> String {
        var output = json
        for (old, new) in [
            ("\"litscenes.project_theme_set.v0.1\"", "\"litscenes.project_lens_set.v0.1\""),
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
            output = output.replacingOccurrences(of: old, with: new)
        }
        return output
    }

    private func loadTypedLenses(
        for project: ProjectRecord,
        connection: OpaquePointer
    ) throws -> ProjectLensSetDocument? {
        let stateRows = try ProjectCreativeSQLite.query(
            connection,
            sql: """
            SELECT schema_version, active_version_id, updated_at
            FROM project_lens_state
            WHERE project_id = ?
            LIMIT 1;
            """,
            bindings: [project.projectId],
            context: context
        ) { statement in
            (
                ProjectCreativeSQLite.columnString(statement, 0),
                ProjectCreativeSQLite.columnString(statement, 1),
                ProjectCreativeSQLite.columnString(statement, 2)
            )
        }
        guard let state = stateRows.first else { return nil }

        let mediaByMessageId = try lensMessageMediaByMessageId(projectId: project.projectId, connection: connection)
        let messages = try ProjectCreativeSQLite.query(
            connection,
            sql: """
            SELECT message_id, role, text, target_scratch_id, target_lens_id, created_at
            FROM project_lens_messages
            WHERE project_id = ?
            ORDER BY message_order ASC;
            """,
            bindings: [project.projectId],
            context: context
        ) { statement in
            let messageId = ProjectCreativeSQLite.columnString(statement, 0)
            return ProjectLensMessage(
                messageId: messageId,
                role: ProjectLensMessageRole(rawValue: ProjectCreativeSQLite.columnString(statement, 1)) ?? .user,
                text: ProjectCreativeSQLite.columnString(statement, 2),
                targetScratchId: ProjectCreativeSQLite.optionalColumnString(statement, 3),
                targetLensId: ProjectCreativeSQLite.optionalColumnString(statement, 4),
                mediaIds: mediaByMessageId[messageId] ?? [],
                createdAt: ProjectCreativeSQLite.columnString(statement, 5)
            )
        }

        // Only ONE version's lens is ever read — `document.lenses` resolves to
        // `activeVersion` — so decoding every version's payload meant ~11 MB of
        // JSON on the main actor at project open for a saturated project. Find
        // which version to hydrate from a payload-free presence query first.
        let hydrationTargetId = try lensHydrationTargetVersionId(
            projectId: project.projectId,
            activeVersionId: state.1,
            connection: connection
        )
        var skippedVersionIds: Set<String> = []
        let versions = try ProjectCreativeSQLite.query(
            connection,
            sql: """
            SELECT version_id, turn_index, selected_lens_id, selected_scratch_id,
                   change_summary, created_at, model
            FROM project_lens_versions
            WHERE project_id = ?
            ORDER BY version_order ASC;
            """,
            bindings: [project.projectId],
            context: context
        ) { statement in
            let versionId = ProjectCreativeSQLite.columnString(statement, 0)
            let hydrate = versionId == hydrationTargetId
            if !hydrate {
                skippedVersionIds.insert(versionId)
            }
            return ProjectLensSetVersion(
                versionId: versionId,
                turnIndex: Int(sqlite3_column_int(statement, 1)),
                lenses: hydrate ? try versionLenses(versionId: versionId, connection: connection) : [],
                scratchDrafts: try versionScratchDrafts(versionId: versionId, connection: connection),
                selectedLensId: ProjectCreativeSQLite.optionalColumnString(statement, 2),
                selectedScratchId: ProjectCreativeSQLite.optionalColumnString(statement, 3),
                changeSummary: ProjectCreativeSQLite.columnString(statement, 4),
                createdAt: ProjectCreativeSQLite.columnString(statement, 5),
                model: ProjectCreativeSQLite.columnString(statement, 6)
            )
        }

        let lensEditMessages = try loadLensEditMessages(projectId: project.projectId, connection: connection)
        let lensBodyVersions = try loadLensBodyVersions(projectId: project.projectId, connection: connection)

        var document = ProjectLensSetDocument(
            schemaVersion: state.0.trimmed.isEmpty ? ProjectLensSetDocument.schemaVersion : state.0,
            projectId: project.projectId,
            messages: messages,
            lensEditMessages: lensEditMessages,
            lensBodyVersions: lensBodyVersions,
            versions: versions,
            activeVersionId: state.1,
            updatedAt: state.2
        )
        // Declared AFTER init on purpose: init runs canonicalization, which must
        // see the fully-hydrated reading for the one version it can judge. From
        // here on the set protects the untouched versions from being rewritten.
        document.versionIdsWithoutLoadedLenses = skippedVersionIds
        return document
    }

    /// Persists the document by writing only what changed.
    ///
    /// This used to `DELETE FROM project_lens_state`, whose cascade wiped every
    /// version, lens snapshot, term, ingredient and hero-image row, and then
    /// re-inserted all of it. Because a version payload embeds the whole lens
    /// (including its accumulating `heroImages`), a saturated project rewrote
    /// ~11 MB of JSON plus ~2,275 satellite rows on EVERY save — and
    /// `saveLensHeroImages` saves on every hero image that lands.
    ///
    /// The diff is exact, not heuristic: `project_lens_versions` already stores
    /// a `content_fingerprint` (sha256 over the encoded version, including its
    /// lenses), so an unchanged version is recognised without reading its
    /// payload back. Only versions whose fingerprint differs are rewritten.
    private func replaceLenses(
        _ document: ProjectLensSetDocument,
        project: ProjectRecord,
        connection: OpaquePointer
    ) throws {
        // Upsert rather than delete: deleting this row is what triggered the
        // cascade that made every save a full rewrite.
        try ProjectCreativeSQLite.execute(
            """
            INSERT INTO project_lens_state (
                project_id, schema_version, active_version_id, updated_at
            ) VALUES (?, ?, ?, ?)
            ON CONFLICT(project_id) DO UPDATE SET
                schema_version = excluded.schema_version,
                active_version_id = excluded.active_version_id,
                updated_at = excluded.updated_at;
            """,
            connection: connection,
            bindings: [project.projectId, document.schemaVersion, document.activeVersionId, document.updatedAt],
            context: context
        )

        // Small collections stay a straight replace — they carry no payloads.
        // They must be deleted explicitly now that the state cascade is gone.
        try ProjectCreativeSQLite.execute(
            "DELETE FROM project_lens_messages WHERE project_id = ?;",
            connection: connection,
            bindings: [project.projectId],
            context: context
        )
        for (messageOrder, message) in document.messages.enumerated() {
            try insertLensMessage(message, order: messageOrder, projectId: project.projectId, connection: connection)
        }

        try syncLensVersions(document, project: project, connection: connection)

        try ProjectCreativeSQLite.execute(
            "DELETE FROM project_lens_edit_messages WHERE project_id = ?;",
            connection: connection,
            bindings: [project.projectId],
            context: context
        )
        for (messageOrder, message) in document.lensEditMessages.enumerated() {
            try insertLensEditMessage(message, order: messageOrder, projectId: project.projectId, connection: connection)
        }

        // Body versions come last on purpose: they also cascade from
        // `project_lens_version_lenses`, so rewriting a version above can take
        // its body-version rows with it. Re-inserting from the document heals that.
        try ProjectCreativeSQLite.execute(
            "DELETE FROM project_lens_body_versions WHERE project_id = ?;",
            connection: connection,
            bindings: [project.projectId],
            context: context
        )
        for (versionOrder, version) in document.lensBodyVersions.enumerated() {
            try insertLensBodyVersion(version, order: versionOrder, projectId: project.projectId, connection: connection)
        }
    }

    private struct StoredLensVersionRow {
        var fingerprint: String
        var order: Int
    }

    /// Brings `project_lens_versions` (and everything cascading from it) in line
    /// with the document, touching only rows that actually differ.
    private func syncLensVersions(
        _ document: ProjectLensSetDocument,
        project: ProjectRecord,
        connection: OpaquePointer
    ) throws {
        var stored: [String: StoredLensVersionRow] = [:]
        _ = try ProjectCreativeSQLite.query(
            connection,
            sql: """
            SELECT version_id, content_fingerprint, version_order
            FROM project_lens_versions WHERE project_id = ?;
            """,
            bindings: [project.projectId],
            context: context
        ) { statement -> Bool in
            stored[ProjectCreativeSQLite.columnString(statement, 0)] = StoredLensVersionRow(
                fingerprint: ProjectCreativeSQLite.columnString(statement, 1),
                order: Int(sqlite3_column_int(statement, 2))
            )
            return true
        }

        let desiredIds = Set(document.versions.map(\.versionId))
        // Dropped versions first — the 35-version cap prunes from the front, so
        // this also frees the low `version_order` slots the survivors shift into.
        for versionId in stored.keys where !desiredIds.contains(versionId) {
            try ProjectCreativeSQLite.execute(
                "DELETE FROM project_lens_versions WHERE version_id = ?;",
                connection: connection,
                bindings: [versionId],
                context: context
            )
            stored[versionId] = nil
        }

        // Ascending order matters: `UNIQUE(project_id, version_order)` means a
        // slot must be vacated before it is claimed, and every shift is
        // downward, so processing low-to-high always finds its target free.
        for (versionOrder, version) in document.versions.enumerated() {
            // A version the loader skipped cannot have been edited, and its
            // in-memory `lenses` is empty only because nobody read it —
            // rewriting from that would erase the stored snapshot. Only its
            // position may need fixing, which is payload-free.
            //
            // `versionIdsWithoutLoadedLenses` names skipped rows explicitly, so
            // a version appended after the load (generating a frame does this)
            // is correctly treated as fully in memory. Naming the hydrated side
            // instead made new versions look unloaded and blocked the save.
            if document.versionIdsWithoutLoadedLenses.contains(version.versionId) {
                guard let existing = stored[version.versionId] else { continue }
                guard existing.order != versionOrder else { continue }
                try ProjectCreativeSQLite.execute(
                    "UPDATE project_lens_versions SET version_order = ? WHERE version_id = ?;",
                    connection: connection,
                    bindings: [versionOrder, version.versionId],
                    context: context
                )
                continue
            }
            let fingerprint = sha256Hex(try JSONCoding.encoder.encode(version))
            if let existing = stored[version.versionId], existing.fingerprint == fingerprint {
                guard existing.order != versionOrder else { continue }
                try ProjectCreativeSQLite.execute(
                    "UPDATE project_lens_versions SET version_order = ? WHERE version_id = ?;",
                    connection: connection,
                    bindings: [versionOrder, version.versionId],
                    context: context
                )
                continue
            }
            // Changed or new. Deleting first clears the lens snapshots, terms,
            // ingredients, hero images and swatches hanging off this version.
            if stored[version.versionId] != nil {
                try ProjectCreativeSQLite.execute(
                    "DELETE FROM project_lens_versions WHERE version_id = ?;",
                    connection: connection,
                    bindings: [version.versionId],
                    context: context
                )
            }
            try insertLensVersion(version, order: versionOrder, projectId: project.projectId, connection: connection)
        }
    }

    private func insertLensMessage(
        _ message: ProjectLensMessage,
        order: Int,
        projectId: String,
        connection: OpaquePointer
    ) throws {
        try ProjectCreativeSQLite.execute(
            """
            INSERT INTO project_lens_messages (
                message_id, project_id, message_order, role, text, target_scratch_id, target_lens_id, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
            """,
            connection: connection,
            bindings: [
                message.messageId,
                projectId,
                order,
                message.role.rawValue,
                message.text,
                message.targetScratchId,
                message.targetLensId,
                message.createdAt
            ],
            context: context
        )
        for (mediaOrder, mediaId) in message.mediaIds.enumerated() {
            try ProjectCreativeSQLite.execute(
                """
                INSERT INTO project_lens_message_media (
                    message_id, media_order, media_id
                ) VALUES (?, ?, ?);
                """,
                connection: connection,
                bindings: [message.messageId, mediaOrder, mediaId],
                context: context
            )
        }
    }

    private func insertLensEditMessage(
        _ message: ProjectLensEditMessage,
        order: Int,
        projectId: String,
        connection: OpaquePointer
    ) throws {
        let normalized = message.normalized()
        guard !normalized.messageId.isEmpty, !normalized.lensId.isEmpty else { return }
        try ProjectCreativeSQLite.execute(
            """
            INSERT INTO project_lens_edit_messages (
                message_id, project_id, lens_id, message_order, role, text, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?);
            """,
            connection: connection,
            bindings: [
                normalized.messageId,
                projectId,
                normalized.lensId,
                order,
                normalized.role.rawValue,
                normalized.text,
                normalized.createdAt
            ],
            context: context
        )
        for (mediaOrder, mediaId) in normalized.mediaIds.enumerated() {
            try ProjectCreativeSQLite.execute(
                """
                INSERT INTO project_lens_edit_message_media (
                    message_id, media_order, media_id
                ) VALUES (?, ?, ?);
                """,
                connection: connection,
                bindings: [normalized.messageId, mediaOrder, mediaId],
                context: context
            )
        }
    }

    private func insertLensBodyVersion(
        _ version: ProjectLensBodyVersion,
        order: Int,
        projectId: String,
        connection: OpaquePointer
    ) throws {
        let normalized = version.normalized()
        guard !normalized.versionId.isEmpty,
              !normalized.lensId.isEmpty,
              !normalized.sourceLensSetVersionId.isEmpty
        else {
            return
        }
        try ProjectCreativeSQLite.execute(
            """
            INSERT INTO project_lens_body_versions (
                version_id, project_id, lens_id, version_order, source_lens_set_version_id,
                turn_index, change_summary, model, created_at, content_fingerprint, is_active
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            connection: connection,
            bindings: [
                normalized.versionId,
                projectId,
                normalized.lensId,
                order,
                normalized.sourceLensSetVersionId,
                normalized.turnIndex,
                normalized.changeSummary,
                normalized.model,
                normalized.createdAt,
                normalized.contentFingerprint,
                normalized.isActive
            ],
            context: context
        )
    }

    private func insertLensVersion(
        _ version: ProjectLensSetVersion,
        order: Int,
        projectId: String,
        connection: OpaquePointer
    ) throws {
        let fingerprint = sha256Hex(try JSONCoding.encoder.encode(version))
        try ProjectCreativeSQLite.execute(
            """
            INSERT INTO project_lens_versions (
                version_id, project_id, version_order, turn_index, selected_lens_id,
                selected_scratch_id, change_summary, model, created_at, content_fingerprint
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            connection: connection,
            bindings: [
                version.versionId,
                projectId,
                order,
                version.turnIndex,
                version.selectedLensId,
                version.selectedScratchId,
                version.changeSummary,
                version.model,
                version.createdAt,
                fingerprint
            ],
            context: context
        )
        for (lensOrder, lens) in version.lenses.enumerated() {
            try insertLensSnapshot(lens.normalized(), versionId: version.versionId, order: lensOrder, connection: connection)
        }
        for (scratchOrder, scratch) in version.scratchDrafts.enumerated() {
            try insertScratchDraft(scratch.normalized(), versionId: version.versionId, order: scratchOrder, connection: connection)
        }
    }

    private func insertLensSnapshot(
        _ lens: ProjectLens,
        versionId: String,
        order: Int,
        connection: OpaquePointer
    ) throws {
        let payload = try ProjectCreativeSQLite.jsonString(lens)
        try ProjectCreativeSQLite.execute(
            """
            INSERT INTO project_lens_version_lenses (
                version_id, lens_id, lens_order, status, enabled, title, claim, visual_summary,
                generation_run_id, generation_phase, generation_error, created_at, updated_at, payload_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            connection: connection,
            bindings: [
                versionId,
                lens.lensId,
                order,
                lens.status.rawValue,
                lens.enabled,
                lens.body.title,
                lens.body.claim,
                lens.body.visualSummary,
                lens.generationRunId,
                lens.generationPhase,
                lens.generationError,
                lens.createdAt,
                lens.updatedAt,
                payload
            ],
            context: context
        )
        try insertLensTerms(lens.body.paletteTerms, versionId: versionId, lensId: lens.lensId, termKind: "palette_terms", connection: connection)
        try insertLensTerms(lens.body.motifTerms, versionId: versionId, lensId: lens.lensId, termKind: "motif_terms", connection: connection)
        try insertLensTerms(lens.body.textureMaterialTerms, versionId: versionId, lensId: lens.lensId, termKind: "texture_material_terms", connection: connection)
        try insertLensTerms(lens.body.compositionTerms, versionId: versionId, lensId: lens.lensId, termKind: "composition_terms", connection: connection)
        try insertLensTerms(lens.body.pacingEnergyTerms, versionId: versionId, lensId: lens.lensId, termKind: "pacing_energy_terms", connection: connection)
        try insertLensTerms(lens.body.mustPreserve, versionId: versionId, lensId: lens.lensId, termKind: "must_preserve", connection: connection)
        try insertLensTerms(lens.body.mustAvoid, versionId: versionId, lensId: lens.lensId, termKind: "must_avoid", connection: connection)
        try insertLensTerms(lens.body.referenceMediaIds, versionId: versionId, lensId: lens.lensId, termKind: "reference_media_ids", connection: connection)
        try insertLensTerms(lens.body.openQuestions, versionId: versionId, lensId: lens.lensId, termKind: "open_questions", connection: connection)
        try insertLensTerms(lens.body.derivedVirtues, versionId: versionId, lensId: lens.lensId, termKind: "derived_virtues", connection: connection)
        try insertColorSwatches(lens.body.colorPalette, versionId: versionId, lensId: lens.lensId, connection: connection)
        for ingredient in lens.body.styleIngredients {
            try insertStyleIngredient(ingredient, versionId: versionId, lensId: lens.lensId, connection: connection)
        }
        for (imageOrder, image) in lens.sortedHeroImages.enumerated() {
            try insertHeroImage(image, versionId: versionId, lensId: lens.lensId, order: imageOrder, connection: connection)
        }
    }

    private func insertScratchDraft(
        _ scratch: LensScratchDraft,
        versionId: String,
        order: Int,
        connection: OpaquePointer
    ) throws {
        try ProjectCreativeSQLite.execute(
            """
            INSERT INTO project_lens_scratch_drafts (
                version_id, scratch_id, scratch_order, title, claim, visual_summary, created_at, updated_at, payload_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            connection: connection,
            bindings: [
                versionId,
                scratch.scratchId,
                order,
                scratch.body.title,
                scratch.body.claim,
                scratch.body.visualSummary,
                scratch.createdAt,
                scratch.updatedAt,
                try ProjectCreativeSQLite.jsonString(scratch)
            ],
            context: context
        )
    }

    private func insertLensTerms(
        _ values: [String],
        versionId: String,
        lensId: String,
        termKind: String,
        connection: OpaquePointer
    ) throws {
        for (itemOrder, value) in uniqueNonEmpty(values).enumerated() {
            try ProjectCreativeSQLite.execute(
                """
                INSERT INTO project_lens_terms (
                    version_id, lens_id, term_kind, item_order, value
                ) VALUES (?, ?, ?, ?, ?);
                """,
                connection: connection,
                bindings: [versionId, lensId, termKind, itemOrder, value],
                context: context
            )
        }
    }

    private func insertColorSwatches(
        _ swatches: [LensColorSwatch],
        versionId: String,
        lensId: String,
        connection: OpaquePointer
    ) throws {
        for (swatchOrder, swatch) in uniqueLensColorSwatches(swatches).enumerated() {
            try ProjectCreativeSQLite.execute(
                """
                INSERT INTO project_lens_color_swatches (
                    version_id, lens_id, swatch_order, name, hex, role, note
                ) VALUES (?, ?, ?, ?, ?, ?, ?);
                """,
                connection: connection,
                bindings: [
                    versionId,
                    lensId,
                    swatchOrder,
                    swatch.name,
                    swatch.hex,
                    swatch.role,
                    swatch.note
                ],
                context: context
            )
        }
    }

    private func insertStyleIngredient(
        _ ingredient: LensStyleIngredient,
        versionId: String,
        lensId: String,
        connection: OpaquePointer
    ) throws {
        try ProjectCreativeSQLite.execute(
            """
            INSERT INTO project_lens_style_ingredients (
                version_id, lens_id, ingredient_id, ingredient_order, enabled, title, role,
                narrative_use, presentation_use, notes, source_recipe_id, source_recipe_version, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            connection: connection,
            bindings: [
                versionId,
                lensId,
                ingredient.ingredientId,
                ingredient.order,
                ingredient.enabled,
                ingredient.title,
                ingredient.role,
                ingredient.narrativeUse,
                ingredient.presentationUse,
                ingredient.notes,
                ingredient.sourceRecipeId,
                ingredient.sourceRecipeVersion,
                ingredient.updatedAt
            ],
            context: context
        )
        try insertIngredientTerms(ingredient.paletteTerms, versionId: versionId, lensId: lensId, ingredientId: ingredient.ingredientId, termKind: "palette_terms", connection: connection)
        try insertIngredientTerms(ingredient.motifTerms, versionId: versionId, lensId: lensId, ingredientId: ingredient.ingredientId, termKind: "motif_terms", connection: connection)
        try insertIngredientTerms(ingredient.avoidTerms, versionId: versionId, lensId: lensId, ingredientId: ingredient.ingredientId, termKind: "avoid_terms", connection: connection)
        try insertIngredientTerms(ingredient.referenceAestheticIds, versionId: versionId, lensId: lensId, ingredientId: ingredient.ingredientId, termKind: "reference_aesthetic_ids", connection: connection)
        try insertIngredientTerms(ingredient.sourceReferenceIds, versionId: versionId, lensId: lensId, ingredientId: ingredient.ingredientId, termKind: "source_reference_ids", connection: connection)
    }

    private func insertIngredientTerms(
        _ values: [String],
        versionId: String,
        lensId: String,
        ingredientId: String,
        termKind: String,
        connection: OpaquePointer
    ) throws {
        for (itemOrder, value) in uniqueNonEmpty(values).enumerated() {
            try ProjectCreativeSQLite.execute(
                """
                INSERT INTO project_lens_ingredient_terms (
                    version_id, lens_id, ingredient_id, term_kind, item_order, value
                ) VALUES (?, ?, ?, ?, ?, ?);
                """,
                connection: connection,
                bindings: [versionId, lensId, ingredientId, termKind, itemOrder, value],
                context: context
            )
        }
    }

    private func insertHeroImage(
        _ image: ProjectLensHeroImage,
        versionId: String,
        lensId: String,
        order: Int,
        connection: OpaquePointer
    ) throws {
        let image = image.normalized()
        let renderVersion = image.renderVersion?.normalized()
        try ProjectCreativeSQLite.execute(
            """
            INSERT INTO project_lens_hero_images (
                version_id, lens_id, image_order, image_index, provider, status, image_path,
                prompt, generated_at, updated_at, render_version_id, render_target_id,
                render_stack_fingerprint, render_version_group_id, version_number, seed,
                final_prompt_fingerprint, render_params_fingerprint, is_active_render_version, payload_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            connection: connection,
            bindings: [
                versionId,
                lensId,
                order,
                image.imageIndex,
                image.provider,
                image.status,
                image.imagePath,
                image.prompt,
                image.generatedAt,
                image.updatedAt,
                renderVersion?.renderVersionId ?? "",
                renderVersion?.renderTargetId ?? "",
                renderVersion?.renderStackFingerprint ?? "",
                renderVersion?.renderVersionGroupId ?? "",
                renderVersion?.versionNumber ?? 0,
                renderVersion?.seed ?? "",
                renderVersion?.finalPromptFingerprint ?? "",
                renderVersion?.renderParamsFingerprint ?? "",
                renderVersion?.isActive == true ? 1 : 0,
                try ProjectCreativeSQLite.jsonString(image)
            ],
            context: context
        )
    }

    /// Which single version's lens snapshot is worth decoding.
    ///
    /// The active version, when it actually holds a lens. Otherwise the newest
    /// version that does — which is precisely the fallback
    /// `canonicalizeToSingleLens` applies (`versions.last(where: { !$0.lenses.isEmpty })`),
    /// so hydrating it keeps the canonical-lens pick and the active-version
    /// reassignment identical to a full load. Reads `version_order` and ids
    /// only; no `payload_json` is touched.
    private func lensHydrationTargetVersionId(
        projectId: String,
        activeVersionId: String,
        connection: OpaquePointer
    ) throws -> String? {
        let lensBearing = try ProjectCreativeSQLite.query(
            connection,
            sql: """
            SELECT v.version_id
            FROM project_lens_versions v
            JOIN project_lens_version_lenses l ON l.version_id = v.version_id
            WHERE v.project_id = ?
            ORDER BY v.version_order ASC;
            """,
            bindings: [projectId],
            context: context
        ) { statement in
            ProjectCreativeSQLite.columnString(statement, 0)
        }
        if lensBearing.contains(activeVersionId) {
            return activeVersionId
        }
        return lensBearing.last
    }

    private func versionLenses(versionId: String, connection: OpaquePointer) throws -> [ProjectLens] {
        try ProjectCreativeSQLite.query(
            connection,
            sql: """
            SELECT lens_id, payload_json FROM project_lens_version_lenses
            WHERE version_id = ?
            ORDER BY lens_order ASC;
            """,
            bindings: [versionId],
            context: context
        ) { statement in
            let lensId = ProjectCreativeSQLite.columnString(statement, 0)
            var lens = try ProjectCreativeSQLite.decodeJSON(
                ProjectLens.self,
                from: ProjectCreativeSQLite.columnString(statement, 1)
            ).normalized()
            let swatches = try lensColorSwatches(versionId: versionId, lensId: lensId, connection: connection)
            if !swatches.isEmpty {
                lens.body.colorPalette = swatches
            }
            return lens.normalized()
        }
    }

    private func lensColorSwatches(
        versionId: String,
        lensId: String,
        connection: OpaquePointer
    ) throws -> [LensColorSwatch] {
        try ProjectCreativeSQLite.query(
            connection,
            sql: """
            SELECT name, hex, role, note
            FROM project_lens_color_swatches
            WHERE version_id = ? AND lens_id = ?
            ORDER BY swatch_order ASC;
            """,
            bindings: [versionId, lensId],
            context: context
        ) { statement in
            LensColorSwatch(
                name: ProjectCreativeSQLite.columnString(statement, 0),
                hex: ProjectCreativeSQLite.columnString(statement, 1),
                role: ProjectCreativeSQLite.columnString(statement, 2),
                note: ProjectCreativeSQLite.columnString(statement, 3)
            ).normalized()
        }
    }

    private func versionScratchDrafts(versionId: String, connection: OpaquePointer) throws -> [LensScratchDraft] {
        try ProjectCreativeSQLite.query(
            connection,
            sql: """
            SELECT payload_json FROM project_lens_scratch_drafts
            WHERE version_id = ?
            ORDER BY scratch_order ASC;
            """,
            bindings: [versionId],
            context: context
        ) { statement in
            try ProjectCreativeSQLite.decodeJSON(
                LensScratchDraft.self,
                from: ProjectCreativeSQLite.columnString(statement, 0)
            ).normalized()
        }
    }

    private func lensMessageMediaByMessageId(
        projectId: String,
        connection: OpaquePointer
    ) throws -> [String: [String]] {
        let rows = try ProjectCreativeSQLite.query(
            connection,
            sql: """
            SELECT m.message_id, mm.media_id
            FROM project_lens_messages m
            JOIN project_lens_message_media mm ON mm.message_id = m.message_id
            WHERE m.project_id = ?
            ORDER BY m.message_order ASC, mm.media_order ASC;
            """,
            bindings: [projectId],
            context: context
        ) { statement in
            (
                ProjectCreativeSQLite.columnString(statement, 0),
                ProjectCreativeSQLite.columnString(statement, 1)
            )
        }
        return Dictionary(grouping: rows, by: { $0.0 }).mapValues { rows in
            rows.map { $0.1 }
        }
    }

    private func loadLensEditMessages(
        projectId: String,
        connection: OpaquePointer
    ) throws -> [ProjectLensEditMessage] {
        let mediaByMessageId = try lensEditMessageMediaByMessageId(projectId: projectId, connection: connection)
        return try ProjectCreativeSQLite.query(
            connection,
            sql: """
            SELECT message_id, lens_id, role, text, created_at
            FROM project_lens_edit_messages
            WHERE project_id = ?
            ORDER BY lens_id ASC, message_order ASC;
            """,
            bindings: [projectId],
            context: context
        ) { statement in
            let messageId = ProjectCreativeSQLite.columnString(statement, 0)
            return ProjectLensEditMessage(
                messageId: messageId,
                lensId: ProjectCreativeSQLite.columnString(statement, 1),
                role: ProjectLensMessageRole(rawValue: ProjectCreativeSQLite.columnString(statement, 2)) ?? .user,
                text: ProjectCreativeSQLite.columnString(statement, 3),
                mediaIds: mediaByMessageId[messageId] ?? [],
                createdAt: ProjectCreativeSQLite.columnString(statement, 4)
            ).normalized()
        }
    }

    private func loadLensBodyVersions(
        projectId: String,
        connection: OpaquePointer
    ) throws -> [ProjectLensBodyVersion] {
        try ProjectCreativeSQLite.query(
            connection,
            sql: """
            SELECT version_id, lens_id, source_lens_set_version_id, turn_index,
                   change_summary, model, created_at, content_fingerprint, is_active
            FROM project_lens_body_versions
            WHERE project_id = ?
            ORDER BY lens_id ASC, version_order ASC;
            """,
            bindings: [projectId],
            context: context
        ) { statement in
            ProjectLensBodyVersion(
                versionId: ProjectCreativeSQLite.columnString(statement, 0),
                lensId: ProjectCreativeSQLite.columnString(statement, 1),
                sourceLensSetVersionId: ProjectCreativeSQLite.columnString(statement, 2),
                turnIndex: Int(sqlite3_column_int(statement, 3)),
                changeSummary: ProjectCreativeSQLite.columnString(statement, 4),
                model: ProjectCreativeSQLite.columnString(statement, 5),
                createdAt: ProjectCreativeSQLite.columnString(statement, 6),
                contentFingerprint: ProjectCreativeSQLite.columnString(statement, 7),
                isActive: sqlite3_column_int(statement, 8) == 1
            ).normalized()
        }
    }

    private func lensEditMessageMediaByMessageId(
        projectId: String,
        connection: OpaquePointer
    ) throws -> [String: [String]] {
        let rows = try ProjectCreativeSQLite.query(
            connection,
            sql: """
            SELECT m.message_id, mm.media_id
            FROM project_lens_edit_messages m
            JOIN project_lens_edit_message_media mm ON mm.message_id = m.message_id
            WHERE m.project_id = ?
            ORDER BY m.lens_id ASC, m.message_order ASC, mm.media_order ASC;
            """,
            bindings: [projectId],
            context: context
        ) { statement in
            (
                ProjectCreativeSQLite.columnString(statement, 0),
                ProjectCreativeSQLite.columnString(statement, 1)
            )
        }
        return Dictionary(grouping: rows, by: { $0.0 }).mapValues { rows in
            rows.map { $0.1 }
        }
    }
}
