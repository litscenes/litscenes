import Foundation

/// Resolves `@Name` mentions of roster characters/objects in free prompt text.
///
/// Matching is case-insensitive, longest-name-first (so "@Kai Aloha" wins over a
/// roster "Kai"), and requires a word boundary after the name ("@Kaiser" never
/// matches "Kai"). `resolve` also produces the prompt to submit: each `@Name`
/// becomes the canonical roster name, because the mention's real effect is the
/// attached reference images — the model only needs the plain name in prose.
enum RosterMentionResolver {
    enum EntryKind: String {
        case character
        case object
        case place
    }

    /// A mentionable roster entry, kind-agnostic (mirrors the roster documents).
    struct Entry: Identifiable, Hashable {
        let id: String
        let name: String
        let kind: EntryKind
        /// Historical structured names for this same stable roster id. These
        /// resolve old planned-frame prompts after a roster rename, but the
        /// submitted prompt and attachment descriptor always use `name`.
        var aliases: [String] = []
        var referenceMediaIds: [String] = []
        var referenceLabels: [String: String] = [:]
        /// The generated character sheet that anchors this entry, when one exists.
        var activeSheetMediaId: String = ""
    }

    struct Resolution {
        /// Prompt with each `@Name` replaced by the canonical roster name.
        var cleanedPrompt: String
        /// Mentioned entries, deduped, in order of first appearance.
        var mentions: [Entry]
    }

    /// An in-progress mention the user is still typing (drives autocomplete).
    struct ActivePartial: Equatable {
        /// Range of the partial INCLUDING its `@`, in the original text.
        var range: Range<String.Index>
        /// Text after the `@`, lowercased for matching (may be empty).
        var query: String
    }

    private static func isBoundary(_ character: Character?) -> Bool {
        guard let character else { return true }
        return !(character.isLetter || character.isNumber)
    }

    private struct MatchCandidate {
        var entry: Entry
        var matchedName: String
    }

    private struct Match {
        var entry: Entry
        var matchedName: String
    }

    private static func matchNames(for entry: Entry) -> [String] {
        var names: [String] = []
        var seen = Set<String>()
        for rawName in [entry.name] + entry.aliases {
            let name = rawName.trimmed
            let key = name.lowercased()
            guard !name.isEmpty, seen.insert(key).inserted else { continue }
            names.append(name)
        }
        return names
    }

    /// Canonical names and safe aliases sorted for greedy matching: longest first,
    /// then alphabetical for deterministic ties.
    private static func matchOrder(_ entries: [Entry]) -> [MatchCandidate] {
        entries.flatMap { entry in
            matchNames(for: entry).map { MatchCandidate(entry: entry, matchedName: $0) }
        }
            .sorted {
                if $0.matchedName.count != $1.matchedName.count {
                    return $0.matchedName.count > $1.matchedName.count
                }
                return $0.matchedName.lowercased() < $1.matchedName.lowercased()
            }
    }

    /// The entry mentioned at `index` (which must point at `@`), if any.
    private static func match(
        in text: String,
        at index: String.Index,
        candidates: [MatchCandidate]
    ) -> Match? {
        let nameStart = text.index(after: index)
        guard nameStart < text.endIndex else { return nil }
        for candidate in candidates {
            let name = candidate.matchedName
            guard let nameEnd = text.index(nameStart, offsetBy: name.count, limitedBy: text.endIndex) else { continue }
            let textSlice = text[nameStart..<nameEnd]
            guard textSlice.compare(name, options: [.caseInsensitive]) == .orderedSame else { continue }
            let after = nameEnd < text.endIndex ? text[nameEnd] : nil
            guard isBoundary(after) else { continue }
            return Match(entry: candidate.entry, matchedName: name)
        }
        return nil
    }

    static func resolve(prompt: String, entries: [Entry]) -> Resolution {
        let ordered = matchOrder(entries)
        var cleaned = ""
        var mentions: [Entry] = []
        var index = prompt.startIndex
        while index < prompt.endIndex {
            let character = prompt[index]
            if character == "@", let match = match(in: prompt, at: index, candidates: ordered) {
                cleaned.append(match.entry.name)
                if !mentions.contains(where: { $0.id == match.entry.id }) {
                    mentions.append(match.entry)
                }
                index = prompt.index(index, offsetBy: match.matchedName.count + 1)
            } else {
                cleaned.append(character)
                index = prompt.index(after: index)
            }
        }
        return Resolution(cleanedPrompt: cleaned, mentions: mentions)
    }

    /// The unfinished mention at the end of the text. Kept for non-editor callers and
    /// compatibility tests; interactive editors should pass their actual caret offset.
    static func activePartial(in text: String, entries: [Entry]) -> ActivePartial? {
        activePartial(in: text, caretUTF16Offset: text.utf16.count, entries: entries)
    }

