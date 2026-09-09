import Foundation

/// Match the same saved fields as the durable history query, including outcomes.
func workflowMatchesSearch(_ job: WorkflowJob, query: String) -> Bool {
    guard !query.isEmpty else { return true }
    guard let data = try? JSONEncoder().encode(job) else { return false }
    return String(decoding: data, as: UTF8.self).replacingOccurrences(of: "_", with: " ")
        .localizedCaseInsensitiveContains(query)
}

func workflowProviderError(_ root: [String: Any]) -> String? {
    if let detail = root["detail"] as? String { return detail }
    if let error = root["error"] as? String { return error }
    for key in ["error", "detail"] {
        if let value = root[key] as? [String: Any], let message = value["message"] as? String { return message }
    }
    if let details = root["detail"] as? [[String: Any]] {
        let messages = details.compactMap { $0["msg"] as? String ?? $0["message"] as? String }
        if !messages.isEmpty { return messages.joined(separator: "; ") }
    }
    return root["message"] as? String
}


struct WorkflowLogEvidence: Decodable, Sendable {
    var jobId: String
    var eventMessage: String?
    var providerResponse: String?
    var failure: String? {
        if let providerResponse, let root = workflowJSONObject(providerResponse), let error = workflowProviderError(root) { return error }
        return eventMessage
    }
}

