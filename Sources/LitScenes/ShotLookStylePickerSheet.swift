import SwiftUI

/// Plate-framed single-select wrapper around LensStyleBrowserPanel for the
/// Shot/Clip Look picker: one catalog choice snapshots both the text summary
/// used by FAL and the verified image reference used by direct Decart.
struct ShotLookStylePickerSheet: View {
    let initialSelection: ShotLookStyleSelection?
    var provider: ShotLookProvider = .fal
    var onApply: (ShotLookStyleSelection) -> Void
    var onCancel: () -> Void

    @State private var selectedSlot: LensStyleTreatmentSlot?
    @State private var catalogVersion = ""
    @State private var unusedPrimarySlot: LensStyleTreatmentSlot?
    @State private var unusedAccentSlots: [LensStyleTreatmentSlot] = []
    @State private var previewRequest: StyleImagePreviewRequest?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                PlateLabel(text: "SHOT LOOK STYLE", size: 11, weight: .bold)
                Rectangle().fill(PlateColor.hairline).frame(height: 1)
                PlateLabel(
                    text: provider == .decart ? "LUCY · IMAGE INPUT" : "LUCY · TEXT INPUT",
                    size: 8.5,
                    color: PlateColor.inkFaint
                )
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PlateColor.inkFaint)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Close without changing the style")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Rectangle().fill(PlateColor.hairline).frame(height: 1)

            LensStyleBrowserPanel(
                primarySlot: $unusedPrimarySlot,
                accentSlots: $unusedAccentSlots,
                catalogVersion: $catalogVersion,
                onPreviewStyle: { previewRequest = $0 },
                selectedStyleSlot: $selectedSlot
            )
            .frame(width: 940, height: 610)

            Rectangle().fill(PlateColor.hairline).frame(height: 1)

            HStack(spacing: 10) {
                if let selectedSlot {
                    PlateLabel(
                        text: "SELECTED · \(selectedSlot.label)",
                        size: 8.5,
                        weight: .semibold,
                        color: PlateColor.ink
                    )
                    .lineLimit(1)
                } else {
                    Text(provider == .decart
                        ? "Choose one catalog style — its verified image is attached to Decart."
                        : "Choose one catalog style — its one-line summary leads the Lucy prompt.")
                        .font(.system(size: 10, design: .serif))
                        .foregroundStyle(PlateColor.inkFaint)
                }
                Spacer()
                Button("CANCEL", action: onCancel)
                    .buttonStyle(PlateButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("USE STYLE", action: applySelection)
                    .buttonStyle(PlateButtonStyle(isProminent: true))
                    .disabled(selectedSlot == nil)
            }
            .padding(16)
        }
        .background(PlateColor.cream)
        .environment(\.colorScheme, .light)
        .sheet(item: $previewRequest) { request in
            StyleImagePreviewModal(request: request)
        }
        .onAppear {
            guard let initialSelection, initialSelection.isUsable, selectedSlot == nil else { return }
            selectedSlot = LensStyleTreatmentSlot(
                styleId: initialSelection.styleId,
                label: initialSelection.label,
                collection: initialSelection.collection,
                hueHex: initialSelection.hueHex,
                url: initialSelection.url,
                weight: 100
            )
        }
    }

    private func applySelection() {
        guard let slot = selectedSlot else { return }
        Task { @MainActor in
            let catalog = try? await StyleBrowseCatalogRuntime.shared.loadCatalog()
            let style = catalog?.style(withId: slot.styleId)
            let resolvedCatalogVersion = (catalog?.version ?? "").nilIfEmpty ?? catalogVersion
            onApply(ShotLookStyleSelection(
                styleId: slot.styleId,
                label: style?.displayLabel ?? slot.label,
                collection: slot.collection,
                hueHex: slot.hueHex,
                url: slot.url,
                summary: style?.styleSummaryLine ?? slot.label,
                catalogVersion: resolvedCatalogVersion,
                imageReference: style?.styleImageReference(catalogVersion: resolvedCatalogVersion)
            ))
        }
    }
}
