import AppKit
import SwiftUI

/// The world-map surface: a full-canvas overlay (the place-detail overlay
/// idiom, widened) where the operator seeds a top-down terrain map, grows it
/// edge by edge through the masked-outpaint pipeline, and pins roster places
/// onto it. All real geometry lives in TerrainMapGeometry; this view only
/// does display math (fit, zoom, pin positioning).
struct TerrainMapView: View {
    @ObservedObject var library: LibraryEngine
    var onClose: () -> Void

    @State private var seedPrompt = ""
    @State private var growthPromptDraft = ""
    @State private var descriptorDraft = ""
    @State private var selectedPlaceId: String?
    @State private var isSeedPickerPresented = false
    @State private var isConfirmingReseed = false
    @State private var zoom: CGFloat = 1
    @State private var draggingPinPlaceId: String?
    @State private var draggingPinPosition: CGPoint?
    @State private var canvasImage: NSImage?
    @State private var canvasImageMediaId = ""

    private var map: TerrainMapDocument { library.terrainMap }
    private var isBusy: Bool { library.isGrowingTerrainMap || library.isGeneratingTerrainSeed }

    var body: some View {
        ZStack {
            Color.black.opacity(0.16)
                .contentShape(Rectangle())
                .onTapGesture { onClose() }
            panel
                .background(CanonColor.paperInset)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(CanonColor.hairlinePaper))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(26)
            if isSeedPickerPresented {
                seedPickerLayer
            }
        }
        .transition(.opacity)
        .onAppear {
            growthPromptDraft = map.growthPrompt
            syncCanvasImage()
        }
        .onChange(of: map.currentMediaId) { _, _ in syncCanvasImage() }
        .onChange(of: selectedPlaceId) { _, _ in
            descriptorDraft = selectedPin?.descriptor ?? ""
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(CanonColor.hairlinePaper).frame(height: 1)
            HStack(spacing: 0) {
                placesRail
                    .frame(width: 210)
                    .frame(maxHeight: .infinity, alignment: .top)
                Rectangle().fill(CanonColor.hairlinePaper).frame(width: 1)
                mainContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let pin = selectedPin {
                    Rectangle().fill(CanonColor.hairlinePaper).frame(width: 1)
                    pinInspector(pin)
                        .frame(width: 230)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            if map.isSeeded {
                Rectangle().fill(CanonColor.hairlinePaper).frame(height: 1)
                growthBar
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "map")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CanonColor.brass)
            Text("World Map")
                .font(CanonType.editorial(17, weight: .semibold))
                .foregroundStyle(CanonColor.ink)
            if map.isSeeded {
                Text("\(map.canvasWidth)×\(map.canvasHeight) · cap \(TerrainMapGeometry.maxCanvasLongEdge)px")
                    .font(CanonType.interface(10.5))
                    .foregroundStyle(CanonColor.ink.opacity(0.5))
            }
            if isBusy {
                ProgressView().controlSize(.small)
            }
            Spacer(minLength: 0)
            if map.isSeeded {
                Button("Re-seed…") { isConfirmingReseed = true }
                    .buttonStyle(.plain)
                    .font(CanonType.interface(11, weight: .semibold))
                    .foregroundStyle(CanonColor.ink.opacity(0.6))
                    .disabled(isBusy)
                    .help("Start a new world map — pins clear, the growth prompt survives")
                    .confirmationDialog(
                        "Re-seeding starts a new world: every pin clears because its geography no longer exists.",
                        isPresented: $isConfirmingReseed,
                        titleVisibility: .visible
                    ) {
                        Button("Pick a new seed from Media", role: .destructive) {
                            isSeedPickerPresented = true
                        }
                        Button("Cancel", role: .cancel) {}
                    }
            }
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CanonColor.ink.opacity(0.55))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close the world map")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    // MARK: Places rail

    private var placesRail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("PLACES")
                    .font(CanonType.archive(8.5, weight: .semibold))
                    .kerning(1.4)
                    .foregroundStyle(CanonColor.muted)
                    .padding(.bottom, 2)
                if library.projectPlaces.places.isEmpty {
                    Text("No places yet — they arrive with FRAMES planning or from the Places sidebar.")
                        .font(CanonType.interface(11))
                        .foregroundStyle(CanonColor.ink.opacity(0.5))
                } else {
                    ForEach(library.projectPlaces.places) { place in
                        placeRailRow(place)
                    }
                }
            }
            .padding(12)
        }
    }

    private func placeRailRow(_ place: ProjectPlace) -> some View {
        let pinned = map.pin(forPlaceId: place.placeId) != nil
        let selected = selectedPlaceId == place.placeId
        return Button {
            if pinned {
                selectedPlaceId = place.placeId
            } else if map.isSeeded {
                // First pin lands center-map; the operator drags it home.
                if library.setTerrainMapPin(placeId: place.placeId, x: 0.5, y: 0.5) {
                    selectedPlaceId = place.placeId
                }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: pinned ? "mappin.circle.fill" : "mappin.slash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(pinned ? CanonColor.brass : CanonColor.ink.opacity(0.35))
                Text(place.name)
                    .font(CanonType.interface(11.5, weight: pinned ? .semibold : .regular))
                    .foregroundStyle(CanonColor.ink.opacity(pinned ? 1 : 0.7))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if !pinned, map.isSeeded {
                    Text("PIN")
                        .font(CanonType.archive(7.5, weight: .semibold))
                        .kerning(0.8)
                        .foregroundStyle(CanonColor.brass.opacity(0.8))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selected ? CanonColor.brass.opacity(0.12) : Color.white.opacity(0.4))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(selected ? CanonColor.brass.opacity(0.5) : CanonColor.hairlinePaper.opacity(0.8))
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(pinned ? "Select \(place.name)'s pin" : "Drop \(place.name) at the map center, then drag it home")
    }

    // MARK: Main content

    @ViewBuilder
    private var mainContent: some View {
        if !map.isSeeded {
            seedPane
        } else if library.terrainMapCanvasItem == nil {
            repairPane
        } else {
            canvasPane
        }
    }

    private var seedPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer(minLength: 0)
            Text("Seed the world")
                .font(CanonType.editorial(16, weight: .semibold))
                .foregroundStyle(CanonColor.ink)
            Text("One top-down map image starts the world. Generate it from a description, or pick an existing image from Media — then grow it outward edge by edge.")
                .font(CanonType.editorial(12.5))
                .foregroundStyle(CanonColor.ink.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
            TextField("A rugged coastline with fishing villages, pine highlands inland…", text: $seedPrompt, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
                .font(CanonType.interface(12))
            HStack(spacing: 10) {
                Button {
                    let prompt = seedPrompt
                    Task { await library.generateTerrainSeed(prompt: prompt) }
                } label: {
                    Label("Generate seed map", systemImage: "sparkles")
                        .font(CanonType.interface(12, weight: .semibold))
                }
                .disabled(isBusy || library.isGenerationPaused)
                .help(library.isGenerationPaused ? "Generation is paused — resume to continue" : "Render a fresh top-down seed map (spends one image render)")
                Button {
                    isSeedPickerPresented = true
                } label: {
                    Label("Pick from Media", systemImage: "photo.on.rectangle")
                        .font(CanonType.interface(12))
                }
                .disabled(isBusy)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 460)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var repairPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer(minLength: 0)
            Label("The map canvas is missing from the Library", systemImage: "exclamationmark.triangle")
                .font(CanonType.editorial(14, weight: .semibold))
                .foregroundStyle(CanonColor.ink)
            Text("The document still remembers this world, but its image was deleted. Revert to the previous canvas if one survives, or re-seed to start a new world.")
                .font(CanonType.editorial(12))
                .foregroundStyle(CanonColor.ink.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Revert last growth") { _ = library.revertTerrainMapLastGrowth() }
                    .disabled(isBusy)
                Button("Re-seed from Media") { isSeedPickerPresented = true }
                    .disabled(isBusy)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 460)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var canvasPane: some View {
        GeometryReader { proxy in
            let fitted = excursionFittedFrame(
                imagePixelSize: CGSize(width: map.canvasWidth, height: map.canvasHeight),
                containerSize: proxy.size
            )
            let displaySize = CGSize(width: fitted.width * zoom, height: fitted.height * zoom)
            ScrollView([.horizontal, .vertical]) {
                canvasContent(displaySize: displaySize)
                    .frame(
                        minWidth: proxy.size.width,
                        minHeight: proxy.size.height
                    )
            }
        }
        .overlay(alignment: .bottomTrailing) { zoomControls.padding(10) }
    }

    private func canvasContent(displaySize: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            if let canvasImage {
                Image(nsImage: canvasImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: displaySize.width, height: displaySize.height)
            }
            if let pin = selectedPin {
                regionOutline(pin: pin, displaySize: displaySize)
            }
            ForEach(map.pins) { pin in
                pinMarker(pin: pin, displaySize: displaySize)
            }
        }
        .frame(width: displaySize.width, height: displaySize.height)
        .overlay(RoundedRectangle(cornerRadius: 2).stroke(CanonColor.hairlinePaper))
        .padding(20)
    }

    private func regionOutline(pin: TerrainMapPin, displaySize: CGSize) -> some View {
        let position = pinDisplayPosition(pin, displaySize: displaySize)
        let width = CGFloat(pin.regionWidth) * displaySize.width
        let height = CGFloat(pin.regionHeight) * displaySize.height
        return Rectangle()
            .stroke(CanonColor.brass.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .frame(width: width, height: height)
            .position(position)
            .allowsHitTesting(false)
    }

    private func pinMarker(pin: TerrainMapPin, displaySize: CGSize) -> some View {
        let name = library.projectPlaces.place(withId: pin.placeId)?.name ?? "?"
        let selected = selectedPlaceId == pin.placeId
        return VStack(spacing: 2) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: selected ? 20 : 16, weight: .semibold))
                .foregroundStyle(selected ? CanonColor.brass : CanonColor.ink.opacity(0.75))
                .background(Circle().fill(Color.white.opacity(0.85)).padding(2))
            Text(name)
                .font(CanonType.interface(9.5, weight: .semibold))
                .foregroundStyle(CanonColor.ink)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Capsule().fill(Color.white.opacity(0.85)))
        }
        .position(pinDisplayPosition(pin, displaySize: displaySize))
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    draggingPinPlaceId = pin.placeId
                    selectedPlaceId = pin.placeId
                    draggingPinPosition = CGPoint(
                        x: min(max(0, value.location.x / max(1, displaySize.width)), 1),
                        y: min(max(0, value.location.y / max(1, displaySize.height)), 1)
                    )
                }
                .onEnded { _ in
                    if let position = draggingPinPosition {
                        _ = library.setTerrainMapPin(placeId: pin.placeId, x: position.x, y: position.y)
                    }
                    draggingPinPlaceId = nil
                    draggingPinPosition = nil
                }
        )
        .onTapGesture { selectedPlaceId = pin.placeId }
        .help("\(name) — drag to move")
    }

    private func pinDisplayPosition(_ pin: TerrainMapPin, displaySize: CGSize) -> CGPoint {
        if draggingPinPlaceId == pin.placeId, let live = draggingPinPosition {
            return CGPoint(x: live.x * displaySize.width, y: live.y * displaySize.height)
        }
        return CGPoint(
            x: CGFloat(pin.x) * displaySize.width,
            y: CGFloat(pin.y) * displaySize.height
        )
    }

    private var zoomControls: some View {
        HStack(spacing: 6) {
            Button {
                zoom = max(0.5, zoom / 1.4)
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            Text("\(Int((zoom * 100).rounded()))%")
                .font(CanonType.interface(10))
                .foregroundStyle(CanonColor.ink.opacity(0.6))
                .frame(width: 40)
            Button {
                zoom = min(6, zoom * 1.4)
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.white.opacity(0.85)))
        .overlay(Capsule().stroke(CanonColor.hairlinePaper))
    }

    // MARK: Growth bar

    private var growthBar: some View {
        HStack(spacing: 10) {
            ForEach(TerrainGrowthDirection.allCases) { direction in
                growButton(direction)
            }
            TextField("Growth prompt — rides every pass", text: $growthPromptDraft)
                .textFieldStyle(.roundedBorder)
                .font(CanonType.interface(11.5))
                .frame(maxWidth: 360)
                .onSubmit { _ = library.setTerrainMapGrowthPrompt(growthPromptDraft) }
            Spacer(minLength: 0)
            Button("Revert last growth") { _ = library.revertTerrainMapLastGrowth() }
                .font(CanonType.interface(11))
                .disabled(isBusy || map.revisions.count < 2)
                .help("Repoint at the previous canvas and restore its pins")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func growButton(_ direction: TerrainGrowthDirection) -> some View {
        let capBlocked = TerrainMapGeometry.growthPlan(
            canvasWidth: map.canvasWidth,
            canvasHeight: map.canvasHeight,
            direction: direction
        ) == nil
        let reason = library.terrainMapGrowStartBlockReason
            ?? (capBlocked ? "The map is at its \(TerrainMapGeometry.maxCanvasLongEdge)px ceiling on that side" : nil)
        return Button {
            // Commit any prompt edit with the same gesture that spends it.
            if growthPromptDraft.trimmed != map.growthPrompt {
                _ = library.setTerrainMapGrowthPrompt(growthPromptDraft)
            }
            Task { await library.growTerrainMap(direction: direction) }
        } label: {
            Label(direction.label, systemImage: growIcon(direction))
                .font(CanonType.interface(11, weight: .semibold))
        }
        .disabled(reason != nil)
        .help(reason ?? "Grow the map \(direction.label.lowercased()) — spends one image render")
    }

    private func growIcon(_ direction: TerrainGrowthDirection) -> String {
        switch direction {
        case .north: return "arrow.up"
        case .south: return "arrow.down"
        case .east: return "arrow.right"
        case .west: return "arrow.left"
        case .radial: return "arrow.up.left.and.arrow.down.right"
        }
    }

    // MARK: Pin inspector

    private func pinInspector(_ pin: TerrainMapPin) -> some View {
        let name = library.projectPlaces.place(withId: pin.placeId)?.name ?? "Pin"
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(name)
                    .font(CanonType.editorial(14, weight: .semibold))
                    .foregroundStyle(CanonColor.ink)
                VStack(alignment: .leading, spacing: 5) {
                    Text("REGION")
                        .font(CanonType.archive(8.5, weight: .semibold))
                        .kerning(1.4)
                        .foregroundStyle(CanonColor.muted)
                    regionStepper(
                        label: "Width",
                        value: pin.regionWidth
                    ) { library.setTerrainMapPinRegion(placeId: pin.placeId, width: $0, height: pin.regionHeight) }
                    regionStepper(
                        label: "Height",
                        value: pin.regionHeight
                    ) { library.setTerrainMapPinRegion(placeId: pin.placeId, width: pin.regionWidth, height: $0) }
                    Text("The dashed region is the map crop that rides this place's renders.")
                        .font(CanonType.interface(10))
                        .foregroundStyle(CanonColor.ink.opacity(0.45))
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("NOTE")
                        .font(CanonType.archive(8.5, weight: .semibold))
                        .kerning(1.4)
                        .foregroundStyle(CanonColor.muted)
                    TextField("coastal cliffs on the northwest shore…", text: $descriptorDraft, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                        .font(CanonType.interface(11.5))
                        .onSubmit { _ = library.setTerrainMapPinDescriptor(placeId: pin.placeId, descriptor: descriptorDraft) }
                }
                Button("Remove pin", role: .destructive) {
                    _ = library.removeTerrainMapPin(placeId: pin.placeId)
                    selectedPlaceId = nil
                }
                .font(CanonType.interface(11))
            }
            .padding(14)
        }
    }

    private func regionStepper(
        label: String,
        value: Double,
        onChange: @escaping (Double) -> Bool
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(CanonType.interface(11))
                .foregroundStyle(CanonColor.ink.opacity(0.7))
            Spacer(minLength: 0)
            Stepper(
                "\(Int((value * 100).rounded()))%",
                value: Binding(
                    get: { value },
                    set: { _ = onChange($0) }
                ),
                in: TerrainMapPin.minimumRegionExtent...1,
                step: 0.05
            )
            .font(CanonType.interface(11))
        }
    }

    // MARK: Seed picker

    private var seedPickerLayer: some View {
        ZStack {
            Color.black.opacity(0.2)
                .contentShape(Rectangle())
                .onTapGesture { isSeedPickerPresented = false }
            MediaPickerSheet(
                title: map.isSeeded ? "Pick a new seed map" : "Pick a seed map",
                subtitle: "One top-down image becomes the world map canvas. Growth passes extend it outward from there.",
                items: library.items.filter { $0.kind == .image },
                observationsById: [:],
                selectionLimit: 1,
                confirmLabel: "Seed map",
                onConfirm: { picks in
                    isSeedPickerPresented = false
                    guard case .media(let item)? = picks.first else { return }
                    selectedPlaceId = nil
                    Task { await library.seedTerrainMapFromMedia(mediaId: item.mediaId) }
                },
                onCancel: { isSeedPickerPresented = false }
            )
            .frame(width: 680, height: 520)
        }
    }

    // MARK: State sync

    private var selectedPin: TerrainMapPin? {
        selectedPlaceId.flatMap { map.pin(forPlaceId: $0) }
    }

    private func syncCanvasImage() {
        guard let item = library.terrainMapCanvasItem else {
            canvasImage = nil
            canvasImageMediaId = ""
            return
        }
        guard item.mediaId != canvasImageMediaId else { return }
        canvasImage = NSImage(contentsOfFile: item.path)
        canvasImageMediaId = item.mediaId
    }
}
