import AppKit
import SwiftUI

/// THE TYPING GUARD: true while any text input owns the keyboard — the key
/// window's first responder is an `NSText` (which covers `TextEditor`'s
/// `NSTextView` AND `TextField`, whose editing routes through the window's
/// field editor, itself an `NSTextView`). Popovers are their own key
/// windows, so their fields are caught too.
///
/// This exists because the modifier's old law — "a focused text field
/// consumes typing keys at the AppKit layer before these handlers see
/// them" — was falsified in the field: typing "e" in a Segment Prompt
/// opened the sound editor, and every bare-letter handler shared the
/// exposure (typing "bio" could arm a blade and write IN/OUT silently).
/// Every transport handler now asks AppKit directly instead of trusting
/// the bubbling story.
@MainActor
func shotTextInputOwnsKeyboard() -> Bool {
    guard let responder = NSApp.keyWindow?.firstResponder else { return false }
    return responder is NSText
}

/// The shot player modal's transport key surface, packaged as a modifier so
/// the modal body stays off the type-checker cliff.
///
/// Focus law (the Clip Inspector precedent, ShotClipInspectorView): the modal
/// body claims first responder with `.focusable()` + `@FocusState`; key
/// presses BUBBLE from the focused view up the hierarchy, and a focused audio
/// lane returns `.ignored` for keys it doesn't own (its handlers guard on
/// selection), so transport keys land here.
///
/// Every handler is gated on `isEnabled` (false while the microphone owns
/// the player) AND on THE TYPING GUARD (`shotTextInputOwnsKeyboard()` —
/// bare keys go dead the moment any text input has the keyboard), and
/// returns `.ignored` when gated, so nothing swallows keys during a take or
/// while typing.
struct ShotPlayerTransportKeys: ViewModifier {
    var isEnabled: Bool
    var onTogglePlayback: () -> Void
    var onPause: () -> Void
    var onShuttleForward: () -> Void
    var onShuttleReverse: () -> Void
    var onFrameStep: (Int) -> Void
    var onJumpToStart: () -> Void
    var onJumpToEnd: () -> Void
    var onToggleLoop: () -> Void
    /// Picture parity: the two-press blade and the in/out keys (⌥ clears).
    var onBlade: () -> Void = { }
    var onSetInPoint: (_ clear: Bool) -> Void = { _ in }
    var onSetOutPoint: (_ clear: Bool) -> Void = { _ in }
    /// THE ESCAPE LADDER's modal rungs; returns true when a rung consumed the
    /// press, false to let the hidden `.cancelAction` button close the modal.
    /// (A focused lane's selection deselects FIRST — it owns the keyboard —
    /// and only an unselected lane lets Escape bubble here.)
    var onEscapeLadder: () -> Bool = { false }
    /// The keyboard reference plate.
    var onShowKeymap: () -> Void = { }
    /// Opens the sound editor (the modal passes this; the editor sheet and
    /// FinalsReel keep the no-op default).
    var onOpenSoundEditor: () -> Void = { }

    @FocusState private var transportFocused: Bool

    /// One gate for every handler: enabled, and nobody is typing.
    private var keysAreLive: Bool {
        isEnabled && !shotTextInputOwnsKeyboard()
    }

    func body(content: Content) -> some View {
        content
            .focusable()
            .focusEffectDisabled()
            .focused($transportFocused)
            .onKeyPress(.space) {
                guard keysAreLive else { return .ignored }
                onTogglePlayback()
                return .handled
            }
            .onKeyPress(keys: ["k"]) { _ in
                guard keysAreLive else { return .ignored }
                onPause()
                return .handled
            }
            .onKeyPress(keys: ["l"]) { press in
                // ⌥L toggles loop; bare L shuttles. A focused lane with a
                // selected region owns bare L (region loop) and this handler
                // never sees it — the cheat sheet states both scopes.
                guard keysAreLive else { return .ignored }
                if press.modifiers.contains(.option) {
                    onToggleLoop()
                } else {
                    onShuttleForward()
                }
                return .handled
            }
            .onKeyPress(keys: ["j"]) { _ in
                guard keysAreLive else { return .ignored }
                onShuttleReverse()
                return .handled
            }
            .onKeyPress(keys: [",", "."]) { press in
                guard keysAreLive else { return .ignored }
                let frames = press.modifiers.contains(.shift) ? 10 : 1
                onFrameStep(press.key == "," ? -frames : frames)
                return .handled
            }
            .onKeyPress(keys: [.home, .end]) { press in
                guard keysAreLive else { return .ignored }
                if press.key == .home { onJumpToStart() } else { onJumpToEnd() }
                return .handled
            }
            .onKeyPress(keys: ["b"]) { _ in
                guard keysAreLive else { return .ignored }
                onBlade()
                return .handled
            }
            .onKeyPress(keys: ["i", "o"]) { press in
                guard keysAreLive else { return .ignored }
                let clear = press.modifiers.contains(.option)
                if press.key == "i" { onSetInPoint(clear) } else { onSetOutPoint(clear) }
                return .handled
            }
            .onKeyPress(keys: ["e"]) { _ in
                guard keysAreLive else { return .ignored }
                onOpenSoundEditor()
                return .handled
            }
            .onKeyPress(keys: ["?"]) { _ in
                // "?" is typed prose everywhere a field is focused.
                guard !shotTextInputOwnsKeyboard() else { return .ignored }
                onShowKeymap()
                return .handled
            }
            .onKeyPress(.escape) {
                // While typing, Escape belongs to the field/popover — the
                // modal's rungs must not fire invisibly underneath it.
                guard !shotTextInputOwnsKeyboard() else { return .ignored }
                return onEscapeLadder() ? .handled : .ignored
            }
            .onAppear {
                // Claim first responder before any text field can.
                transportFocused = true
            }
    }
}
