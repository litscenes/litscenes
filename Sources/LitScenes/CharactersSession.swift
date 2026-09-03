import SwiftUI

/// Which editable field of the selected character has the keyboard.
enum CharacterEditField: Hashable {
    case name
    case appearance
    case prompt
    case newProp
    case studioPrompt
    case studioRefine
}

/// The STUDIO's working state for one character: what to render from, how, and the
/// editable prompt. Kept while the tab is open; never persisted.
struct CharacterStudioDraft: Equatable {
    var isOpen = false
    var shot: RosterCharacterRenderPrompt.Shot = .portrait
    var look: CharacterStudyLook = .asDescribed
    /// Chosen references: source media ids and/or the active sheet's id.
    var referenceIds: [String] = []
    var prompt = ""
    var seededPrompt = ""
    var refineInput = ""
    var hasSeeded = false

    /// The operator changed the seeded text; chips then steer only the canvas and
    /// the attachments until RESET re-seeds.
    var isEdited: Bool { hasSeeded && prompt.trimmed != seededPrompt.trimmed }
}

/// CHARACTERS tab state that must survive the tab-content teardown —
/// `.id(displayedWorkspaceTab)` destroys the tab body's @State on every switch,
/// so the selection, the unsent drafts, and the studio live here, owned by
/// LibraryRootView. The selection also mirrors to the preferences suite per
/// project, so it survives relaunch.
@MainActor
final class CharactersSession: ObservableObject {
    @Published private(set) var selectedCharacterId = ""
    /// Unsent conversation drafts and pending attachments, per character, so
    /// switching characters or tabs never loses a half-written message.
    @Published private var composerDrafts: [String: String] = [:]
    @Published private var pendingAttachments: [String: [String]] = [:]
    /// The SHEET PROMPT disclosure shows every line instead of the first eight.
    @Published var isPromptExpanded = false
    @Published private var studios: [String: CharacterStudioDraft] = [:]

    private var projectId = ""

    private static func selectionKey(_ projectId: String) -> String {
        "LITSCENES_CHARACTERS_SELECTED_\(projectId)"
    }

    /// Point the session at the loaded project, restoring its persisted selection.
    /// A same-project call is a no-op.
    func adoptProject(_ projectId: String) {
        guard !projectId.isEmpty, projectId != self.projectId else { return }
        self.projectId = projectId
        composerDrafts = [:]
        pendingAttachments = [:]
        studios = [:]
        isPromptExpanded = false
        selectedCharacterId = LitScenesPreferences.store.string(forKey: Self.selectionKey(projectId)) ?? ""
    }

    func select(_ characterId: String) {
        guard characterId != selectedCharacterId else { return }
        selectedCharacterId = characterId
        isPromptExpanded = false
        persistSelection()
    }

    /// Keeps the selection honest against the roster: a deleted or never-set
    /// selection falls back to the first character.
    func reconcile(characterIds: [String]) {
        if !selectedCharacterId.isEmpty, characterIds.contains(selectedCharacterId) { return }
        let fallback = characterIds.first ?? ""
        guard fallback != selectedCharacterId else { return }
        selectedCharacterId = fallback
        persistSelection()
    }

    func draft(for characterId: String) -> String {
        composerDrafts[characterId] ?? ""
    }

    func setDraft(_ text: String, for characterId: String) {
        if text.isEmpty {
            composerDrafts.removeValue(forKey: characterId)
        } else {
            composerDrafts[characterId] = text
        }
    }

    func attachments(for characterId: String) -> [String] {
        pendingAttachments[characterId] ?? []
    }

    func setAttachments(_ mediaIds: [String], for characterId: String) {
        if mediaIds.isEmpty {
            pendingAttachments.removeValue(forKey: characterId)
        } else {
            pendingAttachments[characterId] = mediaIds
        }
    }

    func studio(for characterId: String) -> CharacterStudioDraft {
        studios[characterId] ?? CharacterStudioDraft()
    }

    func setStudio(_ draft: CharacterStudioDraft, for characterId: String) {
        studios[characterId] = draft
    }

    private func persistSelection() {
        guard !projectId.isEmpty else { return }
        LitScenesPreferences.store.set(selectedCharacterId, forKey: Self.selectionKey(projectId))
    }
}
