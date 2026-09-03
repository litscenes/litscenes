import Foundation
import Testing
@testable import LitScenes

@Test func sheetDefaultPrefersNanoBananaWhileFALIsConfigured() throws {
    let stacks = RenderStackRegistry.shared.stacks()
    let nano = try #require(stacks.first { $0.id == characterSheetPreferredStackId })
    let openAI = try #require(stacks.first { $0.isOpenAI })

    // FAL and OpenAI both configured: the sheet takes Nano Banana 2.
    #expect(characterSheetDefaultStack(stacks: stacks) { $0.id == nano.id || $0.isOpenAI }?.id == nano.id)
    // Only OpenAI configured: the old order stands.
    #expect(characterSheetDefaultStack(stacks: stacks) { $0.isOpenAI }?.id == openAI.id)
    // Nothing configured: the first stack, whose blocker explains the refusal.
    #expect(characterSheetDefaultStack(stacks: stacks) { _ in false }?.id == stacks.first?.id)
}

@Test func frameDefaultKeepsOpenAIFirst() throws {
    let stacks = RenderStackRegistry.shared.stacks()
    let nano = try #require(stacks.first { $0.id == characterSheetPreferredStackId })
    let openAI = try #require(stacks.first { $0.isOpenAI })
    #expect(frameDefaultStack(stacks: stacks) { $0.id == nano.id || $0.isOpenAI }?.id == openAI.id)
    #expect(frameDefaultStack(stacks: stacks) { $0.id == nano.id }?.id == nano.id)
    #expect(frameDefaultStack(stacks: stacks) { _ in false }?.id == stacks.first?.id)
}
