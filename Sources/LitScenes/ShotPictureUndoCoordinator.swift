import AppKit
import SwiftUI

/// Picture-state undo on the reel idiom: snapshot-based, symmetric — each
/// handler re-registers its inverse, so ⌘Z/⇧⌘Z round-trip without a second
/// path. One committed picture gesture = one persisted Shot transaction =
/// one registered action (THE PICTURE SNAPSHOT LAW).
///
/// `shotId` rides each registration rather than the coordinator because two
/// of the three owning surfaces (the workbench's stage rail, the Clip
/// Inspector) serve whichever shot the gesture touched — and sheet windows
/// own their own UndoManagers, which is why each surface owns its own
/// instance instead of sharing one.
@MainActor
final class ShotPictureUndoCoordinator: ObservableObject {
    var applyState: ((String, ShotPictureStateSnapshot) -> Void)?

    func registerEdit(
        shotId: String,
        old: ShotPictureStateSnapshot,
        new: ShotPictureStateSnapshot,
        actionName: String,
        undoManager: UndoManager?
    ) {
        guard let undoManager, old != new else { return }
        undoManager.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                target.applyState?(shotId, old)
                target.registerEdit(
                    shotId: shotId,
                    old: new,
                    new: old,
                    actionName: actionName,
                    undoManager: undoManager
                )
            }
        }
        undoManager.setActionName(actionName)
    }
}
