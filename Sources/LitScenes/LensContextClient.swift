import Foundation

struct LensContextErrorResponse: Codable {
    var error: String
    var requestId: String?
}

struct LensContextClient: Sendable {
    private let endpointURL: URL
    private let token: String
    private let session: URLSession

    init(endpointURL: URL, token: String, session: URLSession = .shared) {
        self.endpointURL = endpointURL
        self.token = token
        self.session = session
    }

    static func fromEnvironment() throws -> LensContextClient {
        let credentialStore = LitScenesCredentialStore()
        let rawURL = credentialStore
            .resolvedCredentialValue(forKeys: LensContextCredential.endpointURL.keyCandidates)
            .trimmed
        let rawToken = credentialStore
            .resolvedCredentialValue(forKeys: LensContextCredential.token.keyCandidates)
            .trimmed

        guard !rawURL.isEmpty else {
            throw ScreenGraphError.credentials("LITSCENES_LENS_CONTEXT_URL is not configured.")
        }
        guard !rawToken.isEmpty else {
            throw ScreenGraphError.credentials("LITSCENES_LENS_CONTEXT_TOKEN is not configured.")
        }
        guard let url = URL(string: rawURL),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              url.host != nil else {
            throw ScreenGraphError.credentials("LITSCENES_LENS_CONTEXT_URL is invalid.")
        }
        return LensContextClient(endpointURL: url, token: rawToken)
    }

