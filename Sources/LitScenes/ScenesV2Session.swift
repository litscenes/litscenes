import SwiftUI

/// SCENES v2 session state that must survive the tab-content teardown —
/// `.id(displayedWorkspaceTab)` destroys the tab body's @State on every tab
/// switch, so the working set lives here, owned by LibraryRootView (whose
/// identity is stable). The selection also mirrors to the preferences suite
/// per project, so it survives relaunch.
@MainActor
final class ScenesV2Session: ObservableObject {
    /// THE STAGE SELECTION LAW's one datum: the scene on the hero stage.
    /// "" = empty stage (honest exhaustion plate).
    @Published private(set) var selectedSceneId = ""
    /// True when the (possibly empty) selection is a DELIBERATE state — a
    /// click, the conveyor's exhaustion, or a restored preference. An empty
    /// selection with this set survives reconcile (THE DURABLE EMPTY STAGE);
    /// without it (a never-visited project), reconcile seeds.
    private(set) var selectionIsDeliberate = false
    /// Previously staged scenes, most recent first (current excluded), capped.
    /// Reconcile's fallback when the staged scene is deleted: the operator
    /// returns to the last scene they had staged, never to the top of the
    /// rail. Persisted with the selection so the memory survives relaunch.
    private(set) var recentSceneIds: [String] = []
    @Published var poolFilter: ScenesV2PoolFilter = .all
    /// Pool search text lives here for the same reason as `poolFilter`: the
    /// tab teardown would silently clear a typed query mid-hunt. Not
    /// persisted — a fresh launch starts unfiltered, like the chips.
    @Published var poolSearchQuery = ""
    /// Sheet-driven suggestion ids the operator has already seen on this
    /// project (the NEW ribbon's memory). Persisted per project; pruned to
    /// live suggestions on every tab appearance.
    @Published private(set) var seenSuggestionIds: Set<String> = []
    /// The engine's last refusal per suggestion card (imageId → words). Lives
    /// here so a refusal survives a tab switch instead of dying with a card's
    /// @State. Cleared when the project changes.
    @Published var suggestionRefusals: [String: String] = [:]
    /// The global status/error the engine showed when SCENES appeared: the
    /// status line prints only what changed after that (THE SCOPED STATUS).
    var statusBaseline = ""
    var errorBaseline = ""

    private var projectId = ""

    private static let historyLimit = 8

    private static func stageKey(_ projectId: String) -> String {
        "LITSCENES_V2_STAGE_\(projectId)"
    }

    private static func historyKey(_ projectId: String) -> String {
        "LITSCENES_V2_STAGE_HISTORY_\(projectId)"
    }

    private static func seenSuggestionsKey(_ projectId: String) -> String {
        "LITSCENES_V2_SEEN_SUGGESTIONS_\(projectId)"
    }

    /// The two-box era's persistence blob, decoded only to migrate its MRU
    /// scene into the single selection. Never written.
    private struct LegacyBoxSlots: Decodable {
        var sceneIds: [String] = []
        var mruIndex: Int = 0
    }

    private static func legacySlotsKey(_ projectId: String) -> String {
        "LITSCENES_V2_BOXES_\(projectId)"
    }

    /// Point the session at the loaded project, restoring its persisted
    /// selection (falling back to the retired box blob's MRU scene once).
    /// Called whenever the current project changes (including first
    /// appearance); a same-project call is a no-op.
    func adoptProject(_ projectId: String) {
        guard !projectId.isEmpty, projectId != self.projectId else { return }
        self.projectId = projectId
        recentSceneIds = LitScenesPreferences.store.stringArray(forKey: Self.historyKey(projectId)) ?? []
        seenSuggestionIds = Set(LitScenesPreferences.store.stringArray(forKey: Self.seenSuggestionsKey(projectId)) ?? [])
        suggestionRefusals = [:]
        if let stored = LitScenesPreferences.store.string(forKey: Self.stageKey(projectId)) {
            selectedSceneId = stored
            selectionIsDeliberate = true
            return
        }
        if let data = LitScenesPreferences.store.data(forKey: Self.legacySlotsKey(projectId)),
           let legacy = try? JSONDecoder().decode(LegacyBoxSlots.self, from: data) {
            let migrated = scenesV2MigratedLegacySelection(
                sceneIds: legacy.sceneIds,
                mruIndex: legacy.mruIndex
            )
            selectedSceneId = migrated
            // An empty blob migrates as never-visited, so the seed still
            // runs; a named scene is a real preference and persists.
            selectionIsDeliberate = !migrated.isEmpty
            if selectionIsDeliberate {
                persistSelection()
            }
            return
        }
        selectedSceneId = ""
        selectionIsDeliberate = false
    }

    /// Select a scene onto the stage ("" empties it — deliberately, so the
    /// empty stage survives reconcile). The departing scene joins the front
    /// of the history. Persists per project.
    func select(_ shotId: String) {
        guard shotId != selectedSceneId || !selectionIsDeliberate else { return }
        let departing = selectedSceneId
        selectedSceneId = shotId
        selectionIsDeliberate = true
        if !departing.isEmpty, departing != shotId {
            recentSceneIds = ([departing] + recentSceneIds.filter { $0 != departing })
            recentSceneIds = Array(recentSceneIds.prefix(Self.historyLimit))
        }
        persistSelection()
    }

    private func persistSelection() {
        guard !projectId.isEmpty else { return }
        LitScenesPreferences.store.set(selectedSceneId, forKey: Self.stageKey(projectId))
        LitScenesPreferences.store.set(recentSceneIds, forKey: Self.historyKey(projectId))
    }

    /// Mark suggestion ids seen (the NEW ribbon retires). Persists per project.
    func markSuggestionsSeen(_ ids: Set<String>) {
        let union = seenSuggestionIds.union(ids)
        guard union != seenSuggestionIds else { return }
        seenSuggestionIds = union
        persistSeenSuggestions()
    }

    /// Forget ids that are no longer suggestions (rendered, replaced, or gone).
    func pruneSeenSuggestions(live: Set<String>) {
        let pruned = scenesV2PrunedSeenSuggestionIds(seen: seenSuggestionIds, live: live)
        guard pruned != seenSuggestionIds else { return }
        seenSuggestionIds = pruned
        persistSeenSuggestions()
    }

    private func persistSeenSuggestions() {
        guard !projectId.isEmpty else { return }
        LitScenesPreferences.store.set(Array(seenSuggestionIds).sorted(), forKey: Self.seenSuggestionsKey(projectId))
    }
}
