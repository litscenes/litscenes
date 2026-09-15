import Foundation

final class GoMediaTransfer: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let delegate = GoMediaTransfer()
    static let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Validated local outputs survive interrupted project saves and server retention.
actor GoOutputStore {
    static let shared = GoOutputStore()
    private var directory: URL {
        let scope = GoVault.hash(GoConnection.baseURL.absoluteString + (GoVault.read("session")?.string("account_id") ?? ""))
        return litScenesApplicationSupportDirectory().appending(path: "go-outputs/" + scope, directoryHint: .isDirectory)
    }
    private func file(_ name: String) throws -> URL {
        guard !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else { throw URLError(.badURL) }
        return directory.appendingPathComponent(name)
    }
    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    func read(_ jobId: String) -> GoDocument? {
        guard let url = try? file(jobId), let data = try? Data(contentsOf: url) else { return nil }
        let job = GoDocument(data: data)
        for artifact in job.documents("artifacts") {
            guard let url = try? file(artifact.string("sha256")), let bytes = try? Data(contentsOf: url, options: .mappedIfSafe),
                  bytes.count == artifact.int("byte_count"), sha256Hex(bytes) == artifact.string("sha256") else { return nil }
        }
        return job
    }
    func data(_ artifact: GoDocument) async throws -> Data {
        let hash = artifact.string("sha256")
        let expected = artifact.int("byte_count")
        guard hash.count == 64, expected > 0, expected <= 314_572_800 else { throw URLError(.cannotDecodeContentData) }
        let destination = try file(hash)
        let info = try GoDocument(["mime_type": artifact.string("mime_type"), "byte_count": expected, "sha256": hash])
        if let cached = try? Data(contentsOf: destination, options: .mappedIfSafe), cached.count == expected, sha256Hex(cached) == hash {
            try write(info.data, to: file(hash + "-metadata"))
            return cached
        }
        guard let url = URL(string: artifact.string("url")), url.scheme == "https" ||
                (LitScenesReleaseIdentity.current.channel == .development && url.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(url.host ?? "")) else {
            throw GoServiceError(code: "output_expired", message: "This output is no longer available. Previously saved project files are unchanged.")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 300
        let (temporary, response) = try await GoMediaTransfer.session.download(for: request)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        let bytes = try Data(contentsOf: temporary, options: .mappedIfSafe)
        guard bytes.count == expected, sha256Hex(bytes) == hash else { throw URLError(.cannotDecodeContentData) }
        try write(bytes, to: destination)
        try write(info.data, to: file(hash + "-metadata"))
        return bytes
    }
    func persist(_ job: GoDocument) async throws -> GoDocument {
        if let cached = read(job.string("job_id")) { return cached }
        guard !job.bool("artifacts_expired") else {
            throw GoServiceError(code: "output_expired", message: "The server copy of this output expired. Check your saved project files or recover a local copy from Account & usage.")
        }
        var replacements: [String: String] = [:]
        for artifact in job.documents("artifacts") {
            _ = try await data(artifact)
            replacements[artifact.string("url")] = "litscenes-go-cache://" + artifact.string("sha256")
        }
        func localize(_ value: Any) -> Any {
            if let string = value as? String { return replacements[string] ?? string }
            if let object = value as? [String: Any] { return object.mapValues(localize) }
            if let array = value as? [Any] { return array.map(localize) }
            return value
        }
        let local = try GoDocument(localize(job.object) as? [String: Any] ?? [:])
        try write(local.data, to: file(job.string("job_id")))
        try await GoIntentStore.shared.acknowledge(job.string("job_id"))
        return local
    }
    func transfer(_ request: URLRequest) throws -> TracedHTTPDownloadResult? {
        guard let url = request.url, url.scheme == "litscenes-go-cache", let hash = url.host else { return nil }
        let source = try file(hash)
        let bytes = try Data(contentsOf: source, options: .mappedIfSafe)
        guard sha256Hex(bytes) == hash else { throw URLError(.cannotDecodeContentData) }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try bytes.write(to: temporary, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        let info = GoDocument(data: try Data(contentsOf: file(hash + "-metadata")))
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["content-length": String(bytes.count), "content-type": info.string("mime_type")])
        return TracedHTTPDownloadResult(traceId: "", temporaryURL: temporary, response: response, latencyMs: 0)
    }
}
