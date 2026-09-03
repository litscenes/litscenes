import Foundation

/// The CHARACTERS tab's casting state and every line of copy it produces, pure so the
/// masthead, the casting card, and the action bar agree and the laws are testable.
enum CharacterCastingTone: Equatable, Sendable {
    case muted
    case brass
    case softGold
    case rust
}

/// Why a render cannot start right now.
enum CharacterRenderBlocker: Equatable, Sendable {
    case noStack
    case credential(String)
    case paused
    /// Another character's render holds the lane.
    case busy
    /// This character's own source image is generating.
    case studyRunning
}

enum CharacterCastingStage: Equatable, Sendable {
    case uncast(sourceCount: Int, hasAppearance: Bool)
    /// The identity is being drafted from the story before the render.
    case drafting(sourceCount: Int)
    case rendering(stackLabel: String)
    case cast(ordinal: Int, promptIsCurrent: Bool)
    case failed(reason: String, ordinal: Int?)
}

struct CharacterCastingInputs: Equatable, Sendable {
    var name: String
    var sourceCount: Int = 0
    var hasAppearance: Bool = false
    var hasStoryIdentity: Bool = false
    /// 1-based, oldest sheet = 1; nil without a sheet.
    var activeOrdinal: Int? = nil
    var promptIsCurrent: Bool = true
    var isRenderingSheet: Bool = false
    var isDrafting: Bool = false
    /// The next render drafts the identity first.
    var draftsFirst: Bool = false
    var lastFailure: String = ""
    /// The failure came from the identity draft, not the render.
    var lastFailureIsDraft: Bool = false
    var stackLabel: String = ""
    var priceNote: String = ""
    var stackIsTextOnly: Bool = false
    var attachesSheet: Bool = false
    var attachedSourceCount: Int = 0
    var blocker: CharacterRenderBlocker? = nil
    var promptIsHandEdited: Bool = false
}

struct CharacterCastingCopy: Equatable, Sendable {
    var mastheadStatus: String
    var mastheadTone: CharacterCastingTone
    var cardHeadline: String
    var cardSentence: String
    var cardFailure: String
    var barTitle: String
    var barIsGhost: Bool
    var consequence: String
    var note: String
    var noteTone: CharacterCastingTone
    var disabledReason: String
}

enum CharacterNextStep: Equatable, Sendable {
    case nextUncast(characterId: String, name: String)
    case continueToScenes
}

func characterCastingStage(_ inputs: CharacterCastingInputs) -> CharacterCastingStage {
    if inputs.isDrafting { return .drafting(sourceCount: inputs.sourceCount) }
    if inputs.isRenderingSheet { return .rendering(stackLabel: inputs.stackLabel.trimmed) }
    let failure = inputs.lastFailure.trimmed
    if !failure.isEmpty { return .failed(reason: failure, ordinal: inputs.activeOrdinal) }
    if let ordinal = inputs.activeOrdinal { return .cast(ordinal: ordinal, promptIsCurrent: inputs.promptIsCurrent) }
    return .uncast(sourceCount: inputs.sourceCount, hasAppearance: inputs.hasAppearance)
}

