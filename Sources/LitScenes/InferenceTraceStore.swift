import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
private let inferenceTraceSchemaVersion = "litscenes.inference_traces.v0.2"

struct InferenceTraceUsage: Sendable {
    var inputTokens: Int?
    var outputTokens: Int?
    var totalTokens: Int?
}

struct InferenceTraceRequestMetadata: Sendable {
    var provider: String
    var apiFamily: String
    var operation: String
    var projectId: String = ""
    var runId: String = ""
    var traceGroupId: String = ""
    var parentTraceId: String = ""
    var workflowName: String = ""
    var workflowStep: String = ""
    var artifactType: String = ""
    var artifactId: String = ""
    var model: String = ""
    var requestBodyFormat: String = ""
    var responseBodyFormatHint: String = ""
    var requestTextJSON: String = ""
    var responseTextJSON: String = ""
    var mediaRefsJSON: String = ""
    var providerRequestIDHeaderCandidates: [String] = []
    var captureRequestBody: Bool = true
    var captureResponseBody: Bool = true
}

struct TracedHTTPResult: Sendable {
    var traceId: String
    var data: Data
    var response: HTTPURLResponse?
    var latencyMs: Int
}

struct TracedHTTPDownloadResult: Sendable {
    var traceId: String
    var temporaryURL: URL
    var response: HTTPURLResponse?
    var latencyMs: Int
}

enum InferenceTraceSettings {
    static func isEnabled() -> Bool {
        if let override = environmentValue("LITSCENES_DEV_INFERENCE_TRACE")?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !override.isEmpty {
            return !["0", "false", "no", "off"].contains(override)
        }
#if DEBUG
        return true
#else
        return false
#endif
    }

    static var databaseURL: URL {
        litScenesApplicationSupportDirectory()
            .appendingPathComponent("dev", isDirectory: true)
            .appendingPathComponent("inference_traces.sqlite")
    }
}

