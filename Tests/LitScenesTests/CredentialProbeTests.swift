import Foundation
import Testing
@testable import LitScenes

// MARK: - Status-code mapping

@Test
func successStatusesReadAsValid() {
    #expect(CredentialProbe.outcome(forHTTPStatus: 200) == .valid)
    #expect(CredentialProbe.outcome(forHTTPStatus: 204) == .valid)
}

@Test
func authRejectionsReadAsInvalidKey() {
    #expect(CredentialProbe.outcome(forHTTPStatus: 401) == .invalidKey(httpStatus: 401))
    #expect(CredentialProbe.outcome(forHTTPStatus: 403) == .invalidKey(httpStatus: 403))
}

@Test
func throttleProvesAuthPassed() {
    // 429 means the key was accepted and then rate-limited — never a bad key.
    #expect(CredentialProbe.outcome(forHTTPStatus: 429) == .valid)
}

@Test
func everythingElseIsUnreachableNeverInvalid() {
    // The law: a transport or server problem must never read as a rejected
    // key. Only explicit auth statuses may.
    for status in [0, 400, 404, 422, 500, 502, 503] {
        switch CredentialProbe.outcome(forHTTPStatus: status) {
        case .unreachable:
            break
        case .valid, .invalidKey:
            Issue.record("HTTP \(status) must map to .unreachable")
        }
    }
}

// MARK: - Request specs

@Test
func openAIProbeRequestShape() throws {
    let request = try CredentialProbe.request(for: .openAI, apiKey: "sk-test")
    #expect(request.httpMethod == "GET")
    #expect(request.timeoutInterval == CredentialProbe.timeout)
    // The host may be an OPENAI_BASE_URL gateway on a configured machine;
    // the /models path and bearer auth are the stable contract.
    let url = try #require(request.url?.absoluteString)
    #expect(url.hasSuffix("/models"))
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
}

@Test
func falProbeRequestShape() throws {
    let request = try CredentialProbe.request(for: .fal, apiKey: "fal-test")
    #expect(request.httpMethod == "GET")
    #expect(request.timeoutInterval == CredentialProbe.timeout)
    let url = try #require(request.url)
    #expect(url.absoluteString.hasPrefix("https://api.fal.ai/v1/models/pricing?endpoint_id="))
    #expect(!CredentialProbe.falProbeEndpointId.isEmpty)
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Key fal-test")
}

@Test
func elevenLabsProbeRequestShape() throws {
    let request = try CredentialProbe.request(for: .elevenLabs, apiKey: "el-test")
    #expect(request.httpMethod == "GET")
    #expect(request.timeoutInterval == CredentialProbe.timeout)
    #expect(request.url?.absoluteString == "https://api.elevenlabs.io/v1/user")
    #expect(request.value(forHTTPHeaderField: "xi-api-key") == "el-test")
}

@Test
func unsupportedProvidersHaveNoProbe() {
    for provider in LitScenesProviderCredential.allCases
    where !CredentialProbe.supportedProviders.contains(provider) {
        #expect(throws: (any Error).self) {
            _ = try CredentialProbe.request(for: provider, apiKey: "x")
        }
    }
}