func characterCastingCopy(_ inputs: CharacterCastingInputs) -> CharacterCastingCopy {
    let stage = characterCastingStage(inputs)
    let name = inputs.name.trimmed.isEmpty ? "the character" : inputs.name.trimmed
    let stackLabel = inputs.stackLabel.trimmed
    let stackPart = stackLabel.isEmpty ? "No render stack" : stackLabel
    let price = inputs.priceNote.trimmed.isEmpty ? "unpriced" : inputs.priceNote.trimmed
    let sheetWord: (Int) -> String = { "sheet \(characterSheetOrdinalLabel($0))" }

    let masthead: (status: String, tone: CharacterCastingTone)
    switch stage {
    case .drafting:
        masthead = ("CASTING…", .softGold)
    case .rendering:
        masthead = ("RENDERING", .softGold)
    case .cast(let ordinal, _):
        masthead = ("CAST · SHEET \(characterSheetOrdinalLabel(ordinal))", .brass)
    case .failed(_, let ordinal?):
        masthead = ("CAST · SHEET \(characterSheetOrdinalLabel(ordinal))", .brass)
    case .uncast, .failed:
        masthead = ("NOT YET CAST", .muted)
    }

    let from: String
    if inputs.attachesSheet || inputs.attachedSourceCount > 0 {
        var parts: [String] = []
        if inputs.attachesSheet, let ordinal = inputs.activeOrdinal { parts.append(sheetWord(ordinal)) }
        else if inputs.attachesSheet { parts.append("the sheet") }
        if inputs.attachedSourceCount > 0 { parts.append(characterSourceImagesPhrase(inputs.attachedSourceCount)) }
        from = "From " + parts.joined(separator: " and ")
    } else {
        from = inputs.hasAppearance ? "From the description" : "From text alone"
    }
    var consequence = [from, stackPart, price].joined(separator: " · ")
    if inputs.promptIsHandEdited { consequence += " · edited prompt" }
    if inputs.draftsFirst, inputs.activeOrdinal == nil { consequence += " · drafts the identity first" }

    var headline = "Render \(name)'s reference sheet"
    var sentence: String
    var failure = ""
    switch stage {
    case .drafting(let sourceCount):
        headline = "Casting \(name) from the story…"
        sentence = sourceCount > 0
            ? "From the Goal, the other characters, and \(characterSourceImagesPhrase(sourceCount))."
            : "From the Goal, the other characters, and the name alone."
    case .rendering:
        headline = "Rendering \(name)'s sheet…"
        sentence = stackLabel.isEmpty
            ? "The sheet lands here when it is done."
            : "On \(stackLabel). The sheet lands here when it is done."
    default:
        if inputs.stackIsTextOnly, inputs.sourceCount > 0 {
            sentence = "Renders from the description below. \(stackPart) uses text only, not your source images."
        } else if inputs.sourceCount == 0 {
            sentence = "Renders from the description below, then anchors \(name) in every scene."
        } else {
            sentence = "Renders from your \(characterSourceImagesPhrase(inputs.sourceCount)) and the description below, then anchors \(name) in every scene."
        }
        if case .failed(let reason, _) = stage {
            failure = inputs.lastFailureIsDraft ? reasonSentence(reason) : "The last render failed: \(reasonSentence(reason))"
        }
    }

    var barTitle = "RENDER SHEET"
    var barIsGhost = false
    switch stage {
    case .cast(_, let promptIsCurrent):
        barTitle = promptIsCurrent ? "NEW VERSION" : "RENDER AGAIN"
        barIsGhost = promptIsCurrent
    case .failed(_, let ordinal):
        barTitle = ordinal == nil ? "RENDER SHEET" : "RENDER AGAIN"
    case .uncast, .rendering, .drafting:
        break
    }

    var note = ""
    var tone: CharacterCastingTone = .muted
    var disabledReason = ""
    if let blocker = inputs.blocker {
        switch blocker {
        case .noStack:
            note = "Add an API key in App Settings to render."
            tone = .rust
        case .credential(let text):
            note = text.trimmed.isEmpty ? "Add an API key in App Settings to render." : text.trimmed
            tone = .rust
        case .paused:
            note = "Generation is paused. Resume it from Activity to continue."
            tone = .softGold
        case .busy:
            note = "Another character's render is running."
            tone = .muted
        case .studyRunning:
            note = "A source image is generating. Render the sheet when it lands."
            tone = .muted
        }
        disabledReason = note
    } else {
        switch stage {
        case .drafting:
            note = "Drafting an identity from the story…"
            tone = .muted
            disabledReason = "Drafting now."
        case .rendering:
            note = stackLabel.isEmpty ? "Rendering…" : "Rendering on \(stackLabel)…"
            tone = .muted
            disabledReason = "Rendering now."
        case .failed(let reason, let ordinal):
            if inputs.lastFailureIsDraft {
                note = "\(reasonSentence(reason)) RENDER SHEET renders from what is written."
            } else {
                note = "Last render failed: \(reasonSentence(reason))"
                if let ordinal { note += " \(sheetWord(ordinal).capitalizedFirst) still anchors \(name)." }
            }
            tone = .rust
        case .uncast(let sourceCount, let hasAppearance):
            if inputs.stackIsTextOnly, sourceCount > 0 {
                note = "\(stackPart) renders from text only. Your \(characterSourceImagesPhrase(sourceCount)) will not be used."
                tone = .rust
            } else if sourceCount == 0, !hasAppearance {
                note = "No appearance yet. The sheet will invent \(name) from the name and story alone."
                tone = .softGold
            }
        case .cast(let ordinal, let promptIsCurrent):
            if inputs.stackIsTextOnly, inputs.sourceCount > 0 {
                note = "\(stackPart) renders from text only. Your \(characterSourceImagesPhrase(inputs.sourceCount)) will not be used."
                tone = .rust
            } else if promptIsCurrent {
                note = "\(sheetWord(ordinal).capitalizedFirst) is current."
                tone = .muted
            } else {
                note = "Prompt changed since \(sheetWord(ordinal))."
                tone = .softGold
            }
        }
    }

    return CharacterCastingCopy(
        mastheadStatus: masthead.status,
        mastheadTone: masthead.tone,
        cardHeadline: headline,
        cardSentence: sentence,
        cardFailure: failure,
        barTitle: barTitle,
        barIsGhost: barIsGhost,
        consequence: consequence,
        note: note,
        noteTone: tone,
        disabledReason: disabledReason
    )
}