actor InferenceTraceStore {
    static let shared = InferenceTraceStore()

    private var connection: OpaquePointer?
    private var initialized = false

    func record(
        request: URLRequest,
        metadata: InferenceTraceRequestMetadata,
        response: HTTPURLResponse?,
        responseBody: Data?,
        latencyMs: Int,
        error: Error? = nil
    ) -> String {
        let traceId = "itrace_\(UUID().uuidString.lowercased())"
        guard InferenceTraceSettings.isEnabled() else { return traceId }
        do {
            try ensureReady()
            try insertTrace(
                traceId: traceId,
                request: request,
                metadata: metadata,
                response: response,
                responseBody: responseBody ?? Data(),
                latencyMs: latencyMs,
                error: error
            )
        } catch {
            print("[inference_trace] error trace_id=\(traceId) message=\"\(error.localizedDescription)\"")
        }
        return traceId
    }

    /// Records a durable workflow-control event that intentionally performs
    /// no network request (for example, stopping local polling when a provider
    /// has no remote cancellation endpoint). A 200 status means the local
    /// control event itself succeeded; metadata must state remote semantics.
    func recordEvent(
        request: URLRequest,
        metadata: InferenceTraceRequestMetadata
    ) -> String {
        let response = request.url.flatMap {
            HTTPURLResponse(
                url: $0,
                statusCode: 200,
                httpVersion: "LOCAL",
                headerFields: ["x-litscenes-event": "1"]
            )
        }
        return record(
            request: request,
            metadata: metadata,
            response: response,
            responseBody: nil,
            latencyMs: 0
        )
    }

    func enrich(
        traceId: String,
        providerRequestId: String? = nil,
        providerResponseId: String? = nil,
        model: String? = nil,
        usage: InferenceTraceUsage? = nil,
        parsedOutputJSON: String? = nil
    ) {
        guard InferenceTraceSettings.isEnabled() else { return }
        do {
            try ensureReady()
            try updateTrace(
                traceId: traceId,
                providerRequestId: providerRequestId,
                providerResponseId: providerResponseId,
                model: model,
                usage: usage,
                parsedOutputJSON: parsedOutputJSON
            )
        } catch {
            print("[inference_trace] enrich_error trace_id=\(traceId) message=\"\(error.localizedDescription)\"")
        }
    }

    func enrichContext(
        traceId: String,
        traceGroupId: String? = nil,
        parentTraceId: String? = nil,
        workflowName: String? = nil,
        workflowStep: String? = nil,
        artifactType: String? = nil,
        artifactId: String? = nil,
        requestTextJSON: String? = nil,
        responseTextJSON: String? = nil,
        mediaRefsJSON: String? = nil
    ) {
        guard InferenceTraceSettings.isEnabled() else { return }
        do {
            try ensureReady()
            try updateTraceContext(
                traceId: traceId,
                traceGroupId: traceGroupId,
                parentTraceId: parentTraceId,
                workflowName: workflowName,
                workflowStep: workflowStep,
                artifactType: artifactType,
                artifactId: artifactId,
                requestTextJSON: requestTextJSON,
                responseTextJSON: responseTextJSON,
                mediaRefsJSON: mediaRefsJSON
            )
        } catch {
            print("[inference_trace] context_enrich_error trace_id=\(traceId) message=\"\(error.localizedDescription)\"")
        }
    }

    private func ensureReady() throws {
        if initialized { return }
        let databaseURL = InferenceTraceSettings.databaseURL
        try ensureDirectory(databaseURL.deletingLastPathComponent())
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
            throw ScreenGraphError.capture("Inference trace DB open failed: \(message)")
        }
        connection = db
        try execute("""
        CREATE TABLE IF NOT EXISTS inference_calls (
            trace_id TEXT PRIMARY KEY,
            created_at TEXT NOT NULL,
            schema_version TEXT NOT NULL DEFAULT '',
            provider TEXT NOT NULL,
            api_family TEXT NOT NULL,
            operation TEXT NOT NULL,
            project_id TEXT NOT NULL,
            run_id TEXT NOT NULL,
            trace_group_id TEXT NOT NULL DEFAULT '',
            parent_trace_id TEXT NOT NULL DEFAULT '',
            workflow_name TEXT NOT NULL DEFAULT '',
            workflow_step TEXT NOT NULL DEFAULT '',
            artifact_type TEXT NOT NULL DEFAULT '',
            artifact_id TEXT NOT NULL DEFAULT '',
            request_method TEXT NOT NULL,
            request_url TEXT NOT NULL,
            request_headers_json TEXT NOT NULL,
            request_body BLOB,
            request_body_format TEXT NOT NULL,
            request_body_compression TEXT NOT NULL,
            request_body_sha256 TEXT NOT NULL,
            request_text_json TEXT NOT NULL DEFAULT '',
            response_status_code INTEGER,
            response_headers_json TEXT NOT NULL,
            response_body BLOB,
            response_body_format TEXT NOT NULL,
            response_body_compression TEXT NOT NULL,
            response_body_sha256 TEXT NOT NULL,
            response_text_json TEXT NOT NULL DEFAULT '',
            media_refs_json TEXT NOT NULL DEFAULT '',
            provider_request_id TEXT NOT NULL,
            provider_response_id TEXT NOT NULL,
            model TEXT NOT NULL,
            input_tokens INTEGER,
            output_tokens INTEGER,
            total_tokens INTEGER,
            latency_ms INTEGER NOT NULL,
            success INTEGER NOT NULL,
            error_domain TEXT NOT NULL,
            error_message TEXT NOT NULL,
            parsed_output_json TEXT NOT NULL
        );
        """)
        try addColumnIfNeeded("schema_version", definition: "TEXT NOT NULL DEFAULT ''")
        try addColumnIfNeeded("trace_group_id", definition: "TEXT NOT NULL DEFAULT ''")
        try addColumnIfNeeded("parent_trace_id", definition: "TEXT NOT NULL DEFAULT ''")
        try addColumnIfNeeded("workflow_name", definition: "TEXT NOT NULL DEFAULT ''")
        try addColumnIfNeeded("workflow_step", definition: "TEXT NOT NULL DEFAULT ''")
        try addColumnIfNeeded("artifact_type", definition: "TEXT NOT NULL DEFAULT ''")
        try addColumnIfNeeded("artifact_id", definition: "TEXT NOT NULL DEFAULT ''")
        try addColumnIfNeeded("request_text_json", definition: "TEXT NOT NULL DEFAULT ''")
        try addColumnIfNeeded("response_text_json", definition: "TEXT NOT NULL DEFAULT ''")
        try addColumnIfNeeded("media_refs_json", definition: "TEXT NOT NULL DEFAULT ''")
        try execute("CREATE INDEX IF NOT EXISTS inference_calls_created_at_idx ON inference_calls(created_at);")
        try execute("CREATE INDEX IF NOT EXISTS inference_calls_project_created_at_idx ON inference_calls(project_id, created_at);")
        try execute("CREATE INDEX IF NOT EXISTS inference_calls_provider_operation_created_at_idx ON inference_calls(provider, operation, created_at);")
        try execute("CREATE INDEX IF NOT EXISTS inference_calls_trace_group_created_at_idx ON inference_calls(trace_group_id, created_at);")
        try execute("CREATE INDEX IF NOT EXISTS inference_calls_artifact_idx ON inference_calls(artifact_type, artifact_id);")
        try execute("CREATE INDEX IF NOT EXISTS inference_calls_workflow_created_at_idx ON inference_calls(workflow_name, workflow_step, created_at);")
        initialized = true
    }

    private func execute(_ sql: String) throws {
        guard let connection else { throw ScreenGraphError.capture("Inference trace DB is not open.") }
        guard sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK else {
            throw ScreenGraphError.capture("Inference trace SQL failed: \(String(cString: sqlite3_errmsg(connection)))")
        }
    }

    private func addColumnIfNeeded(_ column: String, definition: String) throws {
        guard try !tableHasColumn("inference_calls", column: column) else { return }
        try execute("ALTER TABLE inference_calls ADD COLUMN \(column) \(definition);")
    }

    private func tableHasColumn(_ tableName: String, column: String) throws -> Bool {
        guard let connection else { throw ScreenGraphError.capture("Inference trace DB is not open.") }
        let sql = "PRAGMA table_info(\(tableName));"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ScreenGraphError.capture("Inference trace schema inspect failed: \(String(cString: sqlite3_errmsg(connection)))")
        }
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            if let columnNamePointer = sqlite3_column_text(statement, 1) {
                let columnName = String(cString: columnNamePointer)
                if columnName == column {
                    return true
                }
            }
        }
        return false
    }

    private func insertTrace(
        traceId: String,
        request: URLRequest,
        metadata: InferenceTraceRequestMetadata,
        response: HTTPURLResponse?,
        responseBody: Data,
        latencyMs: Int,
        error: Error?
    ) throws {
        guard let connection else { throw ScreenGraphError.capture("Inference trace DB is not open.") }
        let sql = """
        INSERT INTO inference_calls (
            trace_id, created_at, schema_version, provider, api_family, operation, project_id, run_id,
            trace_group_id, parent_trace_id, workflow_name, workflow_step, artifact_type, artifact_id,
            request_method, request_url, request_headers_json, request_body, request_body_format,
            request_body_compression, request_body_sha256, request_text_json, response_status_code,
            response_headers_json, response_body, response_body_format, response_body_compression,
            response_body_sha256, response_text_json, media_refs_json, provider_request_id,
            provider_response_id, model, input_tokens, output_tokens, total_tokens, latency_ms,
            success, error_domain, error_message, parsed_output_json
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ScreenGraphError.capture("Inference trace insert prepare failed: \(String(cString: sqlite3_errmsg(connection)))")
        }
        defer { sqlite3_finalize(statement) }

        let requestBody = metadata.captureRequestBody ? (request.httpBody ?? Data()) : Data()
        let capturedResponseBody = metadata.captureResponseBody ? responseBody : Data()
        let requestHeaders = jsonString(sanitizedHeaders(request.allHTTPHeaderFields ?? [:]))
        let responseHeaders = jsonString(sanitizedHeaders(headersDictionary(response?.allHeaderFields ?? [:])))
        let requestBodyFormat = request.value(forHTTPHeaderField: "Content-Type") ?? metadata.requestBodyFormat
        let responseBodyFormat = response?.value(forHTTPHeaderField: "content-type") ?? metadata.responseBodyFormatHint
        let providerRequestId = firstHeaderValue(metadata.providerRequestIDHeaderCandidates, in: response)
        let nsError = error as NSError?
        let success = ((response?.statusCode ?? 0) >= 200 && (response?.statusCode ?? 0) < 300) && error == nil

        bindText(traceId, to: statement, index: 1)
        bindText(DateFormats.now(), to: statement, index: 2)
        bindText(inferenceTraceSchemaVersion, to: statement, index: 3)
        bindText(metadata.provider, to: statement, index: 4)
        bindText(metadata.apiFamily, to: statement, index: 5)
        bindText(metadata.operation, to: statement, index: 6)
        bindText(metadata.projectId, to: statement, index: 7)
        bindText(metadata.runId, to: statement, index: 8)
        bindText(metadata.traceGroupId, to: statement, index: 9)
        bindText(metadata.parentTraceId, to: statement, index: 10)
        bindText(metadata.workflowName, to: statement, index: 11)
        bindText(metadata.workflowStep, to: statement, index: 12)
        bindText(metadata.artifactType, to: statement, index: 13)
        bindText(metadata.artifactId, to: statement, index: 14)
        bindText(request.httpMethod ?? "GET", to: statement, index: 15)
        bindText(request.url?.absoluteString ?? "", to: statement, index: 16)
        bindText(requestHeaders, to: statement, index: 17)
        bindBlob(requestBody, to: statement, index: 18)
        bindText(requestBodyFormat, to: statement, index: 19)
        bindText("none", to: statement, index: 20)
        bindText(requestBody.isEmpty ? "" : sha256Hex(requestBody), to: statement, index: 21)
        bindText(metadata.requestTextJSON, to: statement, index: 22)
        if let status = response?.statusCode {
            sqlite3_bind_int(statement, 23, Int32(status))
        } else {
            sqlite3_bind_null(statement, 23)
        }
        bindText(responseHeaders, to: statement, index: 24)
        bindBlob(capturedResponseBody, to: statement, index: 25)
        bindText(responseBodyFormat, to: statement, index: 26)
        bindText("none", to: statement, index: 27)
        bindText(capturedResponseBody.isEmpty ? "" : sha256Hex(capturedResponseBody), to: statement, index: 28)
        bindText(metadata.responseTextJSON, to: statement, index: 29)
        bindText(metadata.mediaRefsJSON, to: statement, index: 30)
        bindText(providerRequestId, to: statement, index: 31)
        bindText("", to: statement, index: 32)
        bindText(metadata.model, to: statement, index: 33)
        sqlite3_bind_null(statement, 34)
        sqlite3_bind_null(statement, 35)
        sqlite3_bind_null(statement, 36)
        sqlite3_bind_int(statement, 37, Int32(max(0, latencyMs)))
        sqlite3_bind_int(statement, 38, success ? 1 : 0)
        bindText(nsError?.domain ?? "", to: statement, index: 39)
        bindText(error?.localizedDescription ?? "", to: statement, index: 40)
        bindText("", to: statement, index: 41)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw ScreenGraphError.capture("Inference trace insert failed: \(String(cString: sqlite3_errmsg(connection)))")
        }
    }

    private func updateTrace(
        traceId: String,
        providerRequestId: String?,
        providerResponseId: String?,
        model: String?,
        usage: InferenceTraceUsage?,
        parsedOutputJSON: String?
    ) throws {
        guard let connection else { throw ScreenGraphError.capture("Inference trace DB is not open.") }
        let sql = """
        UPDATE inference_calls
        SET provider_request_id = COALESCE(NULLIF(?, ''), provider_request_id),
            provider_response_id = COALESCE(NULLIF(?, ''), provider_response_id),
            model = COALESCE(NULLIF(?, ''), model),
            input_tokens = COALESCE(?, input_tokens),
            output_tokens = COALESCE(?, output_tokens),
            total_tokens = COALESCE(?, total_tokens),
            parsed_output_json = COALESCE(NULLIF(?, ''), parsed_output_json)
        WHERE trace_id = ?;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ScreenGraphError.capture("Inference trace update prepare failed: \(String(cString: sqlite3_errmsg(connection)))")
        }
        defer { sqlite3_finalize(statement) }

        bindText(providerRequestId ?? "", to: statement, index: 1)
        bindText(providerResponseId ?? "", to: statement, index: 2)
        bindText(model ?? "", to: statement, index: 3)
        bindOptionalInt(usage?.inputTokens, to: statement, index: 4)
        bindOptionalInt(usage?.outputTokens, to: statement, index: 5)
        bindOptionalInt(usage?.totalTokens, to: statement, index: 6)
        bindText(parsedOutputJSON ?? "", to: statement, index: 7)
        bindText(traceId, to: statement, index: 8)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw ScreenGraphError.capture("Inference trace update failed: \(String(cString: sqlite3_errmsg(connection)))")
        }
    }

    private func updateTraceContext(
        traceId: String,
        traceGroupId: String?,
        parentTraceId: String?,
        workflowName: String?,
        workflowStep: String?,
        artifactType: String?,
        artifactId: String?,
        requestTextJSON: String?,
        responseTextJSON: String?,
        mediaRefsJSON: String?
    ) throws {
        guard let connection else { throw ScreenGraphError.capture("Inference trace DB is not open.") }
        let sql = """
        UPDATE inference_calls
        SET trace_group_id = COALESCE(NULLIF(?, ''), trace_group_id),
            parent_trace_id = COALESCE(NULLIF(?, ''), parent_trace_id),
            workflow_name = COALESCE(NULLIF(?, ''), workflow_name),
            workflow_step = COALESCE(NULLIF(?, ''), workflow_step),
            artifact_type = COALESCE(NULLIF(?, ''), artifact_type),
            artifact_id = COALESCE(NULLIF(?, ''), artifact_id),
            request_text_json = COALESCE(NULLIF(?, ''), request_text_json),
            response_text_json = COALESCE(NULLIF(?, ''), response_text_json),
            media_refs_json = COALESCE(NULLIF(?, ''), media_refs_json)
        WHERE trace_id = ?;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ScreenGraphError.capture("Inference trace context update prepare failed: \(String(cString: sqlite3_errmsg(connection)))")
        }
        defer { sqlite3_finalize(statement) }

        bindText(traceGroupId ?? "", to: statement, index: 1)
        bindText(parentTraceId ?? "", to: statement, index: 2)
        bindText(workflowName ?? "", to: statement, index: 3)
        bindText(workflowStep ?? "", to: statement, index: 4)
        bindText(artifactType ?? "", to: statement, index: 5)
        bindText(artifactId ?? "", to: statement, index: 6)
        bindText(requestTextJSON ?? "", to: statement, index: 7)
        bindText(responseTextJSON ?? "", to: statement, index: 8)
        bindText(mediaRefsJSON ?? "", to: statement, index: 9)
        bindText(traceId, to: statement, index: 10)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw ScreenGraphError.capture("Inference trace context update failed: \(String(cString: sqlite3_errmsg(connection)))")
        }
    }

    private func bindText(_ value: String, to statement: OpaquePointer, index: Int32) {
        _ = value.withCString { pointer in
            sqlite3_bind_text(statement, index, pointer, -1, sqliteTransient)
        }
    }

    private func bindBlob(_ value: Data, to statement: OpaquePointer, index: Int32) {
        guard !value.isEmpty else {
            sqlite3_bind_null(statement, index)
            return
        }
        _ = value.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(value.count), sqliteTransient)
        }
    }

    private func bindOptionalInt(_ value: Int?, to statement: OpaquePointer, index: Int32) {
        if let value {
            sqlite3_bind_int(statement, index, Int32(value))
        } else {
            sqlite3_bind_null(statement, index)
        }
    }
}

enum TracedHTTPTransport {
    static func send(
        request: URLRequest,
        recordedRequest: URLRequest? = nil,
        metadata: InferenceTraceRequestMetadata
    ) async throws -> TracedHTTPResult {
        let startedAt = Date()
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let httpResponse = response as? HTTPURLResponse
            let latencyMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            let traceId = await InferenceTraceStore.shared.record(
                request: recordedRequest ?? request,
                metadata: metadata,
                response: httpResponse,
                responseBody: data,
                latencyMs: latencyMs
            )
            return TracedHTTPResult(
                traceId: traceId,
                data: data,
                response: httpResponse,
                latencyMs: latencyMs
            )
        } catch {
            let latencyMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            let traceId = await InferenceTraceStore.shared.record(
                request: recordedRequest ?? request,
                metadata: metadata,
                response: nil,
                responseBody: nil,
                latencyMs: latencyMs,
                error: error
            )
            print("[inference_trace] request_error trace_id=\(traceId) provider=\(metadata.provider) operation=\(metadata.operation) message=\"\(error.localizedDescription)\"")
            throw error
        }
    }

    /// Streams a request body from disk while recording the same safe trace
    /// envelope as JSON calls. Callers must disable raw body capture for
    /// multipart/binary uploads and describe the executable inputs through
    /// requestTextJSON/mediaRefsJSON instead.
    static func upload(
        request: URLRequest,
        fromFile fileURL: URL,
        recordedRequest: URLRequest? = nil,
        metadata: InferenceTraceRequestMetadata
    ) async throws -> TracedHTTPResult {
        let startedAt = Date()
        do {
            let (data, response) = try await URLSession.shared.upload(for: request, fromFile: fileURL)
            let httpResponse = response as? HTTPURLResponse
            let latencyMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            let traceId = await InferenceTraceStore.shared.record(
                request: recordedRequest ?? request,
                metadata: metadata,
                response: httpResponse,
                responseBody: data,
                latencyMs: latencyMs
            )
            return TracedHTTPResult(
                traceId: traceId,
                data: data,
                response: httpResponse,
                latencyMs: latencyMs
            )
        } catch {
            let latencyMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            let traceId = await InferenceTraceStore.shared.record(
                request: recordedRequest ?? request,
                metadata: metadata,
                response: nil,
                responseBody: nil,
                latencyMs: latencyMs,
                error: error
            )
            print("[inference_trace] upload_error trace_id=\(traceId) provider=\(metadata.provider) operation=\(metadata.operation) message=\"\(error.localizedDescription)\"")
            throw error
        }
    }

    /// Downloads a binary response to URLSession's temporary file. Binary
    /// bytes are deliberately excluded from the trace; callers enrich the row
    /// with hashes/provenance after validating and moving the file.
    static func download(
        request: URLRequest,
        recordedRequest: URLRequest? = nil,
        metadata: InferenceTraceRequestMetadata
    ) async throws -> TracedHTTPDownloadResult {
        let startedAt = Date()
        do {
            let (temporaryURL, response) = try await URLSession.shared.download(for: request)
            let httpResponse = response as? HTTPURLResponse
            let latencyMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            let traceId = await InferenceTraceStore.shared.record(
                request: recordedRequest ?? request,
                metadata: metadata,
                response: httpResponse,
                responseBody: nil,
                latencyMs: latencyMs
            )
            return TracedHTTPDownloadResult(
                traceId: traceId,
                temporaryURL: temporaryURL,
                response: httpResponse,
                latencyMs: latencyMs
            )
        } catch {
            let latencyMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            let traceId = await InferenceTraceStore.shared.record(
                request: recordedRequest ?? request,
                metadata: metadata,
                response: nil,
                responseBody: nil,
                latencyMs: latencyMs,
                error: error
            )
            print("[inference_trace] download_error trace_id=\(traceId) provider=\(metadata.provider) operation=\(metadata.operation) message=\"\(error.localizedDescription)\"")
            throw error
        }
    }
}

private func sanitizedHeaders(_ headers: [String: String]) -> [String: String] {
    var sanitized: [String: String] = [:]
    for (key, value) in headers {
        let lowered = key.lowercased()
        if [
            "authorization",
            "proxy-authorization",
            "cookie",
            "set-cookie",
            "x-api-key",
            "xi-api-key",
            "x-fal-object-lifecycle",
            "x-fal-object-lifecycle-preference",
        ].contains(lowered) {
            continue
        }
        sanitized[key] = value
    }
    return sanitized
}

private func headersDictionary(_ values: [AnyHashable: Any]) -> [String: String] {
    var out: [String: String] = [:]
    for (key, value) in values {
        out[String(describing: key)] = String(describing: value)
    }
    return out
}

private func jsonString(_ value: [String: String]) -> String {
    var anyValue: [String: Any] = [:]
    for (key, entry) in value {
        anyValue[key] = entry
    }
    return inferenceTraceJSONString(anyValue)
}

private func firstHeaderValue(_ candidates: [String], in response: HTTPURLResponse?) -> String {
    for candidate in candidates {
        if let value = response?.value(forHTTPHeaderField: candidate), !value.isEmpty {
            return value
        }
    }
    return ""
}

func inferenceTraceJSONString(_ value: [String: Any]) -> String {
    guard JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
          let text = String(data: data, encoding: .utf8) else {
        return "{}"
    }
    return text
}