    func resolve(_ payload: LensContextResolveRequest) async throws -> LensContextResolveResponse {
        var request = URLRequest(url: resolveURL)
        let requestId = "desktop_\(UUID().uuidString.lowercased())"
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(requestId, forHTTPHeaderField: "X-Request-Id")
        request.httpBody = try JSONCoding.encoder.encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ScreenGraphError.openAI("Frame Context response was not HTTP. request_id=\(requestId)")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = decodedErrorMessage(from: data)
            throw ScreenGraphError.openAI(
                "Frame Context request failed (\(httpResponse.statusCode)) request_id=\(requestId): \(message)"
            )
        }
        do {
            return try JSONCoding.decoder.decode(LensContextResolveResponse.self, from: data)
        } catch {
            throw ScreenGraphError.openAI(decodeFailureMessage(
                label: "Frame Context",
                error: error,
                requestId: requestId,
                statusCode: httpResponse.statusCode,
                contentType: httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "",
                data: data
            ))
        }
    }

    func generateSceneStorySet(_ payload: SceneStoryGenerateRequest) async throws -> SceneStoryGenerateResult {
        var request = URLRequest(url: sceneStoryGenerateURL)
        let requestId = "desktop_\(UUID().uuidString.lowercased())"
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(requestId, forHTTPHeaderField: "X-Request-Id")
        request.httpBody = try JSONCoding.encoder.encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ScreenGraphError.openAI("SceneStory response was not HTTP. request_id=\(requestId)")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = decodedErrorMessage(from: data)
            throw ScreenGraphError.openAI(
                "SceneStory request failed (\(httpResponse.statusCode)) request_id=\(requestId): \(message)"
            )
        }
        do {
            if let envelope = try? JSONCoding.decoder.decode(SceneStorySetEnvelope.self, from: data),
               !envelope.document.sceneStories.isEmpty {
                return SceneStoryGenerateResult(
                    document: envelope.document.normalized(),
                    provenance: envelope.provenance.normalized(),
                    hostedRequestId: requestId
                )
            }
            return SceneStoryGenerateResult(
                document: try SceneStorySetDocument.decode(from: data),
                provenance: SceneStoryGenerationProvenance(),
                hostedRequestId: requestId
            )
        } catch {
            throw ScreenGraphError.openAI(decodeFailureMessage(
                label: "SceneStory",
                error: error,
                requestId: requestId,
                statusCode: httpResponse.statusCode,
                contentType: httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "",
                data: data
            ))
        }
    }

    func generateFrameForms(_ payload: FrameFormsGenerateRequest) async throws -> FrameFormsGenerateResponse {
        var request = URLRequest(url: frameFormsGenerateURL)
        let requestId = "desktop_\(UUID().uuidString.lowercased())"
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(requestId, forHTTPHeaderField: "X-Request-Id")
        request.httpBody = try JSONCoding.encoder.encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ScreenGraphError.openAI("Frame Forms response was not HTTP. request_id=\(requestId)")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = decodedErrorMessage(from: data)
            throw ScreenGraphError.openAI(
                "Frame Forms request failed (\(httpResponse.statusCode)) request_id=\(requestId): \(message)"
            )
        }
        do {
            return try JSONCoding.decoder.decode(FrameFormsGenerateResponse.self, from: data)
        } catch {
            throw ScreenGraphError.openAI(decodeFailureMessage(
                label: "Frame Forms",
                error: error,
                requestId: requestId,
                statusCode: httpResponse.statusCode,
                contentType: httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "",
                data: data
            ))
        }
    }

    private var resolveURL: URL {
        let targetPath = "/lens-context/resolve"
        if endpointURL.path == targetPath || endpointURL.path.hasSuffix(targetPath) {
            return endpointURL
        }
        return serviceRootURL.appendingPathComponent("lens-context").appendingPathComponent("resolve")
    }

    private var frameFormsGenerateURL: URL {
        let targetPath = "/frame-forms/generate"
        if endpointURL.path == targetPath || endpointURL.path.hasSuffix(targetPath) {
            return endpointURL
        }
        return serviceRootURL.appendingPathComponent("frame-forms").appendingPathComponent("generate")
    }

    private var sceneStoryGenerateURL: URL {
        let targetPath = "/scene-story/generate"
        if endpointURL.path == targetPath || endpointURL.path.hasSuffix(targetPath) {
            return endpointURL
        }
        return serviceRootURL.appendingPathComponent("scene-story").appendingPathComponent("generate")
    }

    private var serviceRootURL: URL {
        let knownSuffixes = [
            "/lens-context/resolve",
            "/scene-story/generate",
            "/frame-forms/generate"
        ]
        for suffix in knownSuffixes where endpointURL.path == suffix || endpointURL.path.hasSuffix(suffix) {
            return endpointURL.deletingLastPathComponent().deletingLastPathComponent()
        }
        return endpointURL
    }

    private func decodedErrorMessage(from data: Data) -> String {
        if let response = try? JSONCoding.decoder.decode(LensContextErrorResponse.self, from: data),
           !response.error.trimmed.isEmpty {
            return response.error
        }
        let text = String(data: data, encoding: .utf8)?.trimmed ?? ""
        return text.isEmpty ? "empty response" : lensContextClientShortSummaryText(text, limit: 240)
    }

    private func decodeFailureMessage(
        label: String,
        error: Error,
        requestId: String,
        statusCode: Int,
        contentType: String,
        data: Data
    ) -> String {
        let digest = data.isEmpty ? "" : sha256Hex(data)
        let contentTypeSummary = contentType.trimmed.isEmpty ? "unknown" : contentType.trimmed
        let path = lensContextDecodingPath(error)
        let pathSummary = path.isEmpty ? "unknown" : path
        return "\(label) response could not be read: \(error.localizedDescription) request_id=\(requestId) status_code=\(statusCode) content_type=\(contentTypeSummary) response_bytes=\(data.count) response_sha256=\(digest) decode_path=\(pathSummary)"
    }
}

private func lensContextClientShortSummaryText(_ value: String, limit: Int) -> String {
    let compact = value
        .split(whereSeparator: { $0.isWhitespace })
        .joined(separator: " ")
    guard compact.count > limit else { return compact }
    return String(compact.prefix(max(0, limit - 1))) + "..."
}

private func lensContextDecodingPath(_ error: Error) -> String {
    let codingPath: [CodingKey]
    switch error {
    case DecodingError.typeMismatch(_, let context):
        codingPath = context.codingPath
    case DecodingError.valueNotFound(_, let context):
        codingPath = context.codingPath
    case DecodingError.keyNotFound(let key, let context):
        codingPath = context.codingPath + [key]
    case DecodingError.dataCorrupted(let context):
        codingPath = context.codingPath
    default:
        return ""
    }
    return codingPath.map { key in
        if let index = key.intValue {
            return "[\(index)]"
        }
        return key.stringValue
    }.joined(separator: ".")
}