/// Where the bar points after this character is cast: the next uncast character in
/// rail order (wrapping), or SCENES when every character is cast; nil while the
/// selected character is still uncast.
func characterNextStep(
    characters: [(id: String, name: String, isCast: Bool)],
    selectedId: String
) -> CharacterNextStep? {
    guard let index = characters.firstIndex(where: { $0.id == selectedId }), characters[index].isCast else { return nil }
    let count = characters.count
    if count > 1 {
        for offset in 1..<count {
            let candidate = characters[(index + offset) % count]
            if !candidate.isCast { return .nextUncast(characterId: candidate.id, name: candidate.name) }
        }
    }
    return .continueToScenes
}

/// The sheet plate's height follows the workspace so the sheet earns its space
/// without pushing the sources below the fold on a short window.
func sheetPlateHeight(workspaceHeight: CGFloat) -> CGFloat {
    min(680, max(360, workspaceHeight - 420))
}

func characterSheetOrdinalLabel(_ ordinal: Int) -> String {
    FrameCreatorModal.romanNumeral(ordinal).uppercased()
}

func characterSourceImagesPhrase(_ count: Int) -> String {
    count == 1 ? "1 source image" : "\(count) source images"
}

/// Rail status fragment: "NO SOURCES" / "1 SOURCE" / "N SOURCES".
func characterSourcesLabel(_ count: Int) -> String {
    switch count {
    case ..<1: return "NO SOURCES"
    case 1: return "1 SOURCE"
    default: return "\(count) SOURCES"
    }
}

/// "2,140 CHARACTERS" for the prompt disclosure.
func characterCountLabel(_ count: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.locale = Locale(identifier: "en_US")
    let number = formatter.string(from: NSNumber(value: max(count, 0))) ?? "\(max(count, 0))"
    return count == 1 ? "1 CHARACTER" : "\(number) CHARACTERS"
}

func characterPromptDriftNote(hasDrift: Bool) -> String? {
    hasDrift ? "Identity changed after your edit. The edited prompt still renders." : nil
}

/// Menu row text for a render stack: AppKit menu items take no glyphs, so the
/// state rides as a suffix.
func characterStackMenuLabel(label: String, isTextOnly: Bool, blocked: Bool) -> String {
    var text = label.trimmed.isEmpty ? "Stack" : label.trimmed
    if isTextOnly { text += " · text only" }
    if blocked { text += " · needs key" }
    return text
}

private func reasonSentence(_ reason: String) -> String {
    var trimmed = reason.trimmed
    while trimmed.hasSuffix(".") { trimmed.removeLast() }
    return trimmed.isEmpty ? "unknown error." : trimmed + "."
}

private extension String {
    var capitalizedFirst: String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}

/// The last thing a character's render lane had to say, in words, beside the action.
struct CharacterRenderNote: Equatable, Sendable {
    enum Lane: Equatable, Sendable {
        case sheet
        case study
        case draft
        /// The sheet→SCENES suggestion lane: "2 Frames suggested in SCENES" or
        /// its failure, in words beside the action.
        case suggestions
    }

    var lane: Lane
    var message: String
    /// `.suggestions` only: how many Frames the note points at (0 = a failure).
    var suggestedFrameCount: Int = 0
}

// MARK: - Default render stacks

/// The stack a character sheet prefers when the operator picked none: FAL Nano
/// Banana 2 — fast and multi-reference — whenever FAL is configured.
let characterSheetPreferredStackId = "fal_nano_banana_2"

/// THE SHEET DEFAULT LAW: the preferred stack while credentialed, then the Frame
/// default order (OpenAI, any credentialed stack, else the first stack — its
/// blocker explains the refusal).
func characterSheetDefaultStack(
    stacks: [RenderStack],
    isCredentialed: (RenderStack) -> Bool
) -> RenderStack? {
    stacks.first { $0.id == characterSheetPreferredStackId && isCredentialed($0) }
        ?? frameDefaultStack(stacks: stacks, isCredentialed: isCredentialed)
}

/// THE FRAME DEFAULT LAW (one-click Frame renders): OpenAI first, then any
/// credentialed stack, else the first stack.
func frameDefaultStack(
    stacks: [RenderStack],
    isCredentialed: (RenderStack) -> Bool
) -> RenderStack? {
    stacks.first { $0.isOpenAI && isCredentialed($0) }
        ?? stacks.first { isCredentialed($0) }
        ?? stacks.first
}
