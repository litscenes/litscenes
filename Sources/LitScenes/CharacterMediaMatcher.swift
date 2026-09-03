import Foundation

/// An analyzed Story Input as the matcher sees it: who is visible and what the
/// observation says, never the image itself.
struct CharacterMediaCandidate: Hashable, Sendable {
    var mediaId: String
    var peopleVisible: Bool
    var caption: String = ""
    var literalDescription: String = ""
    var roles: [String] = []
}

/// Cheap first-pass association of Story Inputs with a character: a person must be
/// visible, name tokens count for a lot, distinctive description words for a little.
/// Deterministic, offline, and honest about being a suggestion — the user confirms
/// with one click; nothing attaches on its own.
func characterSourceImageSuggestions(
    name: String,
    description: String,
    candidates: [CharacterMediaCandidate],
    excluding: Set<String>,
    limit: Int = 6
) -> [String] {
    let nameTokens = matcherTokens(name, minimumLength: 3)
    let descriptionTokens = matcherTokens(description, minimumLength: 5).subtracting(nameTokens)
    guard !nameTokens.isEmpty || !descriptionTokens.isEmpty else { return [] }
    var scored: [(mediaId: String, score: Int)] = []
    for candidate in candidates where candidate.peopleVisible && !excluding.contains(candidate.mediaId) {
        let haystack = matcherTokens(
            [candidate.caption, candidate.literalDescription, candidate.roles.joined(separator: " ")].joined(separator: " "),
            minimumLength: 3
        )
        var score = 0
        for token in nameTokens where haystack.contains(token) { score += 3 }
        for token in descriptionTokens where haystack.contains(token) { score += 1 }
        if score >= 1 {
            scored.append((candidate.mediaId, score))
        }
    }
    return scored
        .sorted { lhs, rhs in
            if lhs.score == rhs.score { return lhs.mediaId < rhs.mediaId }
            return lhs.score > rhs.score
        }
        .prefix(max(0, limit))
        .map(\.mediaId)
}

private let matcherStopwords: Set<String> = [
    "about", "above", "after", "again", "against", "along", "among", "around", "because", "before",
    "behind", "below", "beneath", "beside", "between", "beyond", "character", "clothing", "color",
    "colored", "dark", "figure", "front", "green", "large", "light", "little", "looking", "medium",
    "other", "person", "small", "standing", "their", "there", "these", "those", "through", "under",
    "wearing", "where", "which", "while", "white", "woman", "young", "black", "brown", "human",
]

private func matcherTokens(_ text: String, minimumLength: Int) -> Set<String> {
    let lowered = text.lowercased()
    let parts = lowered.split { !($0.isLetter || $0.isNumber) }
    return Set(parts.map(String.init).filter { $0.count >= minimumLength && !matcherStopwords.contains($0) })
}
