import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ChatComposerAttachment: Identifiable, Hashable {
    var mediaId: String
    var id: String { mediaId }
    var filename: String
    var thumbnailPath: String
    var kind: MediaKind
}

struct ChatComposerView: View {
    @Binding var text: String
    var attachments: [ChatComposerAttachment]
    var placeholder: String
    var statusText: String
    var isWaiting: Bool
    var canSend: Bool
    var onSend: () -> Void
    var onUpload: () -> Void
    var onRemoveAttachment: (String) -> Void
    var onPasteImageData: (Data) -> Void
    var onPasteFileURLs: ([URL]) -> Void
    var onDropMediaIds: ([String]) -> Void

    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if !attachments.isEmpty {
                attachmentTray
            }

            ZStack(alignment: .topLeading) {
                PasteAwareTextView(
                    text: $text,
                    isEditable: !isWaiting,
                    onSubmit: {
                        if canSend {
                            onSend()
                        }
                    },
                    onPasteImageData: onPasteImageData,
                    onPasteFileURLs: onPasteFileURLs
                )
                .frame(minHeight: 112, maxHeight: 150)
                .background(Color.white.opacity(0.70), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isDropTargeted ? CanonColor.focusBlue : CanonColor.hairlinePaper, lineWidth: isDropTargeted ? 2 : 1)
                )
                .dropDestination(for: MediaIDTransfer.self) { transfers, _ in
                    guard !isWaiting else { return false }
                    let mediaIds = transfers.map(\.mediaId)
                    onDropMediaIds(mediaIds)
                    return !mediaIds.isEmpty
                } isTargeted: { targeted in
                    isDropTargeted = targeted && !isWaiting
                }

                if text.trimmed.isEmpty {
                    Text(placeholder)
                        .font(CanonType.editorial(14))
                        .foregroundStyle(CanonColor.ink.opacity(0.44))
                        .padding(.horizontal, 15)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }

            HStack(spacing: 8) {
                Button {
                    onUpload()
                } label: {
                    Label("Upload", systemImage: "paperclip")
                        .font(CanonType.interface(12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(CanonColor.ink)
                .disabled(isWaiting)
                .opacity(isWaiting ? 0.44 : 1)
                .help("Upload image attachments")

                if !statusText.trimmed.isEmpty {
                    Text(statusText.trimmed)
                        .font(CanonType.interface(11))
                        .foregroundStyle(CanonColor.ink.opacity(0.58))
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    onSend()
                } label: {
                    Text("Send")
                        .font(CanonType.interface(12, weight: .semibold))
                        .foregroundStyle(CanonColor.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(CanonColor.softGold.opacity(0.82), in: RoundedRectangle(cornerRadius: 7))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(CanonColor.brass.opacity(0.78))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .opacity(canSend ? 1 : 0.44)
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
    }

    private var attachmentTray: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(attachments) { attachment in
                    HStack(spacing: 6) {
                        ChatAttachmentThumbnail(path: attachment.thumbnailPath, kind: attachment.kind)
                            .frame(width: 36, height: 28)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        Text(attachment.filename)
                            .font(CanonType.interface(11, weight: .semibold))
                            .foregroundStyle(CanonColor.ink)
                            .lineLimit(1)
                        Button {
                            onRemoveAttachment(attachment.mediaId)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2.weight(.bold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(CanonColor.muted)
                        .help("Remove attachment")
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(CanonColor.paperInset.opacity(0.72), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(CanonColor.hairlinePaper)
                    )
                }
            }
        }
    }
}

private struct ChatAttachmentThumbnail: View {
    let path: String
    let kind: MediaKind

    var body: some View {
        Group {
            if kind == .image, let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    CanonColor.paperInset
                    Image(systemName: kind == .video ? "film" : "photo")
                        .foregroundStyle(CanonColor.muted)
                }
            }
        }
        .clipped()
    }
}

private struct PasteAwareTextView: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool
    var onSubmit: () -> Void
    var onPasteImageData: (Data) -> Void
    var onPasteFileURLs: ([URL]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder

        let textView = PasteInterceptingTextView()
        textView.delegate = context.coordinator
        textView.owner = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.font = NSFont.systemFont(ofSize: 15)
        textView.textColor = NSColor(CanonColor.ink)
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? PasteInterceptingTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.isEditable = isEditable
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PasteAwareTextView

        init(_ parent: PasteAwareTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func submit() {
            parent.onSubmit()
        }

        func paste(_ sender: PasteInterceptingTextView) {
            let pasteboard = NSPasteboard.general
            let imageFileURLs = pastedImageFileURLs(from: pasteboard)
            if !imageFileURLs.isEmpty {
                parent.onPasteFileURLs(imageFileURLs)
                return
            }
            if let data = pastedImageData(from: pasteboard) {
                parent.onPasteImageData(data)
                return
            }
            sender.defaultPaste(nil)
        }

        private func pastedImageFileURLs(from pasteboard: NSPasteboard) -> [URL] {
            guard let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] else { return [] }
            return urls.filter { url in
                guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
                return type.conforms(to: .image)
            }
        }

        private func pastedImageData(from pasteboard: NSPasteboard) -> Data? {
            for type in [NSPasteboard.PasteboardType.png, .tiff] {
                if let data = pasteboard.data(forType: type), !data.isEmpty {
                    return data
                }
            }
            if let image = NSImage(pasteboard: pasteboard),
               let tiff = image.tiffRepresentation {
                return tiff
            }
            return nil
        }
    }
}

private final class PasteInterceptingTextView: NSTextView {
    weak var owner: PasteAwareTextView.Coordinator?

    override func paste(_ sender: Any?) {
        owner?.paste(self)
    }

    func defaultPaste(_ sender: Any?) {
        super.paste(sender)
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers == "\r" {
            owner?.submit()
            return
        }
        super.keyDown(with: event)
    }
}
