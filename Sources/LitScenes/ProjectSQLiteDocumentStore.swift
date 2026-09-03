import Foundation
import SQLite3

struct ProjectDocumentBatchWrite {
    var data: Data
    var documentType: String
    var documentId: String = "default"
}

struct ProjectSQLiteDocumentStore {
    private static let queue = DispatchQueue(label: "local.litscenes.project-document-store")

    let projectLibrary: ProjectLibrary

    init(projectLibrary: ProjectLibrary = ProjectLibrary()) {
        self.projectLibrary = projectLibrary
    }

    func loadDocument<T: Decodable>(
        _ type: T.Type,
        for project: ProjectRecord,
        documentType: String,
        documentId: String = "default"
    ) throws -> T? {
        try withConnection(project, readOnly: true) { connection in
            let sql = """
            SELECT payload_json FROM project_documents
            WHERE project_id = ? AND document_type = ? AND document_id = ?
            LIMIT 1;
            """
            guard let json = try optionalString(connection, sql: sql, bindings: [project.projectId, documentType, documentId]) else {
                return nil
            }
            return try JSONCoding.decoder.decode(T.self, from: Data(json.utf8))
        }
    }

    func loadDocumentData(
        for project: ProjectRecord,
        documentType: String,
        documentId: String = "default"
    ) throws -> Data? {
        try withConnection(project, readOnly: true) { connection in
            let sql = """
            SELECT payload_json FROM project_documents
            WHERE project_id = ? AND document_type = ? AND document_id = ?
            LIMIT 1;
            """
            guard let json = try optionalString(connection, sql: sql, bindings: [project.projectId, documentType, documentId]) else {
                return nil
            }
            return Data(json.utf8)
        }
    }

    func loadDocuments<T: Decodable>(
        _ type: T.Type,
        for project: ProjectRecord,
        documentType: String
    ) throws -> [T] {
        try withConnection(project, readOnly: true) { connection in
            let sql = """
            SELECT payload_json FROM project_documents
            WHERE project_id = ? AND document_type = ?
            ORDER BY updated_at DESC, document_id ASC;
            """
            return try queryStrings(connection, sql: sql, bindings: [project.projectId, documentType])
                .map { try JSONCoding.decoder.decode(T.self, from: Data($0.utf8)) }
        }
    }

    func saveDocument<T: Encodable>(
        _ value: T,
        for project: ProjectRecord,
        documentType: String,
        documentId: String = "default"
    ) throws {
        try saveDocumentData(
            try JSONCoding.encoder.encode(value),
            for: project,
            documentType: documentType,
            documentId: documentId
        )
    }

    func saveDocumentData(
        _ data: Data,
        for project: ProjectRecord,
        documentType: String,
        documentId: String = "default"
    ) throws {
        let json = String(decoding: data, as: UTF8.self)
        let schemaVersion = schemaVersion(from: data)
        let now = DateFormats.now()
        try Self.queue.sync {
            try withConnection(project, readOnly: false) { connection in
                try writeDocumentData(
                    data,
                    json: json,
                    schemaVersion: schemaVersion,
                    for: project,
                    documentType: documentType,
                    documentId: documentId,
                    now: now,
                    connection: connection
                )
            }
        }
    }

    /// Commits related canonical documents through one SQLite connection and
    /// one transaction. A failed second write rolls the first back, so the
    /// timeline and Stage grouping can never disagree after a combine.
    func saveDocumentsAtomically(
        _ writes: [ProjectDocumentBatchWrite],
        for project: ProjectRecord
    ) throws {
        guard !writes.isEmpty else { return }
        let now = DateFormats.now()
        try Self.queue.sync {
            try withConnection(project, readOnly: false) { connection in
                try execute("BEGIN IMMEDIATE;", connection: connection, bindings: [])
                do {
                    for write in writes {
                        guard !write.documentType.trimmed.isEmpty,
                              !write.documentId.trimmed.isEmpty else {
                            throw ScreenGraphError.capture("Project document batch contains an empty identity.")
                        }
                        try writeDocumentData(
                            write.data,
                            json: String(decoding: write.data, as: UTF8.self),
                            schemaVersion: schemaVersion(from: write.data),
                            for: project,
                            documentType: write.documentType,
                            documentId: write.documentId,
                            now: now,
                            connection: connection
                        )
                    }
                    try execute("COMMIT;", connection: connection, bindings: [])
                } catch {
                    try? execute("ROLLBACK;", connection: connection, bindings: [])
                    throw error
                }
            }
        }
    }

