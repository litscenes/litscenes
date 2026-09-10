import Foundation

/// A saved creative checkpoint, independent of generated image versions.
struct CharacterPromptVersion: Codable, Hashable, Identifiable, Sendable {
    var versionId: String
    var prompt: String
    var source: String
    var summary: String
    var createdAt: String
    var parentVersionId: String = ""
    var chatTurnId: String = ""
    var isProposal: Bool = false

    var id: String { versionId }
    var dateLabel: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: createdAt) else { return createdAt }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    var sourceLabel: String {
        switch source {
        case "chat": return "Chat"
        case "manual": return "Your edit"
        case "restore": return "Restored"
        case "legacy_sheet": return "Archived sheet prompt"
        case "identity": return "Story update"
        default: return "Existing description"
        }
    }
}

struct CharacterPromptHistory: Codable, Hashable, Sendable {
    var versions: [CharacterPromptVersion] = []
    var activeVersionId: String = ""
    /// Each saved output keeps the creative revision used by its submitted request.
    var mediaVersionIds: [String: String] = [:]

    var activeVersion: CharacterPromptVersion? { versions.first { $0.id == activeVersionId } }
    var activeOrdinal: Int? { versions.firstIndex { $0.id == activeVersionId }.map { $0 + 1 } }

    @discardableResult
    mutating func append(
        prompt: String, source: String, summary: String = "", parentVersionId: String? = nil,
        chatTurnId: String = "", activate: Bool = true, now: String = DateFormats.now()
    ) -> CharacterPromptVersion {
        let version = CharacterPromptVersion(
            versionId: "cprompt_\(UUID().uuidString.lowercased())", prompt: prompt.trimmed,
            source: source, summary: summary, createdAt: now,
            parentVersionId: parentVersionId ?? activeVersionId,
            chatTurnId: chatTurnId, isProposal: !activate && source == "chat"
        )
        versions.append(version)
        if activate { activeVersionId = version.id }
        return version
    }
}

extension ProjectCharacter {
    /// Explicit, local migration on entering the smart-prompt workflow. Old output
    /// overrides remain readable in history, without overriding the shared subject.
    mutating func adoptSmartPrompt(now: String = DateFormats.now()) {
        guard promptHistory == nil else { return }
        var history = CharacterPromptHistory()
        var parts = [descriptionPrompt.trimmed]
        if !signatureProps.isEmpty { parts.append("Always present: " + signatureProps.joined(separator: "; ") + ".") }
        if !sheetDirectives.isEmpty { parts.append(sheetDirectives.joined(separator: "\n")) }
        let initial = parts.filter { !$0.isEmpty }.joined(separator: "\n\n")
        if !initial.isEmpty { history.append(prompt: initial, source: "legacy", now: now) }
        if let custom = sheetPromptOverride, !custom.trimmed.isEmpty {
            history.append(prompt: custom, source: "legacy_sheet", summary: "Previous custom sheet prompt; retained for reference.", activate: false, now: now)
        }
        promptHistory = history
        descriptionPrompt = initial
        sheetPromptOverride = nil
        sheetPromptOverrideBaseHash = ""
    }

    /// The submitted base determines whether a chat result can become current.
    /// A conflicting result is retained as a proposal in the same history.
    @discardableResult
    mutating func reviseSmartPrompt(
        _ prompt: String, source: String, summary: String = "", baseVersionId: String? = nil,
        chatTurnId: String = "", now: String = DateFormats.now()
    ) -> Bool {
        adoptSmartPrompt(now: now)
        guard var history = promptHistory else { return false }
        let activate = baseVersionId == nil || baseVersionId == history.activeVersionId
        if activate, prompt.trimmed == history.activeVersion?.prompt { return true }
        history.append(prompt: prompt, source: source, summary: summary, parentVersionId: baseVersionId,
                       chatTurnId: chatTurnId, activate: activate, now: now)
        promptHistory = history
        if activate { descriptionPrompt = prompt.trimmed }
        return activate
    }

    mutating func restoreSmartPrompt(versionId: String) {
        guard let version = promptHistory?.versions.first(where: { $0.id == versionId }) else { return }
        let ordinal = promptHistory?.versions.firstIndex { $0.id == versionId }.map { $0 + 1 } ?? 1
        // Restoring even identical text is an intentional checkpoint: it invalidates
        // an outstanding chat's old base without deleting either branch.
        promptHistory?.append(prompt: version.prompt, source: "restore", summary: "Restored version \(ordinal).", parentVersionId: version.id)
        descriptionPrompt = version.prompt
    }

    /// Preserve revision order and newer edits when an unrelated background writer
    /// saves an older character snapshot. Explicit revisions retain their intent.
    mutating func reconcileSmartPromptHistory(with current: ProjectCharacter?) {
        if let current, let saved = current.promptHistory {
            var history = promptHistory ?? saved
            let savedIds = Set(saved.versions.map(\.id))
            let additions = history.versions.filter { !savedIds.contains($0.id) }
            if promptHistory?.activeVersionId != saved.activeVersionId, additions.isEmpty {
                history.activeVersionId = saved.activeVersionId
                descriptionPrompt = current.descriptionPrompt
            }
            history.versions = saved.versions + additions
            history.mediaVersionIds = saved.mediaVersionIds.merging(history.mediaVersionIds) { _, incoming in incoming }
            promptHistory = history
        }
        if let history = promptHistory, descriptionPrompt.trimmed != (history.activeVersion?.prompt ?? "") {
            reviseSmartPrompt(descriptionPrompt, source: "identity")
        }
    }

    func promptVersionLabel(for mediaId: String) -> String? {
        guard let history = promptHistory, let versionId = history.mediaVersionIds[mediaId],
              let index = history.versions.firstIndex(where: { $0.id == versionId }) else { return nil }
        return "Prompt v\(index + 1)"
    }
}
