import Foundation

enum ElevenLabsSpeechModels {
    static let elevenV3 = "eleven_v3"
    static let multilingualV2 = "eleven_multilingual_v2"
    static let defaultModelId = elevenV3
    static let legacyMissingModelId = multilingualV2
}

struct ElevenLabsSettings: Hashable {
    var apiKey: String
    var voiceId: String
}

struct ElevenLabsVoiceSettings: Hashable {
    var speed: Double?

    var requestBody: [String: Any] {
        var body: [String: Any] = [:]
        if let speed {
            body["speed"] = StoryAudioVoiceCatalog.clampedProviderSpeed(speed)
        }
        return body
    }
}

enum ElevenLabsSettingsStore {
    static func resolvedAPIKey() -> String? {
        let credential = LitScenesCredentialStore()
            .resolvedCredential(for: .elevenLabs)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !credential.isEmpty {
            return credential
        }
        let values = loadDotEnv(from: OpenAIKeyStore.savedKeyURL)
        if let key = firstValue(in: values, keys: ["ELEVEN_LABS_API_KEY", "ELEVENLABS_API_KEY"]) {
            return key
        }
        return firstEnvironmentValue(keys: ["ELEVEN_LABS_API_KEY", "ELEVENLABS_API_KEY"])
    }

    static func resolvedVoiceId() -> String? {
        let values = loadDotEnv(from: OpenAIKeyStore.savedKeyURL)
        if let voiceId = firstValue(in: values, keys: ["ELEVEN_LABS_VOICE_ID", "ELEVENLABS_VOICE_ID"]) {
            return voiceId
        }
        return firstEnvironmentValue(keys: ["ELEVEN_LABS_VOICE_ID", "ELEVENLABS_VOICE_ID"])
    }

    static func resolvedCustomVoiceId() -> String? {
        let values = loadDotEnv(from: OpenAIKeyStore.savedKeyURL)
        if let voiceId = firstValue(
            in: values,
            keys: ["LITSCENES_CUSTOM_VOICE_ID", "LITSCENES_KEVIN_VOICE_ID", "ELEVEN_LABS_KEVIN_VOICE_ID", "ELEVENLABS_KEVIN_VOICE_ID"]
        ) {
            return voiceId
        }
        if let voiceId = firstEnvironmentValue(
            keys: ["LITSCENES_CUSTOM_VOICE_ID", "LITSCENES_KEVIN_VOICE_ID", "ELEVEN_LABS_KEVIN_VOICE_ID", "ELEVENLABS_KEVIN_VOICE_ID"]
        ) {
            return voiceId
        }
        return resolvedVoiceId()
    }

    static func resolvedSettings() throws -> ElevenLabsSettings {
        guard let apiKey = resolvedAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty else {
            throw ScreenGraphError.credentials("ELEVEN_LABS_API_KEY or ELEVENLABS_API_KEY is not configured.")
        }
        guard let voiceId = resolvedVoiceId()?.trimmingCharacters(in: .whitespacesAndNewlines), !voiceId.isEmpty else {
            throw ScreenGraphError.credentials("ELEVEN_LABS_VOICE_ID or ELEVENLABS_VOICE_ID is not configured.")
        }
        return ElevenLabsSettings(apiKey: apiKey, voiceId: voiceId)
    }

    static func resolvedAPIKeyOrThrow() throws -> String {
        guard let apiKey = resolvedAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty else {
            throw ScreenGraphError.credentials("ELEVEN_LABS_API_KEY or ELEVENLABS_API_KEY is not configured.")
        }
        return apiKey
    }

