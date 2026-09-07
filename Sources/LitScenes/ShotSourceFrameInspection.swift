import SwiftUI
import AppKit

/// Read-only source inspection within the Shot's editing context.
struct ShotSourceFrameInspection: View {
    @ObservedObject var library: LibraryEngine
    let shotId: String
    let entryId: String
    var onClose: () -> Void

    private var frame: ProjectLensHeroImage? {
        guard let entry = library.shotTimeline.shots.first(where: { $0.shotId == shotId })?.entries.first(where: { $0.entryId == entryId }) else { return nil }
        return library.projectLenses.lenses.flatMap(\.heroImages).first { $0.imageId == entry.frameImageId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(frame?.label.trimmed.nilIfEmpty ?? "Frame").font(.headline)
                Spacer()
                Button("CLOSE", action: onClose).buttonStyle(PlateButtonStyle())
            }
            if let frame, let image = NSImage(contentsOfFile: frame.imagePath) {
                Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
                Button("OPEN IMAGE") { NSWorkspace.shared.open(URL(fileURLWithPath: frame.imagePath)) }
                    .buttonStyle(PlateButtonStyle())
            } else {
                ContentUnavailableView("Frame not rendered", systemImage: "photo", description: Text("Use ART DIRECT below this Frame in the Shot row to create it."))
            }
            if let frame { Text(frame.prompt).font(.caption).lineLimit(6).textSelection(.enabled) }
        }
        .padding(20)
        .frame(width: 820, height: 640)
        .background(PlateColor.cream)
    }
}
