import Foundation

/// Funding markers are decoded for old projects, never accepted as vendor keys.
enum LegacyManagedWork {
    static let marker = "litscenes-managed-routing"
    static let message = "This saved job used the retired LitScenes Go service. Its saved files and history are preserved. Start a new run with your own provider key to generate again."
    struct Unavailable: LocalizedError {
        var errorDescription: String? { LegacyManagedWork.message }
    }
    static func selectsManaged(_ request: URLRequest) -> Bool {
        (request.allHTTPHeaderFields ?? [:]).values.contains { $0.contains(marker) }
    }
    static func requirePersonal(_ key: String) throws {
        if key == marker { throw Unavailable() }
    }
    static func requirePersonal(_ request: URLRequest) throws {
        if selectsManaged(request) { throw Unavailable() }
    }
}

extension Notification.Name {
    static let providerCredentialsChanged = Notification.Name("LitScenesProviderCredentialsChanged")
}

@MainActor
final class ProviderSetupEligibility {
    static let shared = ProviderSetupEligibility()
    private var checkedLaunch = false
    func needsSetupOnLaunch() -> Bool {
        guard !checkedLaunch else { return false }
        checkedLaunch = true
        return !LitScenesCredentialStore().personalCredentialStatus(for: .openAI).isConfigured
    }
}

/// Read-only access to already downloaded outputs; no account or network required.
actor LegacyManagedOutputStore {
    static let shared = LegacyManagedOutputStore()
    func transfer(_ request: URLRequest) throws -> TracedHTTPDownloadResult? {
        guard let url = request.url, url.scheme == "litscenes-go-cache" else { return nil }
        guard let hash = url.host, hash.count == 64,
              hash.allSatisfy({ "0123456789abcdef".contains($0) }) else { throw URLError(.badURL) }
        let directory = litScenesApplicationSupportDirectory().appending(path: "go-outputs", directoryHint: .isDirectory)
        let scopes = (try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])) ?? []
        for scope in scopes.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let properties = try scope.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard properties.isDirectory == true, properties.isSymbolicLink != true else { continue }
            let source = scope.appendingPathComponent(hash)
            guard let properties = try? source.resourceValues(forKeys: [.isSymbolicLinkKey]), properties.isSymbolicLink != true,
                  let bytes = try? Data(contentsOf: source, options: .mappedIfSafe), sha256Hex(bytes) == hash,
                  let infoData = try? Data(contentsOf: scope.appendingPathComponent(hash + "-metadata")),
                  let info = try? JSONSerialization.jsonObject(with: infoData) as? [String: Any],
                  info["sha256"] as? String == hash, info["byte_count"] as? Int == bytes.count else { continue }
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try bytes.write(to: temporary, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["content-length": String(bytes.count), "content-type": info["mime_type"] as? String ?? "application/octet-stream"])
            return TracedHTTPDownloadResult(traceId: "", temporaryURL: temporary, response: response, latencyMs: 0)
        }
        throw ScreenGraphError.capture("This old output is not cached on this Mac. Locate a previously saved copy or start a new run with your own provider key.")
    }
}