    static func hasResolvedSettings() -> Bool {
        (resolvedAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            && (resolvedVoiceId()?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
    }

    static func hasResolvedAPIKey() -> Bool {
        resolvedAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    static func hasSavedSettings() -> Bool {
        let values = loadDotEnv(from: OpenAIKeyStore.savedKeyURL)
        return firstValue(in: values, keys: ["ELEVEN_LABS_API_KEY", "ELEVENLABS_API_KEY"]) != nil
            || firstValue(in: values, keys: ["ELEVEN_LABS_VOICE_ID", "ELEVENLABS_VOICE_ID"]) != nil
            || firstValue(
                in: values,
                keys: ["LITSCENES_CUSTOM_VOICE_ID", "LITSCENES_KEVIN_VOICE_ID", "ELEVEN_LABS_KEVIN_VOICE_ID", "ELEVENLABS_KEVIN_VOICE_ID"]
            ) != nil
    }

    static func save(apiKey: String, voiceId: String) throws {
        try save(apiKey: apiKey, customVoiceId: voiceId)
    }

    static func save(apiKey: String, customVoiceId: String) throws {
        var values = loadDotEnv(from: OpenAIKeyStore.savedKeyURL)
        let cleanedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedVoiceId = customVoiceId.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedAPIKey.isEmpty {
            values.removeValue(forKey: "ELEVEN_LABS_API_KEY")
            values.removeValue(forKey: "ELEVENLABS_API_KEY")
        } else {
            values["ELEVEN_LABS_API_KEY"] = cleanedAPIKey
        }
        if cleanedVoiceId.isEmpty {
            values.removeValue(forKey: "LITSCENES_CUSTOM_VOICE_ID")
            values.removeValue(forKey: "LITSCENES_KEVIN_VOICE_ID")
            values.removeValue(forKey: "ELEVEN_LABS_KEVIN_VOICE_ID")
            values.removeValue(forKey: "ELEVENLABS_KEVIN_VOICE_ID")
        } else {
            values["LITSCENES_CUSTOM_VOICE_ID"] = cleanedVoiceId
        }
        try OpenAIKeyStore.saveCredentialValues(values)
    }

    // MARK: Default narration voice (Voices tab)

    static func resolvedDefaultNarrationVoice() -> (voiceId: String, name: String)? {
        let values = loadDotEnv(from: OpenAIKeyStore.savedKeyURL)
        guard let voiceId = firstValue(in: values, keys: ["LITSCENES_DEFAULT_NARRATION_VOICE_ID"])
            ?? firstEnvironmentValue(keys: ["LITSCENES_DEFAULT_NARRATION_VOICE_ID"]) else {
            return nil
        }
        let name = firstValue(in: values, keys: ["LITSCENES_DEFAULT_NARRATION_VOICE_NAME"])
            ?? firstEnvironmentValue(keys: ["LITSCENES_DEFAULT_NARRATION_VOICE_NAME"])
            ?? ""
        return (voiceId, name)
    }

    static func saveDefaultNarrationVoice(voiceId: String, name: String) throws {
        var values = loadDotEnv(from: OpenAIKeyStore.savedKeyURL)
        let cleanedId = voiceId.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedId.isEmpty {
            values.removeValue(forKey: "LITSCENES_DEFAULT_NARRATION_VOICE_ID")
            values.removeValue(forKey: "LITSCENES_DEFAULT_NARRATION_VOICE_NAME")
        } else {
            values["LITSCENES_DEFAULT_NARRATION_VOICE_ID"] = cleanedId
            values["LITSCENES_DEFAULT_NARRATION_VOICE_NAME"] = cleanedName
        }
        try OpenAIKeyStore.saveCredentialValues(values)
    }

    // MARK: Hidden narration voices (Voices tab curation)

    /// Voice ids kept OUT of the render-time menus. Display-only curation —
    /// see THE VOICE CURATION LAW in `StoryAudioVoiceCatalog`. Stored beside
    /// the default-voice pair as one comma-separated local value.
    static func resolvedHiddenNarrationVoiceIds() -> Set<String> {
        let values = loadDotEnv(from: OpenAIKeyStore.savedKeyURL)
        let raw = firstValue(in: values, keys: ["LITSCENES_HIDDEN_NARRATION_VOICE_IDS"])
            ?? firstEnvironmentValue(keys: ["LITSCENES_HIDDEN_NARRATION_VOICE_IDS"])
            ?? ""
        return Set(
            raw.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    static func saveHiddenNarrationVoiceIds(_ voiceIds: Set<String>) throws {
        var values = loadDotEnv(from: OpenAIKeyStore.savedKeyURL)
        let cleaned = voiceIds
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
        if cleaned.isEmpty {
            values.removeValue(forKey: "LITSCENES_HIDDEN_NARRATION_VOICE_IDS")
        } else {
            values["LITSCENES_HIDDEN_NARRATION_VOICE_IDS"] = cleaned.joined(separator: ",")
        }
        try OpenAIKeyStore.saveCredentialValues(values)
    }

    private static func firstEnvironmentValue(keys: [String]) -> String? {
        for key in keys {
            if let value = environmentValue(key)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func firstValue(in values: [String: String], keys: [String]) -> String? {
        for key in keys {
            if let value = values[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        return nil
    }
}

struct ElevenLabsAudioResponse {
    var data: Data
    var contentType: String
    var requestId: String
    var characterCost: String
    var characterCount: String
    var responseBodySHA256: String
}

/// One voice from the account's GET /v1/voices listing.
struct ElevenLabsVoice: Codable, Hashable, Identifiable, Sendable {
    var voiceId: String
    var name: String = ""
    var category: String = ""
    var description: String = ""

    var id: String { voiceId }

    /// Matches a decoder that CONVERTS from snake_case — which the shared
    /// `JSONCoding.decoder` does, so `voice_id` arrives already spelled
    /// `voiceId`. Declaring `case voiceId = "voice_id"` here (the obvious
    /// reading of the wire format) made every id decode EMPTY under that
    /// decoder, and `listVoices` then filtered all 33 account voices away —
    /// a silent empty list behind an HTTP 200. The model now
    /// answers to both spellings so it can never again depend on which
    /// decoder happens to open it.
    private enum CodingKeys: String, CodingKey {
        case voiceId
        case name
        case category
        case description
    }

    /// Matches a decoder that does NOT convert (a plain `JSONDecoder`).
    private enum WireCodingKeys: String, CodingKey {
        case voiceId = "voice_id"
    }

    init(voiceId: String, name: String = "", category: String = "", description: String = "") {
        self.voiceId = voiceId
        self.name = name
        self.category = category
        self.description = description
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let converted = ((try? container.decodeIfPresent(String.self, forKey: .voiceId)) ?? nil) ?? ""
        if converted.isEmpty {
            let wire = try? decoder.container(keyedBy: WireCodingKeys.self)
            voiceId = ((try? wire?.decodeIfPresent(String.self, forKey: .voiceId)) ?? nil) ?? ""
        } else {
            voiceId = converted
        }
        name = ((try? container.decodeIfPresent(String.self, forKey: .name)) ?? nil) ?? ""
        category = ((try? container.decodeIfPresent(String.self, forKey: .category)) ?? nil) ?? ""
        description = ((try? container.decodeIfPresent(String.self, forKey: .description)) ?? nil) ?? ""
    }
}

struct ElevenLabsVoicesResponse: Codable {
    var voices: [ElevenLabsVoice] = []

    private enum CodingKeys: String, CodingKey {
        case voices
    }

    init(voices: [ElevenLabsVoice] = []) {
        self.voices = voices
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        voices = ((try? container.decodeIfPresent([ElevenLabsVoice].self, forKey: .voices)) ?? nil) ?? []
    }
}

struct ElevenLabsClient {
    var apiKey: String
    var baseURL: URL = URL(string: "https://api.elevenlabs.io")!

    static func fromEnvironment() throws -> ElevenLabsClient {
        let settings = try ElevenLabsSettingsStore.resolvedSettings()
        return ElevenLabsClient(apiKey: settings.apiKey)
    }

    func createSpeech(
        voiceId: String,
        text: String,
        modelId: String = ElevenLabsSpeechModels.defaultModelId,
        outputFormat: String = "mp3_44100_128",
        voiceSettings: ElevenLabsVoiceSettings? = nil,
        projectId: String = "",
        runId: String = ""
    ) async throws -> ElevenLabsAudioResponse {
        let url = try url(
            path: "/v1/text-to-speech/\(voiceId)",
            queryItems: [URLQueryItem(name: "output_format", value: outputFormat)]
        )
        var body: [String: Any] = [
            "text": text,
            "model_id": modelId
        ]
        if let voiceSettings {
            let settingsBody = voiceSettings.requestBody
            if !settingsBody.isEmpty {
                body["voice_settings"] = settingsBody
            }
        }
        return try await sendAudioRequest(
            url: url,
            body: body,
            metadata: InferenceTraceRequestMetadata(
                provider: "elevenlabs",
                apiFamily: "audio",
                operation: "text_to_speech",
                projectId: projectId,
                runId: runId,
                model: modelId,
                requestBodyFormat: "application/json",
                responseBodyFormatHint: "audio/mpeg",
                providerRequestIDHeaderCandidates: ["request-id", "x-request-id"]
            )
        )
    }

    func createSoundEffect(
        text: String,
        durationSeconds: Double,
        loop: Bool = true,
        promptInfluence: Double = 0.3,
        modelId: String = "eleven_text_to_sound_v2",
        outputFormat: String = "mp3_44100_128",
        projectId: String = "",
        runId: String = ""
    ) async throws -> ElevenLabsAudioResponse {
        let url = try url(
            path: "/v1/sound-generation",
            queryItems: [URLQueryItem(name: "output_format", value: outputFormat)]
        )
        return try await sendAudioRequest(
            url: url,
            body: [
                "text": text,
                "loop": loop,
                "duration_seconds": durationSeconds,
                "prompt_influence": promptInfluence,
                "model_id": modelId
            ],
            metadata: InferenceTraceRequestMetadata(
                provider: "elevenlabs",
                apiFamily: "audio",
                operation: "sound_generation",
                projectId: projectId,
                runId: runId,
                model: modelId,
                requestBodyFormat: "application/json",
                responseBodyFormatHint: "audio/mpeg",
                providerRequestIDHeaderCandidates: ["request-id", "x-request-id"]
            )
        )
    }

    /// Lists the account's voices (GET /v1/voices) — premade + cloned.
    func listVoices(projectId: String = "", runId: String = "") async throws -> [ElevenLabsVoice] {
        let requestURL = try url(path: "/v1/voices", queryItems: [])
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 60
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let result = try await TracedHTTPTransport.send(
            request: request,
            metadata: InferenceTraceRequestMetadata(
                provider: "elevenlabs",
                apiFamily: "voices",
                operation: "list_voices",
                projectId: projectId,
                runId: runId,
                requestBodyFormat: "none",
                responseBodyFormatHint: "application/json",
                providerRequestIDHeaderCandidates: ["request-id", "x-request-id"]
            )
        )
        let status = result.response?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let bodyText = String(data: result.data, encoding: .utf8) ?? ""
            if bodyText.contains("voices_read") || bodyText.contains("missing_permissions") {
                throw ScreenGraphError.openAI(
                    "Your ElevenLabs API key can't list voices — it's missing the voices_read permission. In the ElevenLabs dashboard, open Profile → API Keys, edit this key (or create one) with Voices read access, save it in App Settings, then reopen this tab. Narration with the built-in preset voices keeps working without it."
                )
            }
            throw ScreenGraphError.openAI("ElevenLabs voices request failed (\(status)): \(bodyText)")
        }
        let decoded: ElevenLabsVoicesResponse
        do {
            decoded = try JSONCoding.decoder.decode(ElevenLabsVoicesResponse.self, from: result.data)
        } catch {
            throw ScreenGraphError.openAI("ElevenLabs voices response could not be read: \(error.localizedDescription)")
        }
        return decoded.voices.filter { !$0.voiceId.trimmed.isEmpty }
    }

    private func url(path: String, queryItems: [URLQueryItem]) throws -> URL {
        guard var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false) else {
            throw ScreenGraphError.credentials("ElevenLabs URL is invalid.")
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw ScreenGraphError.credentials("ElevenLabs URL is invalid.")
        }
        return url
    }

    private func sendAudioRequest(
        url: URL,
        body: [String: Any],
        metadata: InferenceTraceRequestMetadata
    ) async throws -> ElevenLabsAudioResponse {
        let requestData = try JSONSerialization.data(withJSONObject: body)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.httpBody = requestData

        let result = try await TracedHTTPTransport.send(request: request, metadata: metadata)
        let data = result.data
        let httpResponse = result.response
        let status = httpResponse?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw ScreenGraphError.openAI("ElevenLabs request failed (\(status)): \(bodyText)")
        }

        let requestId = header("request-id", in: httpResponse) ?? header("x-request-id", in: httpResponse) ?? ""
        await InferenceTraceStore.shared.enrich(
            traceId: result.traceId,
            providerRequestId: requestId,
            model: metadata.model
        )
        return ElevenLabsAudioResponse(
            data: data,
            contentType: header("content-type", in: httpResponse) ?? "audio/mpeg",
            requestId: requestId,
            characterCost: header("character-cost", in: httpResponse) ?? "",
            characterCount: header("x-character-count", in: httpResponse) ?? "",
            responseBodySHA256: sha256Hex(data)
        )
    }

    private func header(_ name: String, in response: HTTPURLResponse?) -> String? {
        guard let headers = response?.allHeaderFields else { return nil }
        let lowered = name.lowercased()
        for (key, value) in headers where String(describing: key).lowercased() == lowered {
            return String(describing: value)
        }
        return nil
    }
}
