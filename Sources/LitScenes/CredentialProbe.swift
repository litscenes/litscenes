import Foundation

/// Result of a zero-spend authenticated ping against a provider. The law:
/// a transport failure is never reported as a rejected key — `.unreachable`
/// absorbs every timeout, offline, and unexpected-status outcome.
enum CredentialProbeOutcome: Equatable, Sendable {
    case valid
    case invalidKey(httpStatus: Int)
    case unreachable(detail: String)
}

/// Cheap authenticated GETs proving a key is actually usable — the Settings
/// "Configured" capsule only means non-empty. Probes exist for the three
/// first-run providers; every other key proves itself at first real use.
struct CredentialProbe: Sendable {
    var session: URLSession = .shared

    static let timeout: TimeInterval = 8
    static let supportedProviders: Set<LitScenesProviderCredential> = [.openAI, .fal, .elevenLabs]

    /// Any real FAL endpoint id satisfies the pricing lookup; deriving it
    /// from the fallback stack avoids hardcoding a driftable slug.
    static var falProbeEndpointId: String {
        ShotRenderStack.fallback.pairedModelSelection.providerModelId
    }

    static func request(for provider: LitScenesProviderCredential, apiKey: String) throws -> URLRequest {
        switch provider {
        case .openAI:
            let base = try OpenAITextEndpointSettings.baseURL()
            let url = base.map { OpenAITextEndpointSettings.endpoint(base: $0, path: "models") }
                ?? URL(string: "https://api.openai.com/v1/models")!
            var request = URLRequest(url: url, timeoutInterval: timeout)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            return request
        case .fal:
            var components = URLComponents(string: "https://api.fal.ai/v1/models/pricing")!
            components.queryItems = [URLQueryItem(name: "endpoint_id", value: falProbeEndpointId)]
            var request = URLRequest(url: components.url!, timeoutInterval: timeout)
            request.setValue("Key \(apiKey)", forHTTPHeaderField: "Authorization")
            return request
        case .elevenLabs:
            var request = URLRequest(
                url: URL(string: "https://api.elevenlabs.io/v1/user")!,
                timeoutInterval: timeout
            )
            request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            return request
        case .ltx, .civitai, .decart, .kling, .stability:
            throw ScreenGraphError.credentials("\(provider.label) keys have no probe endpoint.")
        }
    }

    static func outcome(forHTTPStatus status: Int) -> CredentialProbeOutcome {
        switch status {
        case 200..<300:
            return .valid
        case 401, 403:
            return .invalidKey(httpStatus: status)
        case 429:
            // A throttle means auth passed.
            return .valid
        default:
            return .unreachable(detail: "Unexpected response (HTTP \(status))")
        }
    }

    func probe(_ provider: LitScenesProviderCredential, apiKey: String) async -> CredentialProbeOutcome {
        let key = apiKey.trimmed
        guard !key.isEmpty else { return .invalidKey(httpStatus: 0) }
        do {
            let request = try Self.request(for: provider, apiKey: key)
            let (_, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return Self.outcome(forHTTPStatus: status)
        } catch {
            return .unreachable(detail: error.localizedDescription)
        }
    }
}
