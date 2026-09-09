import Foundation

/// Durable operational state is separate from the creative artifact it produces.
enum WorkflowState: String, Codable, CaseIterable, Sendable {
    case queued, running, stopping, succeeded, failed, canceled, pausedAutomatically

    var label: String {
        switch self {
        case .pausedAutomatically: return "Paused automatically"
        default: return rawValue.capitalized
        }
    }
    var isTerminal: Bool { [.succeeded, .failed, .canceled].contains(self) }
}

enum WorkflowLane: String, Codable, CaseIterable, Sendable {
    case image, video, text, audio, local
    var capacity: Int {
        switch self {
        case .image: return 8
        case .video, .text: return 3
        case .audio, .local: return 2
        }
    }
}

struct WorkflowJob: Codable, Identifiable, Sendable {
    var id = UUID().uuidString.lowercased()
    var projectId: String
    var projectName: String
    var workflow: String
    var artifactType: String
    var artifactId: String
    var lane: WorkflowLane
    var state: WorkflowState = .queued
    var phase = "Waiting for capacity"
    var provider = ""
    var model = ""
    var createdAt = DateFormats.now()
    var updatedAt = DateFormats.now()
    var reason = ""
    var recipeJSON = ""
    var traceIds: [String] = []
    var providerRequestId = ""
    var submissionUncertain = false
    var requiresReview = false
    var spendEntries: [SpendLedgerEntry]?
    var schemaVersion: Int? = 1
    var submissionKey: String?
    var artifactLabel: String?
    var outcomeMessage: String?
    var completedAt: String?
    var segmentProgress: [WorkflowSegmentProgress]?
    var currentSegmentKey: String?

    var label: String {
        workflow.replacingOccurrences(of: "_", with: " ").capitalized
    }
    var conflictKey: String {
        guard !artifactId.isEmpty else { return "" }
        return "\(projectId):\(artifactType):\(artifactId)"
    }
}

struct WorkflowEvent: Codable, Identifiable, Sendable {
    var id = UUID().uuidString.lowercased()
    var jobId: String
    var timestamp = DateFormats.now()
    var state: WorkflowState
    var phase: String
    var message: String = ""
    var traceId: String = ""
    var kind: String? = nil
    var segment: WorkflowSegmentProgress? = nil
}

struct WorkflowContext: Sendable {
    var jobId: String
    var projectId: String
    var workflow: String
    var artifactType: String
    var artifactId: String
    var lane: WorkflowLane
    @TaskLocal static var current: WorkflowContext?
}

/// Classification uses structured status/codes, never creative prompt text.
struct ProviderFailure: Error, LocalizedError, Sendable {
    var provider: String
    var statusCode: Int
    var code: String
    var message: String
    var accountBlocked: Bool
    var transient: Bool
    var acceptanceUnknown: Bool
    var errorDescription: String? { message }

    static func classify(provider: String, status: Int, data: Data, submission: Bool) -> ProviderFailure? {
        guard status >= 400 else { return nil }
        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let error = root["error"] as? [String: Any] ?? root["detail"] as? [String: Any] ?? root
        let code = (error["code"] as? String ?? error["type"] as? String ?? error["status"] as? String ?? "").lowercased()
        let fundingCodes: Set<String> = ["insufficient_quota", "insufficient_funds", "insufficient_credits", "quota_exceeded", "credit_balance_too_low", "billing_hard_limit_reached", "billing_not_active", "out_of_credits", "payment_required"]
        let funding = status == 402 || fundingCodes.contains(code)
        let auth = status == 401 || (status == 403 && ["invalid_api_key", "authentication_error", "permission_denied"].contains(code))
        let transient = [408, 429, 500, 502, 503, 504, 529].contains(status) && !funding
        let message = funding ? "The vendor account needs funds or quota."
            : auth ? "The vendor credential needs attention."
            : "The vendor returned HTTP \(status)\(code.isEmpty ? "" : " (\(code))")."
        return ProviderFailure(provider: provider, statusCode: status, code: code,
            message: message, accountBlocked: funding || auth, transient: transient,
            acceptanceUnknown: submission && (status == 408 || status >= 500))
    }
}

/// Safe projections are used at both persistence and presentation boundaries.
enum WorkflowPrivacy {
    static func text(_ text: String) -> String {
        var result = text
        for pattern in [#"(?i)(bearer\s+|(?:api[_-]?key|access[_-]?token|token|secret)\s*[:=]\s*[\"']?)[^\s,\"'}]+"#,
                        #"https?://[^\s\"<>]+\?[^\s\"<>]+"#,
                        #"/Users/[^/\s]+/"#] {
            result = result.replacingOccurrences(of: pattern, with: "[redacted]", options: .regularExpression)
        }
        return result
    }
    static func url(_ url: URL?) -> String {
        guard let url, var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return "" }
        parts.user = nil; parts.password = nil; parts.query = nil; parts.fragment = nil
        return parts.string ?? ""
    }
    static func mediaReference(_ value: String) -> String {
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), let host = url.host else {
            return text(value)
        }
        return "[media reference: \(host), sha256=\(sha256Hex(Data(value.utf8)))]"
    }
    static func json(_ text: String) -> String {
        guard let data = text.data(using: .utf8), let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return self.text(text)
        }
        guard let safe = try? JSONSerialization.data(withJSONObject: sanitize(value), options: [.sortedKeys, .fragmentsAllowed]) else { return "" }
        return String(decoding: safe, as: UTF8.self)
    }
    static func body(_ data: Data) -> Data {
        guard !data.isEmpty, let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let safe = try? JSONSerialization.data(withJSONObject: sanitize(value), options: [.sortedKeys, .fragmentsAllowed]) else { return Data() }
        return safe
    }
    private static func sanitize(_ value: Any) -> Any {
        if let map = value as? [String: Any] {
            return map.mapValues { $0 }.reduce(into: [String: Any]()) { output, item in
                let key = item.key.lowercased()
                if ["authorization", "api_key", "apikey", "token", "access_token", "secret", "password", "cookie", "email", "phone", "phone_number", "b64_json", "base64", "audio_base64", "image_base64"].contains(key) {
                    output[item.key] = "[redacted]"
                } else if (key.contains("url") || key.contains("uri")), let value = item.value as? String {
                    output[item.key] = mediaReference(value)
                } else { output[item.key] = sanitize(item.value) }
            }
        }
        if let list = value as? [Any] { return list.map(sanitize) }
        if let string = value as? String {
            if string.hasPrefix("data:") { return "[media omitted]" }
            return text(string)
        }
        return value
    }
}

func workflowRecipe<T: Encodable>(_ value: T) -> String {
    guard let data = try? JSONEncoder().encode(value) else { return "" }
    return String(decoding: data, as: UTF8.self)
}

protocol WorkflowOutcomeReporting {
    var workflowSucceeded: Bool { get }
}

extension Result: WorkflowOutcomeReporting {
    var workflowSucceeded: Bool {
        if case .success = self { return true }
        return false
    }
}
