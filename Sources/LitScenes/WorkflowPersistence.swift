import Foundation
import SQLite3

extension InferenceTraceStore {
    func migrateWorkflowStorage() throws {
        try workflowSQL("""
        CREATE TABLE IF NOT EXISTS workflow_migrations (version INTEGER PRIMARY KEY);
        CREATE TABLE IF NOT EXISTS workflow_jobs (
            job_id TEXT PRIMARY KEY, project_id TEXT NOT NULL, updated_at TEXT NOT NULL,
            state TEXT NOT NULL, payload_json TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS workflow_events (
            event_id TEXT PRIMARY KEY, job_id TEXT NOT NULL, created_at TEXT NOT NULL,
            payload_json TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS workflow_jobs_project_updated ON workflow_jobs(project_id, updated_at DESC);
        CREATE INDEX IF NOT EXISTS workflow_jobs_state_updated ON workflow_jobs(state, updated_at DESC);
        CREATE INDEX IF NOT EXISTS workflow_events_job_created ON workflow_events(job_id, created_at);
        INSERT OR IGNORE INTO workflow_migrations(version) VALUES (1);
        """)
    }

    func saveWorkflow(_ job: WorkflowJob, event: WorkflowEvent? = nil) throws {
        try ensureReady()
        try workflowSQL("BEGIN IMMEDIATE")
        do {
            try workflowWrite("INSERT INTO workflow_jobs(job_id,project_id,updated_at,state,payload_json) VALUES(?,?,?,?,?) ON CONFLICT(job_id) DO UPDATE SET project_id=excluded.project_id,updated_at=excluded.updated_at,state=excluded.state,payload_json=excluded.payload_json",
                values: [job.id, job.projectId, job.updatedAt, job.state.rawValue, String(decoding: try JSONEncoder().encode(job), as: UTF8.self)])
            if let event {
                try workflowWrite("INSERT OR IGNORE INTO workflow_events(event_id,job_id,created_at,payload_json) VALUES(?,?,?,?)",
                    values: [event.id, event.jobId, event.timestamp, String(decoding: try JSONEncoder().encode(event), as: UTF8.self)])
            }
            try workflowSQL("COMMIT")
        } catch { try? workflowSQL("ROLLBACK"); throw error }
    }

    func workflows(limit: Int = 100, offset: Int = 0, unfinishedOnly: Bool = false, projectId: String = "", status: String = "", provider: String = "", workflow: String = "", search: String = "") throws -> [WorkflowJob] {
        try ensureReady()
        var conditions = unfinishedOnly ? ["state NOT IN ('succeeded','failed','canceled')"] : []
        var values: [String] = []
        for (column, value) in [("project_id", projectId), ("state", status), ("json_extract(payload_json,'$.provider')", provider), ("json_extract(payload_json,'$.workflow')", workflow)] where !value.isEmpty {
            conditions.append(column + "=?")
            values.append(value)
        }
        if !search.isEmpty {
            conditions.append("instr(lower(replace(payload_json,'_',' ')), lower(?)) > 0")
            values.append(search)
        }
        let condition = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
        values += [String(max(1, limit)), String(max(0, offset))]
        return try workflowRows("SELECT payload_json FROM workflow_jobs \(condition) ORDER BY updated_at DESC,job_id LIMIT ? OFFSET ?", values: values)
            .compactMap { try? JSONDecoder().decode(WorkflowJob.self, from: Data($0.utf8)) }
    }

    func workflowEvents(jobId: String) throws -> [WorkflowEvent] {
        try ensureReady()
        return try workflowRows("SELECT payload_json FROM workflow_events WHERE job_id=? ORDER BY rowid", values: [jobId])
            .compactMap { try? JSONDecoder().decode(WorkflowEvent.self, from: Data($0.utf8)) }
    }

    func workflowLogSummaries(jobIds: [String]) throws -> [WorkflowLogEvidence] {
        try ensureReady()
        guard !jobIds.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: jobIds.count).joined(separator: ",")
        let sql = """
        SELECT json_object('jobId',j.job_id,
          'eventMessage',(SELECT json_extract(e.payload_json,'$.message') FROM workflow_events e
            WHERE e.job_id=j.job_id AND json_extract(e.payload_json,'$.message') != ''
              AND (json_extract(e.payload_json,'$.kind')='error' OR json_extract(e.payload_json,'$.phase') IN ('video.error','error'))
            ORDER BY e.rowid DESC LIMIT 1),
          'providerResponse',(SELECT CASE WHEN c.response_text_json != '' THEN c.response_text_json ELSE CAST(c.response_body AS TEXT) END
            FROM inference_calls c WHERE c.trace_id IN (SELECT value FROM json_each(j.payload_json,'$.traceIds'))
              AND c.response_status_code >= 400 ORDER BY c.created_at DESC LIMIT 1))
        FROM workflow_jobs j WHERE j.job_id IN (\(placeholders))
        """
        return try workflowRows(sql, values: jobIds).compactMap {
            try? JSONDecoder().decode(WorkflowLogEvidence.self, from: Data(WorkflowPrivacy.json($0).utf8))
        }
    }

    func workflowTraceRecords(ids: [String]) throws -> [WorkflowTraceRecord] {
        let raw = try workflowTraceDetails(ids: ids)
        return raw.components(separatedBy: "\n\n").filter { !$0.isEmpty }.map { WorkflowTraceRecord(rawJSON: $0) }
    }

    func workflowTraceDetails(ids: [String]) throws -> String {
        try ensureReady()
        var results: [String] = []
        for id in ids {
            let rows = try workflowRows("SELECT json_object('trace_id',trace_id,'created_at',created_at,'provider',provider,'model',model,'operation',operation,'request',CASE WHEN request_text_json != '' THEN request_text_json ELSE CAST(request_body AS TEXT) END,'response',CASE WHEN response_text_json != '' THEN response_text_json ELSE CAST(response_body AS TEXT) END,'provider_request_id',provider_request_id,'provider_response_id',provider_response_id,'parsed_output',parsed_output_json,'media_refs',media_refs_json,'status_code',response_status_code,'error',error_message,'latency_ms',latency_ms,'input_tokens',input_tokens,'output_tokens',output_tokens) FROM inference_calls WHERE trace_id=?", values: [id])
            results.append(contentsOf: rows.map(WorkflowPrivacy.json))
        }
        return results.joined(separator: "\n\n")
    }

    private func workflowSQL(_ sql: String) throws {
        guard let connection, sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK else {
            throw ScreenGraphError.capture("Could not update operational history")
        }
    }
    private func workflowWrite(_ sql: String, values: [String]) throws {
        let statement = try workflowStatement(sql, values: values)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw ScreenGraphError.capture("Could not save operational history") }
    }
    private func workflowRows(_ sql: String, values: [String]) throws -> [String] {
        let statement = try workflowStatement(sql, values: values)
        defer { sqlite3_finalize(statement) }
        var result: [String] = []
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            if let text = sqlite3_column_text(statement, 0) { result.append(String(cString: text)) }
            status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE else { throw ScreenGraphError.capture("Could not read operational history") }
        return result
    }
    private func workflowStatement(_ sql: String, values: [String]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard let connection, sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ScreenGraphError.capture("Could not open operational history query")
        }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in values.enumerated() { sqlite3_bind_text(statement, Int32(index + 1), value, -1, transient) }
        return statement
    }
}
