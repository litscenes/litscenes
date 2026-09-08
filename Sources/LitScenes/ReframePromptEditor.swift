import AppKit
import SwiftUI

/// Native text colors and appearance prevent a dark room from washing out paper editors.
struct ReframePromptEditor: NSViewRepresentable {
    @Binding var text: String
    var isEditable = true

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let editor = scroll.documentView as? NSTextView else { return scroll }
        editor.delegate = context.coordinator
        editor.isRichText = false
        editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.textContainerInset = NSSize(width: 8, height: 8)
        editor.font = .systemFont(ofSize: 12.5)
        editor.setAccessibilityLabel(isEditable ? "Reframe instructions" : "Composed camera prompt")
        configure(scroll, editor: editor)
        editor.string = text
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.owner = self
        guard let editor = scroll.documentView as? NSTextView else { return }
        configure(scroll, editor: editor)
        if editor.string != text { editor.string = text }
    }

    private func configure(_ scroll: NSScrollView, editor: NSTextView) {
        let paper = NSColor(srgbRed: 246.0 / 255, green: 239.0 / 255, blue: 220.0 / 255, alpha: 1)
        let ink = NSColor(srgbRed: 32.0 / 255, green: 26.0 / 255, blue: 18.0 / 255, alpha: 1)
        scroll.appearance = NSAppearance(named: .aqua)
        scroll.drawsBackground = true
        scroll.backgroundColor = paper
        editor.backgroundColor = paper
        editor.textColor = ink
        editor.insertionPointColor = ink
        editor.isEditable = isEditable
        editor.isSelectable = true
        editor.typingAttributes = [.foregroundColor: ink, .font: NSFont.systemFont(ofSize: 12.5)]
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var owner: ReframePromptEditor
        init(_ owner: ReframePromptEditor) { self.owner = owner }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            owner.text = editor.string
        }
    }
}

struct LensReframeGenerateAction: View {
    let mode: String
    let hasFocus: Bool
    let canReframe: Bool
    let stackConfigured: Bool
    let blockReason: String
    var onGenerate: () -> Void

    private var reason: String {
        if !canReframe { return "Select a ready Frame to reframe." }
        if !blockReason.isEmpty { return blockReason }
        if !stackConfigured { return "Add this provider's key in Settings." }
        if mode != LensReframeSpec.zoomOutMode && !hasFocus {
            return mode == LensReframeSpec.viewpointMode ? "Select a camera position in the image." : "Select a focus area in the image."
        }
        return ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !reason.isEmpty {
                Text(reason).font(CanonType.interface(10)).foregroundStyle(CanonColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: onGenerate) {
                Label(mode == LensReframeSpec.viewpointMode ? "Generate camera turn" : (mode == LensReframeSpec.zoomOutMode ? "Generate zoom out" : "Generate zoom in"), systemImage: "sparkles")
                    .font(CanonType.interface(11, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(CanonSecondaryButtonStyle(isFullWidth: true))
            .disabled(!reason.isEmpty)
            .accessibilityIdentifier("reframe-generate")
        }
    }
}