    /// The unfinished mention immediately before the caret. Only text between the last
    /// boundary-safe `@` and the caret participates, so editing the middle of a prompt
    /// never activates a later mention elsewhere in the document.
    static func activePartial(
        in text: String,
        caretUTF16Offset: Int,
        entries: [Entry]
    ) -> ActivePartial? {
        let ordered = matchOrder(entries)
        guard !ordered.isEmpty else { return nil }
        let boundedOffset = min(max(caretUTF16Offset, 0), text.utf16.count)
        let caretIndex = String.Index(utf16Offset: boundedOffset, in: text)
        let prefix = text[..<caretIndex]
        let atIndex = prefix.lastIndex(of: "@")
        guard let atIndex else { return nil }
        let preceding = atIndex > text.startIndex ? text[text.index(before: atIndex)] : nil
        guard isBoundary(preceding) else { return nil }
        guard match(in: text, at: atIndex, candidates: ordered) == nil else { return nil }
        let queryStart = text.index(after: atIndex)
        guard queryStart <= caretIndex else { return nil }
        let rawQuery = text[queryStart..<caretIndex]
        guard rawQuery.count <= 40, !rawQuery.contains(where: \.isNewline) else { return nil }
        let query = String(rawQuery).lowercased()
        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
        let hasCandidate = ordered.contains { candidate in
            let name = candidate.matchedName.lowercased()
            return trimmedQuery.isEmpty || name.hasPrefix(trimmedQuery) || name.hasPrefix(query)
        }
        guard hasCandidate else { return nil }
        return ActivePartial(range: atIndex..<caretIndex, query: trimmedQuery)
    }

    /// Entries whose names complete the active partial's query, suggestion-ready.
    static func suggestions(for partial: ActivePartial, entries: [Entry], limit: Int = 5) -> [Entry] {
        let query = partial.query
        let candidates = entries.filter { entry in
            matchNames(for: entry).contains { name in
                query.isEmpty || name.lowercased().hasPrefix(query)
            }
        }
        return Array(candidates.prefix(limit))
    }

    /// Replaces the active partial with a completed `@Name ` mention.
    static func completing(text: String, partial: ActivePartial, with entry: Entry) -> String {
        text.replacingCharacters(in: partial.range, with: "@\(entry.name) ")
    }

    /// Drops the `@` of `@Name`-style mention tokens — an `@` at a word boundary
    /// followed by a letter or number — keeping the name text. Emails and mid-word
    /// `@` are untouched. Roster-free on purpose: render paths must never send a
    /// literal mention token to an image model, whether or not the name resolves.
    static func strippingMentionTokens(_ text: String) -> String {
        var cleaned = ""
        var previous: Character?
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            let nextIndex = text.index(after: index)
            if character == "@", isBoundary(previous), nextIndex < text.endIndex,
               text[nextIndex].isLetter || text[nextIndex].isNumber {
                previous = character
                index = nextIndex
                continue
            }
            cleaned.append(character)
            previous = character
            index = nextIndex
        }
        return cleaned
    }

    /// Manifest descriptor for a mentioned entry's attached reference image. Rides
    /// LensPromptImageAttachment.detail into the attachment manifest.
    static func attachmentDescriptor(for entry: Entry, label: String, isCompositeSheet: Bool, isCharacterSheet: Bool = false) -> String {
        let descriptor: String
        switch entry.kind {
        case .character:
            descriptor = "CHARACTER reference for \"\(entry.name)\": this exact figure appears in the scene; match their appearance, build, and distinguishing features from this image. It is subject matter, not a style reference — render \"\(entry.name)\" in this treatment's style."
        case .object:
            descriptor = "OBJECT reference for \"\(entry.name)\": this exact object appears in the scene; match its form, material, and condition from this image. It is subject matter, not a style reference — render \"\(entry.name)\" in this treatment's style."
        case .place:
            descriptor = "PLACE reference for \"\(entry.name)\": the scene is set in this exact location; match its layout, architecture, landmarks, and materials from this image. It is subject matter, not a style reference — render \"\(entry.name)\" in this treatment's style."
        }
        return descriptor + descriptorSuffix(name: entry.name, label: label, isCompositeSheet: isCompositeSheet, isCharacterSheet: isCharacterSheet)
    }

    /// Treatment-neutral descriptor for roster reference renders: there is no lens
    /// style in play, so the written prompt owns framing and treatment.
    static func characterStudyAttachmentDescriptor(name: String, label: String, isCompositeSheet: Bool, isCharacterSheet: Bool = false) -> String {
        let descriptor = "CHARACTER identity reference for \"\(name)\": render this exact person; match their appearance, build, and distinguishing features from this image. It is subject matter, not a style reference — follow the written prompt for framing and treatment."
        return descriptor + descriptorSuffix(name: name, label: label, isCompositeSheet: isCompositeSheet, isCharacterSheet: isCharacterSheet)
    }

    /// Sheet-lane descriptor for a source image: an INPUT the sheet is built from,
    /// not a scene subject and not a style reference. With a sheet attached alongside,
    /// the sheet sets continuity and the photo corrects the likeness.
    static func characterSheetSourceDescriptor(name: String, label: String, hasSheet: Bool) -> String {
        var descriptor = "SOURCE IMAGE for \"\(name)\": a photo or artwork of this character, an input the sheet is built from — take face, build, skin, hair, and distinguishing features from it. It is subject matter, not a style or layout reference."
        if hasSheet {
            descriptor += " Reconcile it with the attached reference sheet: the sheet sets continuity; this image corrects and completes the likeness."
        }
        return descriptor + descriptorSuffix(name: name, label: label, isCompositeSheet: false, isCharacterSheet: false)
    }

    private static func descriptorSuffix(name: String, label: String, isCompositeSheet: Bool, isCharacterSheet: Bool = false) -> String {
        if isCharacterSheet {
            return " This image is \"\(name)\"'s generated reference sheet — turnaround, face, expression, pose, costume, and palette panels of the same character; match identity from it."
        }
        if isCompositeSheet {
            return " This image is a labeled reference sheet — each panel shows \"\(name)\" from a different angle, age, or context; the panel captions name what each view shows."
        }
        let trimmedLabel = label.trimmed
        return trimmedLabel.isEmpty ? "" : " This particular reference shows: \(trimmedLabel)."
    }
}
