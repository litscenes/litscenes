import Foundation

struct ArtifactStore {
    let root: URL
    let sessionId: String
    let project: ProjectRecord?

    var sessionDir: URL { root.appendingPathComponent("sessions").appendingPathComponent(sessionId) }
    var bufferDir: URL { sessionDir.appendingPathComponent("buffer") }
    var capturesDir: URL { sessionDir.appendingPathComponent("captures") }
    var capturesLog: URL { sessionDir.appendingPathComponent("captures.jsonl") }
    var analysisLog: URL { sessionDir.appendingPathComponent("analysis.jsonl") }
    var usageLog: URL { sessionDir.appendingPathComponent("usage.jsonl") }
    var eventsLog: URL { sessionDir.appendingPathComponent("events.jsonl") }
    var summariesLog: URL { sessionDir.appendingPathComponent("summaries.jsonl") }
    var sessionJson: URL { sessionDir.appendingPathComponent("session.json") }

    init(
        root: URL = litScenesApplicationSupportDirectory().appendingPathComponent("screen-graph-output", isDirectory: true),
        sessionId: String,
        project: ProjectRecord? = nil
    ) {
        self.root = root
        self.sessionId = sessionId
        self.project = project
    }

    init(project: ProjectRecord, sessionId: String, library: ProjectLibrary = ProjectLibrary()) {
        self.root = library.projectDirectory(for: project)
        self.sessionId = sessionId
        self.project = project
    }

    func prepare(config: SessionConfig) throws {
        try ensureDirectory(bufferDir)
        try ensureDirectory(capturesDir)
        var sessionPacket: [String: String] = [
            "session_id": sessionId,
            "created_at": DateFormats.now(),
            "schema_version": "screen_graph.session.v0.1",
            "capture_interval_seconds": String(config.captureIntervalSeconds),
            "buffer_delay_seconds": String(config.bufferDelaySeconds),
            "model": config.model,
            "detail": config.detail.rawValue
        ]
        if let project {
            sessionPacket["project_id"] = project.projectId
            sessionPacket["project_name"] = project.name
        }
        let data = try JSONSerialization.data(withJSONObject: sessionPacket, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: sessionJson, options: [.atomic])
    }

    func bufferURL(captureId: String) -> URL {
        bufferDir.appendingPathComponent("\(captureId).png")
    }

    func retainedURL(captureId: String) -> URL {
        capturesDir.appendingPathComponent("\(captureId).png")
    }

    func retainBufferedCapture(_ url: URL, captureId: String) throws -> URL {
        let retained = retainedURL(captureId: captureId)
        if FileManager.default.fileExists(atPath: retained.path) {
            try FileManager.default.removeItem(at: retained)
        }
        try FileManager.default.moveItem(at: url, to: retained)
        return retained
    }

    func append<T: Encodable>(_ value: T, to url: URL) throws {
        try ensureDirectory(url.deletingLastPathComponent())
        let line = try JSONCoding.encoder.encode(value) + Data([0x0A])
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: url, options: [.atomic])
        }
    }

    func appendCapture(_ record: CaptureRecord) throws {
        try append(record, to: capturesLog)
    }

    func appendAnalysis(_ record: AnalysisEnvelope) throws {
        try append(record, to: analysisLog)
    }

    func appendUsage(_ record: UsageRecord) throws {
        try append(record, to: usageLog)
    }

    func appendEvent(kind: String, message: String) throws {
        let event = EventRecord(
            eventId: "event_\(UUID().uuidString.lowercased())",
            sessionId: sessionId,
            kind: kind,
            message: message,
            createdAt: DateFormats.now()
        )
        try append(event, to: eventsLog)
    }

    func appendSummary(_ record: SummaryRecord) throws {
        try append(record, to: summariesLog)
    }
}
