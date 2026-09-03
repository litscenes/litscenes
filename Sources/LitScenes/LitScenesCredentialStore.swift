import Foundation

enum LitScenesProviderCredential: String, CaseIterable, Identifiable {
    case openAI = "openai"
    case elevenLabs = "elevenlabs"
    case ltx = "ltx"
    case civitai = "civitai"
    case fal = "fal"
    case decart = "decart"
    case kling = "kling"
    case stability = "stability"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .openAI: "OpenAI"
        case .elevenLabs: "ElevenLabs"
        case .ltx: "LTX"
        case .civitai: "CivitAI"
        case .fal: "FAL"
        case .decart: "Decart"
        case .kling: "Kling"
        case .stability: "Stability AI"
        }
    }

    var keyCandidates: [String] {
        switch self {
        case .openAI: ["OPENAI_API_KEY"]
        case .elevenLabs: ["ELEVEN_LABS_API_KEY", "ELEVENLABS_API_KEY"]
        case .ltx: ["LTX_API_KEY", "LTXV_API_KEY"]
        case .civitai: ["CIVITAI_API_KEY"]
        case .fal: ["FAL_API_KEY", "FAL_KEY"]
        case .decart: ["DECART_API_KEY"]
        case .kling: ["KLING_API_KEY", "KLINGAI_API_KEY", "KLING_ACCESS_KEY", "KLING_SECRET_KEY", "KLINGAI_ACCESS_KEY", "KLINGAI_SECRET_KEY"]
        case .stability: ["STABILITY_AI_API_KEY", "STABILITY_API_KEY"]
        }
    }

    var primaryWritableKey: String {
        switch self {
        case .openAI: "OPENAI_API_KEY"
        case .elevenLabs: "ELEVEN_LABS_API_KEY"
        case .ltx: "LTX_API_KEY"
        case .civitai: "CIVITAI_API_KEY"
        case .fal: "FAL_API_KEY"
        case .decart: "DECART_API_KEY"
        case .kling: "KLING_API_KEY"
        case .stability: "STABILITY_AI_API_KEY"
        }
    }
}

enum CredentialSource: String, Codable, Hashable {
    case credentialsFile = "credentials_file"
    case environment
    case missing

    var label: String {
        switch self {
        case .credentialsFile: "credentials.env"
        case .environment: "Environment"
        case .missing: "Missing"
        }
    }
}

struct CredentialStatus: Hashable, Identifiable {
    var provider: LitScenesProviderCredential
    var id: String { provider.rawValue }
    var source: CredentialSource
    var isConfigured: Bool
    var message: String
}

enum LensContextCredential: String, CaseIterable, Identifiable {
    case endpointURL = "lens_context_url"
    case token = "lens_context_token"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .endpointURL: "Meaning Service URL"
        case .token: "Meaning Service Token"
        }
    }

    var keyCandidates: [String] {
        switch self {
        case .endpointURL: ["LITSCENES_LENS_CONTEXT_URL", "LITSCENES_THEME_CONTEXT_URL"]
        case .token: ["LITSCENES_LENS_CONTEXT_TOKEN", "LITSCENES_THEME_CONTEXT_TOKEN", "AUTH_TOKEN"]
        }
    }

    var primaryWritableKey: String {
        switch self {
        case .endpointURL: "LITSCENES_LENS_CONTEXT_URL"
        case .token: "LITSCENES_LENS_CONTEXT_TOKEN"
        }
    }

    var isSecret: Bool {
        self == .token
    }
}

struct LensContextCredentialStatus: Hashable, Identifiable {
    var credential: LensContextCredential
    var id: String { credential.rawValue }
    var source: CredentialSource
    var isConfigured: Bool
    var message: String
}

protocol LitScenesCredentialResolving {
    func resolvedCredential(for provider: LitScenesProviderCredential) -> String
    func resolvedCredentialValue(forKey key: String) -> String
    func resolvedCredentialValue(forKeys keys: [String]) -> String
    func credentialStatus(for provider: LitScenesProviderCredential) -> CredentialStatus
    func lensContextCredentialStatus(for credential: LensContextCredential) -> LensContextCredentialStatus
}

struct LitScenesCredentialStore: LitScenesCredentialResolving {
    func resolvedCredential(for provider: LitScenesProviderCredential) -> String {
        if provider == .kling {
            return resolvedKlingCredential()
        }
        if let file = credentialsFileCredential(for: provider), !file.isEmpty {
            return file
        }
        return environmentCredential(for: provider) ?? ""
    }

