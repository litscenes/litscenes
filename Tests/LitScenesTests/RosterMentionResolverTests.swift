import Foundation
import Testing
@testable import LitScenes

private func entry(_ id: String, _ name: String, kind: RosterMentionResolver.EntryKind = .character) -> RosterMentionResolver.Entry {
    RosterMentionResolver.Entry(id: id, name: name, kind: kind)
}

@Test
func mentionResolveMatchesCaseInsensitivelyAndCleansPrompt() {
    let entries = [entry("c1", "Bethany"), entry("o1", "Lantern", kind: .object)]
    let resolution = RosterMentionResolver.resolve(
        prompt: "@bethany lifts the @LANTERN toward the door.",
        entries: entries
    )
    #expect(resolution.cleanedPrompt == "Bethany lifts the Lantern toward the door.")
    #expect(resolution.mentions.map(\.id) == ["c1", "o1"])
}

@Test
func mentionResolvePrefersLongestNameAndRequiresBoundary() {
    let entries = [entry("c1", "Kai"), entry("c2", "Kai Aloha")]
    let resolution = RosterMentionResolver.resolve(
        prompt: "@Kai Aloha waves while @Kai watches; @Kaiser is nobody.",
        entries: entries
    )
    #expect(resolution.mentions.map(\.id) == ["c2", "c1"])
    #expect(resolution.cleanedPrompt == "Kai Aloha waves while Kai watches; @Kaiser is nobody.")
}

@Test
func mentionResolveDedupesRepeatMentions() {
    let entries = [entry("c1", "Ava")]
    let resolution = RosterMentionResolver.resolve(prompt: "@Ava meets @Ava at dusk", entries: entries)
    #expect(resolution.mentions.count == 1)
    #expect(resolution.cleanedPrompt == "Ava meets Ava at dusk")
}

@Test
func historicalCharacterAliasResolvesToCurrentRosterIdentityAndReferences() {
    let current = RosterMentionResolver.Entry(
        id: "character_river",
        name: "Mara Chen",
        kind: .character,
        aliases: ["Mara Vale"],
        referenceMediaIds: ["reference_front", "reference_profile"]
    )
    let resolution = RosterMentionResolver.resolve(
        prompt: "@Mara Vale waits beneath the station clock.",
        entries: [current]
    )

    #expect(resolution.cleanedPrompt == "Mara Chen waits beneath the station clock.")
    #expect(resolution.mentions.map(\.id) == ["character_river"])
    #expect(resolution.mentions.first?.referenceMediaIds == ["reference_front", "reference_profile"])
    let partial = RosterMentionResolver.activePartial(in: "find @Mara V", entries: [current])
    #expect(partial?.query == "mara v")
    #expect(RosterMentionResolver.suggestions(for: partial!, entries: [current]).map(\.name) == ["Mara Chen"])
}

@Test
func activePartialDetectsUnfinishedMentionAndCompletionReplacesIt() {
    let entries = [entry("c1", "Bethany"), entry("c2", "Beau")]
    let text = "close on @be"
    let partial = RosterMentionResolver.activePartial(in: text, entries: entries)
    #expect(partial?.query == "be")
    let suggestions = RosterMentionResolver.suggestions(for: partial!, entries: entries)
    #expect(suggestions.map(\.id) == ["c1", "c2"])
    let completed = RosterMentionResolver.completing(text: text, partial: partial!, with: suggestions[0])
    #expect(completed == "close on @Bethany ")
    // Once complete, no partial remains.
    #expect(RosterMentionResolver.activePartial(in: completed, entries: entries) == nil)
}

@Test
func activePartialIgnoresCompleteMentionsAndUnmatchableText() {
    let entries = [entry("c1", "Bethany")]
    #expect(RosterMentionResolver.activePartial(in: "hello @Bethany", entries: entries) == nil)
    #expect(RosterMentionResolver.activePartial(in: "email me @ zed", entries: entries) == nil)
    #expect(RosterMentionResolver.activePartial(in: "@zzz nothing", entries: entries) == nil)
    // A bare trailing @ suggests everyone.
    #expect(RosterMentionResolver.activePartial(in: "pan to @", entries: entries)?.query == "")
}

@Test
func attachmentDescriptorSpeaksCharacterObjectAndSheetLanguage() {
    let character = entry("c1", "Bethany")
    let object = entry("o1", "Lantern", kind: .object)
    let plain = RosterMentionResolver.attachmentDescriptor(for: character, label: "young Bethany", isCompositeSheet: false)
    #expect(plain.contains("CHARACTER reference for \"Bethany\""))
    #expect(plain.hasSuffix("This particular reference shows: young Bethany."))
    let sheet = RosterMentionResolver.attachmentDescriptor(for: character, label: "", isCompositeSheet: true)
    #expect(sheet.contains("labeled reference sheet"))
    let objectDescriptor = RosterMentionResolver.attachmentDescriptor(for: object, label: "", isCompositeSheet: false)
    #expect(objectDescriptor.contains("OBJECT reference for \"Lantern\""))
    #expect(!objectDescriptor.contains("This particular reference shows"))
}

@Test
func strippingMentionTokensDropsTokensAndKeepsEmailsAndMidWordAt() {
    let stripped = RosterMentionResolver.strippingMentionTokens(
        "@Elise works. Email pat@example.com. (@Kai) and @Marley wait."
    )
    #expect(stripped == "Elise works. Email pat@example.com. (Kai) and Marley wait.")
    let placeDescriptor = RosterMentionResolver.attachmentDescriptor(
        for: RosterMentionResolver.Entry(id: "p1", name: "The Batching Kitchen", kind: .place),
        label: "porch side",
        isCompositeSheet: false
    )
    #expect(placeDescriptor.contains("PLACE reference for \"The Batching Kitchen\""))
    #expect(placeDescriptor.hasSuffix("This particular reference shows: porch side."))
}

@Test
func strippingMentionTokensHandlesEdges() {
    #expect(RosterMentionResolver.strippingMentionTokens("@Start of line") == "Start of line")
    #expect(RosterMentionResolver.strippingMentionTokens("trailing @") == "trailing @")
    #expect(RosterMentionResolver.strippingMentionTokens("") == "")
    #expect(RosterMentionResolver.strippingMentionTokens("@@Elise") == "@Elise")
    #expect(RosterMentionResolver.strippingMentionTokens("no tokens at all") == "no tokens at all")
}