func workflowJSONObject(_ text: String) -> [String: Any]? {
    (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
}

struct WorkflowLogField: Identifiable, Hashable {
    var label: String
    var value: String
    var id: String { label + ":" + value }
}

struct WorkflowTraceRecord: Sendable, Identifiable {
    var rawJSON: String
    private var root: [String: Any] { workflowJSONObject(rawJSON) ?? [:] }
    var id: String { root["trace_id"] as? String ?? rawJSON }
    var createdAt: String { root["created_at"] as? String ?? "" }
    var operation: String { root["operation"] as? String ?? "Request" }
    var provider: String { root["provider"] as? String ?? "" }
    var model: String { root["model"] as? String ?? "" }
    var status: Int { (root["status_code"] as? NSNumber)?.intValue ?? 0 }
    var milliseconds: Int { (root["latency_ms"] as? NSNumber)?.intValue ?? 0 }
    var request: String { root["request"] as? String ?? "" }
    var response: String { root["response"] as? String ?? "" }
    var parsedOutput: String { root["parsed_output"] as? String ?? "" }
    var error: String {
        if let text = root["error"] as? String, !text.isEmpty { return text }
        return status >= 400 ? workflowJSONObject(response).flatMap(workflowProviderError) ?? "HTTP \(status)" : ""
    }
    var inputFields: [WorkflowLogField] { workflowLogFields(request, output: false) }
    var outputFields: [WorkflowLogField] {
        workflowLogFields(parsedOutput.isEmpty ? response : parsedOutput, output: true)
    }
}

/// Project-neutral structured projection; creative text is never classified.
func workflowLogFields(_ json: String, output: Bool) -> [WorkflowLogField] {
    guard let root = try? JSONSerialization.jsonObject(with: Data(json.utf8)) else { return [] }
    let labels = output
        ? ["text": "Generated text", "output_text": "Generated text", "prompt": "Generated prompt",
           "content": "Generated text", "message": "Result", "summary": "Summary", "direction": "Direction"]
        : ["prompt": "Provider prompt", "operator_prompt": "Written direction", "operatorPrompt": "Written direction",
           "source_prompt": "Source prompt", "negative_prompt": "Negative prompt", "text": "Prompt text",
           "input": "Prompt", "instructions": "Instructions", "content": "Prompt text",
           "duration": "Duration", "duration_seconds": "Duration", "durationSeconds": "Duration",
           "resolution": "Resolution", "aspect_ratio": "Aspect ratio", "generate_audio": "Audio",
           "generateAudio": "Audio", "seed": "Seed", "intent": "Assistance", "model": "Model"]
    var fields: [WorkflowLogField] = []
    func visit(_ value: Any) {
        if let array = value as? [Any] { array.forEach(visit); return }
        guard let object = value as? [String: Any] else { return }
        for key in object.keys.sorted() {
            guard let value = object[key] else { continue }
            if let label = labels[key], let text = value as? String, !text.isEmpty,
               !text.hasPrefix("data:"), !text.hasPrefix("https://"), !text.hasPrefix("http://") {
                fields.append(WorkflowLogField(label: label, value: WorkflowPrivacy.text(text)))
            } else if let label = labels[key], let number = value as? NSNumber {
                fields.append(WorkflowLogField(label: label, value: number.stringValue))
            } else if value is [String: Any] || value is [Any] { visit(value) }
        }
    }
    visit(root)
    var seen: Set<String> = []
    return fields.filter { seen.insert($0.id).inserted }
}

func workflowLocalDate(_ text: String) -> String {
    guard let date = workflowDate(text) else { return text }
    return date.formatted(date: .abbreviated, time: .standard)
}
func workflowDate(_ text: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
}
func workflowElapsed(_ job: WorkflowJob, now: Date = Date()) -> String {
    guard let start = workflowDate(job.createdAt) else { return "" }
    let end = job.completedAt.flatMap(workflowDate)
        ?? (job.state.isTerminal ? workflowDate(job.updatedAt) : nil) ?? now
    let seconds = max(0, Int(end.timeIntervalSince(start)))
    return seconds < 60 ? "\(seconds)s" : "\(seconds / 60)m \(seconds % 60)s"
}
func workflowProviderLabel(_ provider: String) -> String {
    if provider.hasPrefix("fal") { return "FAL" }
    switch provider {
    case "openai": return "OpenAI"
    case "elevenlabs": return "ElevenLabs"
    case "local": return "Local"
    default: return provider
    }
}
func workflowModelLabel(_ job: WorkflowJob) -> String {
    let models = (job.segmentProgress ?? []).filter(\.isGeneration).map(\.model).filter { !$0.isEmpty }
    var seen: Set<String> = []
    let labels = models.filter { seen.insert($0).inserted }
    if !labels.isEmpty { return labels.joined(separator: " + ") }
    let label = shotClipModelShortLabel(provider: job.provider, model: job.model)
    return job.model.isEmpty ? "" : label
}
func workflowCostLabel(_ job: WorkflowJob) -> String {
    let entries = job.spendEntries ?? []
    let priced = entries.compactMap(\.estimatedUSD)
    var parts: [String] = []
    if !priced.isEmpty {
        parts.append(String(format: "Est. $%.2f", priced.reduce(0, +)) + (priced.count < entries.count ? " + unpriced work" : ""))
    }
    if entries.contains(where: \.isFailure) || job.submissionUncertain { parts.append("Charge unknown") }
    else if priced.isEmpty, !job.provider.isEmpty, job.provider != "local" { parts.append("Cost not recorded") }
    return parts.joined(separator: " · ")
}
func workflowOutcomeLabel(_ job: WorkflowJob, evidence: WorkflowLogEvidence?) -> String {
    if job.state == .failed {
        return job.outcomeMessage?.trimmed.nilIfEmpty ?? evidence?.failure?.trimmed.nilIfEmpty
            ?? "This operation failed. Open details for the saved activity."
    }
    if let outcome = job.outcomeMessage, !outcome.isEmpty, job.state.isTerminal { return outcome }
    if job.state == .succeeded, job.workflow == "shot_prompt_assistance" {
        let intent = workflowJSONObject(job.recipeJSON)?["intent"] as? String
        return intent == "improve" ? "Improved direction generated" : "Suggested direction generated"
    }
    if !job.state.isTerminal { return job.reason.isEmpty ? job.phase : job.reason }
    return job.state == .canceled ? "Canceled · completed outputs kept" : "Completed"
}