    func resolvedCredentialValue(forKey key: String) -> String {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return "" }
        if let value = loadDotEnv(from: OpenAIKeyStore.savedKeyURL)[trimmedKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            return value
        }
        return environmentValue(trimmedKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func resolvedCredentialValue(forKeys keys: [String]) -> String {
        for key in keys {
            let value = resolvedCredentialValue(forKey: key)
            if !value.isEmpty {
                return value
            }
        }
        return ""
    }

    func credentialStatus(for provider: LitScenesProviderCredential) -> CredentialStatus {
        if provider == .kling {
            return klingCredentialStatus()
        }
        if let file = credentialsFileCredential(for: provider), !file.isEmpty {
            return CredentialStatus(provider: provider, source: .credentialsFile, isConfigured: true, message: "Configured in credentials.env")
        }
        if let environment = environmentCredential(for: provider), !environment.isEmpty {
            return CredentialStatus(provider: provider, source: .environment, isConfigured: true, message: "Configured through process environment")
        }
        return CredentialStatus(provider: provider, source: .missing, isConfigured: false, message: "\(provider.label) credential missing")
    }

    func lensContextCredentialStatus(for credential: LensContextCredential) -> LensContextCredentialStatus {
        let fileValues = loadDotEnv(from: OpenAIKeyStore.savedKeyURL)
        let savedValue = firstValue(in: fileValues, keys: credential.keyCandidates)
        if !savedValue.isEmpty {
            return lensContextCredentialStatus(
                credential: credential,
                source: .credentialsFile,
                value: savedValue,
                fallbackMessage: "Configured in credentials.env"
            )
        }

        let environmentValue = firstEnvironmentValue(keys: credential.keyCandidates)
        if !environmentValue.isEmpty {
            return lensContextCredentialStatus(
                credential: credential,
                source: .environment,
                value: environmentValue,
                fallbackMessage: "Configured through environment or dot-env fallback"
            )
        }

        return LensContextCredentialStatus(
            credential: credential,
            source: .missing,
            isConfigured: false,
            message: "\(credential.label) missing"
        )
    }

    private func credentialsFileCredential(for provider: LitScenesProviderCredential) -> String? {
        let saved = loadDotEnv(from: OpenAIKeyStore.savedKeyURL)
        for key in provider.keyCandidates {
            if let value = saved[key], !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func environmentCredential(for provider: LitScenesProviderCredential) -> String? {
        for key in provider.keyCandidates {
            if let value = environmentValue(key), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func resolvedKlingCredential() -> String {
        let combinedKeys = ["KLING_API_KEY", "KLINGAI_API_KEY"]
        for key in combinedKeys {
            let value = resolvedCredentialValue(forKey: key)
            if !value.isEmpty {
                return value
            }
        }
        let access = firstResolvedCredentialValue(keys: ["KLING_ACCESS_KEY", "KLINGAI_ACCESS_KEY"])
        let secret = firstResolvedCredentialValue(keys: ["KLING_SECRET_KEY", "KLINGAI_SECRET_KEY"])
        if !access.isEmpty, !secret.isEmpty {
            return "\(access):\(secret)"
        }
        return ""
    }

    private func klingCredentialStatus() -> CredentialStatus {
        let fileValues = loadDotEnv(from: OpenAIKeyStore.savedKeyURL)
        let combinedFile = firstValue(in: fileValues, keys: ["KLING_API_KEY", "KLINGAI_API_KEY"])
        let accessFile = firstValue(in: fileValues, keys: ["KLING_ACCESS_KEY", "KLINGAI_ACCESS_KEY"])
        let secretFile = firstValue(in: fileValues, keys: ["KLING_SECRET_KEY", "KLINGAI_SECRET_KEY"])
        if klingCredentialLooksUsable(combinedFile) || (!accessFile.isEmpty && !secretFile.isEmpty) {
            return CredentialStatus(provider: .kling, source: .credentialsFile, isConfigured: true, message: "Configured in credentials.env")
        }
        if !combinedFile.isEmpty || !accessFile.isEmpty || !secretFile.isEmpty {
            return CredentialStatus(provider: .kling, source: .credentialsFile, isConfigured: false, message: "Kling expects KLING_API_KEY as ACCESS_KEY:SECRET_KEY or a JWT token.")
        }

        let combinedEnv = firstEnvironmentValue(keys: ["KLING_API_KEY", "KLINGAI_API_KEY"])
        let accessEnv = firstEnvironmentValue(keys: ["KLING_ACCESS_KEY", "KLINGAI_ACCESS_KEY"])
        let secretEnv = firstEnvironmentValue(keys: ["KLING_SECRET_KEY", "KLINGAI_SECRET_KEY"])
        if klingCredentialLooksUsable(combinedEnv) || (!accessEnv.isEmpty && !secretEnv.isEmpty) {
            return CredentialStatus(provider: .kling, source: .environment, isConfigured: true, message: "Configured through process environment")
        }
        if !combinedEnv.isEmpty || !accessEnv.isEmpty || !secretEnv.isEmpty {
            return CredentialStatus(provider: .kling, source: .environment, isConfigured: false, message: "Kling expects KLING_API_KEY as ACCESS_KEY:SECRET_KEY or a JWT token.")
        }

        return CredentialStatus(provider: .kling, source: .missing, isConfigured: false, message: "Kling credential missing")
    }

    private func firstResolvedCredentialValue(keys: [String]) -> String {
        for key in keys {
            let value = resolvedCredentialValue(forKey: key)
            if !value.isEmpty {
                return value
            }
        }
        return ""
    }

    private func firstEnvironmentValue(keys: [String]) -> String {
        for key in keys {
            if let value = environmentValue(key)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        return ""
    }

    private func firstValue(in values: [String: String], keys: [String]) -> String {
        for key in keys {
            if let value = values[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        return ""
    }

    private func lensContextCredentialStatus(
        credential: LensContextCredential,
        source: CredentialSource,
        value: String,
        fallbackMessage: String
    ) -> LensContextCredentialStatus {
        if credential == .endpointURL {
            let url = URL(string: value)
            let scheme = url?.scheme?.lowercased() ?? ""
            let hasValidHTTPURL = (scheme == "http" || scheme == "https") && url?.host != nil
            guard hasValidHTTPURL else {
                return LensContextCredentialStatus(
                    credential: credential,
                    source: source,
                    isConfigured: false,
                    message: "Frame Context URL must be an HTTP(S) URL."
                )
            }
        }
        return LensContextCredentialStatus(
            credential: credential,
            source: source,
            isConfigured: true,
            message: fallbackMessage
        )
    }

    private func klingCredentialLooksUsable(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.split(separator: ".").count == 3 || trimmed.contains(":")
    }
}
