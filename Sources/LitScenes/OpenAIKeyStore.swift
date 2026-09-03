import Foundation

enum OpenAIKeySource: String {
    case savedLocal = "Saved Locally"
    case environment = "Environment"
    case missing = "Missing"
}

enum OpenAIKeyStore {
    static var savedKeyURL: URL {
        appSupportDirectory.appendingPathComponent("credentials.env")
    }

    static func resolvedAPIKey() -> String? {
        let key = LitScenesCredentialStore()
            .resolvedCredential(for: .openAI)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            return key
        }
        return nil
    }

    static func currentSource() -> OpenAIKeySource {
        let status = LitScenesCredentialStore().credentialStatus(for: .openAI)
        if status.source == .credentialsFile {
            return .savedLocal
        }
        if status.source == .environment {
            return .environment
        }
        return .missing
    }

    static func hasSavedAPIKey() -> Bool {
        guard let key = savedAPIKey() else { return false }
        return !key.isEmpty
    }

    static func savedAPIKey() -> String? {
        loadDotEnv(from: savedKeyURL)["OPENAI_API_KEY"]
    }

    static func saveAPIKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        var values = loadDotEnv(from: savedKeyURL)
        guard !trimmed.isEmpty else {
            try deleteAPIKey()
            return
        }

        values["OPENAI_API_KEY"] = trimmed
        try saveCredentialValues(values)
    }

    static func deleteAPIKey() throws {
        var values = loadDotEnv(from: savedKeyURL)
        values.removeValue(forKey: "OPENAI_API_KEY")
        try saveCredentialValues(values)
    }

    private static var appSupportDirectory: URL {
        litScenesApplicationSupportDirectory()
    }

    static func saveCredentialValues(_ values: [String: String]) throws {
        try ensureDirectory(appSupportDirectory)
        if values.isEmpty {
            guard FileManager.default.fileExists(atPath: savedKeyURL.path) else { return }
            try FileManager.default.removeItem(at: savedKeyURL)
            return
        }
        let text = values
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "\n") + "\n"
        try text.write(to: savedKeyURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: savedKeyURL.path)
    }
}