    func documentExists(
        for project: ProjectRecord,
        documentType: String,
        documentId: String = "default"
    ) -> Bool {
        (try? withConnection(project, readOnly: true) { connection in
            let sql = """
            SELECT 1 FROM project_documents
            WHERE project_id = ? AND document_type = ? AND document_id = ?
            LIMIT 1;
            """
            return try optionalString(connection, sql: sql, bindings: [project.projectId, documentType, documentId]) != nil
        }) ?? false
    }

    func deleteDocument(
        for project: ProjectRecord,
        documentType: String,
        documentId: String = "default"
    ) throws {
        try Self.queue.sync {
            try withConnection(project, readOnly: false) { connection in
                let sql = """
                DELETE FROM project_documents
                WHERE project_id = ? AND document_type = ? AND document_id = ?;
                """
                try execute(sql, connection: connection, bindings: [project.projectId, documentType, documentId])
            }
        }
    }

    func deleteDocuments(for project: ProjectRecord, documentTypes: [String]) throws {
        guard !documentTypes.isEmpty else { return }
        try Self.queue.sync {
            try withConnection(project, readOnly: false) { connection in
                for documentType in documentTypes {
                    try execute(
                        "DELETE FROM project_documents WHERE project_id = ? AND document_type = ?;",
                        connection: connection,
                        bindings: [project.projectId, documentType]
                    )
                }
            }
        }
    }

    private func withConnection<T>(
        _ project: ProjectRecord,
        readOnly: Bool,
        _ body: (OpaquePointer) throws -> T
    ) throws -> T {
        let url = try LitScenesDesktopDatabase.prepareProjectDatabase(for: project, projectLibrary: projectLibrary)
        let flags = readOnly ? SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX : SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        return try LitScenesDesktopDatabase.withConnection(url: url, flags: flags, context: "Project document DB", body)
    }

    private func schemaVersion(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ""
        }
        if let value = object["schema_version"] as? String {
            return value
        }
        if let value = object["schemaVersion"] as? String {
            return value
        }
        return ""
    }

    private func writeDocumentData(
        _ data: Data,
        json: String,
        schemaVersion: String,
        for project: ProjectRecord,
        documentType: String,
        documentId: String,
        now: String,
        connection: OpaquePointer
    ) throws {
        let sql = """
        INSERT INTO project_documents (
            project_id, document_type, document_id, schema_version, payload_json,
            content_fingerprint, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(project_id, document_type, document_id) DO UPDATE SET
            schema_version = excluded.schema_version,
            payload_json = excluded.payload_json,
            content_fingerprint = excluded.content_fingerprint,
            updated_at = excluded.updated_at,
            record_revision = project_documents.record_revision + 1;
        """
        try execute(sql, connection: connection, bindings: [
            project.projectId,
            documentType,
            documentId,
            schemaVersion,
            json,
            sha256Hex(data),
            now,
            now
        ])
    }

    private func execute(_ sql: String, connection: OpaquePointer, bindings: [String]) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ScreenGraphError.capture("Project document DB prepare failed: \(litScenesSQLiteMessage(connection))")
        }
        defer { sqlite3_finalize(statement) }
        for (index, value) in bindings.enumerated() {
            litScenesSQLiteBindText(value, to: Int32(index + 1), in: statement)
        }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw ScreenGraphError.capture("Project document DB step failed: \(litScenesSQLiteMessage(connection))")
        }
    }

    private func optionalString(_ connection: OpaquePointer, sql: String, bindings: [String]) throws -> String? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ScreenGraphError.capture("Project document DB query prepare failed: \(litScenesSQLiteMessage(connection))")
        }
        defer { sqlite3_finalize(statement) }
        for (index, value) in bindings.enumerated() {
            litScenesSQLiteBindText(value, to: Int32(index + 1), in: statement)
        }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return litScenesSQLiteColumnText(statement, 0)
    }

    private func queryStrings(_ connection: OpaquePointer, sql: String, bindings: [String]) throws -> [String] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ScreenGraphError.capture("Project document DB query prepare failed: \(litScenesSQLiteMessage(connection))")
        }
        defer { sqlite3_finalize(statement) }
        for (index, value) in bindings.enumerated() {
            litScenesSQLiteBindText(value, to: Int32(index + 1), in: statement)
        }
        var output: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            output.append(litScenesSQLiteColumnText(statement, 0))
        }
        return output
    }
}
