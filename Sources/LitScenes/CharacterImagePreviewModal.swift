import AppKit
import SwiftUI

/// Full-resolution inspection, independent of which sheet version anchors the character.
struct CharacterImagePreviewModal: View {
    let request: StyleImagePreviewRequest
    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1
    @State private var actualSizeZoom: CGFloat = 1
    @State private var followsActualSize = true

    private var path: String { URL(string: request.url)?.path ?? "" }
    private var minimumZoom: CGFloat { min(0.2, actualSizeZoom) }
    private var maximumZoom: CGFloat { max(8, actualSizeZoom * 2) }

    private var presentationSize: CGSize {
        let visible = (NSApp.keyWindow?.screen ?? NSScreen.main)?.visibleFrame.size
            ?? CGSize(width: 1440, height: 900)
        return CGSize(width: visible.width * 0.94, height: visible.height * 0.9)
    }

    private var interactiveZoom: Binding<CGFloat> {
        Binding(get: { zoom }, set: { value in
            followsActualSize = false
            zoom = value
        })
    }

    private func updateActualSizeZoom(_ value: CGFloat) {
        guard value.isFinite, value > 0 else { return }
        if abs(value - actualSizeZoom) > 0.001 { actualSizeZoom = value }
        // Keep 100% through the sheet's opening layout and screen-scale changes.
        if followsActualSize, abs(value - zoom) > 0.001 { zoom = value }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(request.label)
                        .font(CanonType.editorial(18, weight: .semibold))
                        .foregroundStyle(CanonColor.bone)
                    Text(request.detail)
                        .font(CanonType.interface(11))
                        .foregroundStyle(CanonColor.muted)
                }
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            if FileManager.default.fileExists(atPath: path) {
                ZoomableImageScrollView(
                    path: path, zoomScale: interactiveZoom, minZoom: minimumZoom, maxZoom: maximumZoom,
                    inspectionMode: true,
                    onActualSizeZoomChange: updateActualSizeZoom
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ContentUnavailableView("Image unavailable", systemImage: "photo", description: Text("The original image file could not be found."))
            }
            HStack(spacing: 12) {
                Button("Fit") { followsActualSize = false; zoom = 1 }
                    .keyboardShortcut("0", modifiers: .command)
                Button("Actual size") { followsActualSize = true; zoom = actualSizeZoom }
                    .keyboardShortcut("1", modifiers: .command)
                Button { interactiveZoom.wrappedValue = max(minimumZoom, zoom / 1.25) } label: { Image(systemName: "minus.magnifyingglass") }
                    .accessibilityLabel("Zoom out")
                    .keyboardShortcut("-", modifiers: .command)
                Text("\(Int((zoom / actualSizeZoom * 100).rounded()))%")
                    .font(CanonType.interface(12))
                    .monospacedDigit()
                    .frame(minWidth: 45)
                Button { interactiveZoom.wrappedValue = min(maximumZoom, zoom * 1.25) } label: { Image(systemName: "plus.magnifyingglass") }
                    .accessibilityLabel("Zoom in")
                    .keyboardShortcut("+", modifiers: .command)
                Spacer()
                Text("Pinch to zoom · Scroll or drag to pan")
                    .font(CanonType.interface(11))
                    .foregroundStyle(CanonColor.muted)
            }
        }
        .padding(16)
        .frame(width: presentationSize.width, height: presentationSize.height)
        .background(CanonColor.room)
        .onChange(of: request.id) { _, _ in
            followsActualSize = true
            zoom = 1
            actualSizeZoom = 1
        }
    }
}
