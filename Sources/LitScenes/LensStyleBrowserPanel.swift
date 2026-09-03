import SwiftUI

/// Embeddable style-catalog browser for the Lens workbench's inline studio mode: a filter
/// rail (collections, mood, palette) beside a collection-grouped style grid. Selection
/// edits the bound draft slots only — committing is the blend console's job. Canon paper
/// idiom; the old dark-room modal died with the sheet.
struct LensStyleBrowserPanel: View {
    @Binding var primarySlot: LensStyleTreatmentSlot?
    @Binding var accentSlots: [LensStyleTreatmentSlot]
    @Binding var catalogVersion: String
    var onPreviewStyle: (StyleImagePreviewRequest) -> Void = { _ in }
    var selectedStyleSlot: Binding<LensStyleTreatmentSlot?>? = nil

    @State private var catalog = StyleBrowseCatalog.empty
    @State private var loadError = ""
    @State private var loadWarning = ""
    @State private var isLoading = true
    @State private var selectedCollectionKey = ""
    @State private var selectedMoods: Set<String> = []
    @State private var selectedHues: Set<String> = []

    private static let allMoods = [
        "Calm", "Mysterious", "Nostalgic", "Elegant", "Energetic", "Dreamlike",
        "Melancholic", "Romantic", "Serious", "Sublime", "Whimsical"
    ]

    var body: some View {
        VStack(spacing: 0) {
            if !loadWarning.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(loadWarning)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Link("Terms", destination: LitScenesReleaseIdentity.catalogTermsURL)
                }
                .font(CanonType.interface(10))
                .foregroundStyle(CanonColor.ink.opacity(0.78))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(CanonColor.brass.opacity(0.12))
            }
            if isLoading {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Loading style catalog")
                        .font(CanonType.interface(12))
                        .foregroundStyle(CanonColor.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !loadError.isEmpty {
                VStack(spacing: 12) {
                    Text(loadError)
                        .font(CanonType.interface(13))
                        .foregroundStyle(CanonColor.ink)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                    Button("Retry") {
                        Task { await loadCatalog(force: true) }
                    }
                    .buttonStyle(.plain)
                    .font(CanonType.interface(12, weight: .semibold))
                    .foregroundStyle(CanonColor.brass)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: 0) {
                    filterRail
                        .frame(width: 208)
                    Rectangle().fill(CanonColor.hairlinePaper).frame(width: 1)
                    styleGrid
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .task {
            await loadCatalog()
        }
    }

    // MARK: - Filter rail

    private var filterRail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                railSection("Collections") {
                    VStack(alignment: .leading, spacing: 1) {
                        collectionRow(key: "", name: "All collections", dotHex: "", count: filteredStyles.count)
                        ForEach(catalog.displayCollections) { collection in
                            collectionRow(
                                key: collection.key,
                                name: collection.name,
                                dotHex: collection.dotColorHex,
                                count: filteredCollectionCounts[collection.key] ?? 0
                            )
                        }
                    }
                }
                railSection("Mood") {
                    FlowChips(items: Self.allMoods.filter { moodCounts[$0, default: 0] > 0 }) { mood in
                        filterChip(mood, isOn: selectedMoods.contains(mood)) {
                            toggle(&selectedMoods, mood)
                        }
                    }
                }
                railSection("Palette") {
                    FlowChips(items: hueOrder) { hueName in
                        hueChip(hueName)
                    }
                }
                if !selectedMoods.isEmpty || !selectedHues.isEmpty {
                    Button("Clear filters") {
                        selectedMoods = []
                        selectedHues = []
                    }
                    .buttonStyle(.plain)
                    .font(CanonType.archive(10))
                    .foregroundStyle(CanonColor.muted)
                    .underline()
                }
                Link("Catalog terms", destination: LitScenesReleaseIdentity.catalogTermsURL)
                    .font(CanonType.archive(10))
                    .foregroundStyle(CanonColor.muted)
            }
            .padding(14)
        }
        .background(CanonColor.paperInset.opacity(0.5))
    }

    private func railSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title.uppercased())
                .font(CanonType.archive(9, weight: .semibold))
                .kerning(1.6)
                .foregroundStyle(CanonColor.muted)
            content()
        }
    }

    private func collectionRow(key: String, name: String, dotHex: String, count: Int) -> some View {
        Button {
            selectedCollectionKey = key
        } label: {
            HStack(spacing: 8) {
                if dotHex.isEmpty {
                    Circle().fill(CanonColor.muted.opacity(0.5)).frame(width: 8, height: 8)
                } else {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(canonColor(fromHex: dotHex))
                        .frame(width: 8, height: 8)
                }
                Text(name)
                    .font(CanonType.interface(12, weight: selectedCollectionKey == key ? .semibold : .regular))
                    .foregroundStyle(CanonColor.ink.opacity(selectedCollectionKey == key ? 1 : 0.78))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(count)")
                    .font(CanonType.archive(10))
                    .foregroundStyle(CanonColor.muted)
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selectedCollectionKey == key ? CanonColor.paper : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func filterChip(_ label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(CanonType.interface(11))
                .foregroundStyle(isOn ? CanonColor.brass : CanonColor.ink.opacity(0.68))
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(
                    Capsule().fill(isOn ? CanonColor.brass.opacity(0.13) : Color.clear)
                )
                .overlay(
                    Capsule().stroke(isOn ? CanonColor.brass : CanonColor.hairlinePaper, lineWidth: 1)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func hueChip(_ hueName: String) -> some View {
        let isOn = selectedHues.contains(hueName)
        let hex = hueHexByName[hueName] ?? ""
        return Button {
            toggle(&selectedHues, hueName)
        } label: {
            Circle()
                .fill(canonColor(fromHex: hex))
                .frame(width: 22, height: 22)
                .overlay(Circle().stroke(isOn ? CanonColor.ink : CanonColor.hairlinePaper, lineWidth: 2))
                .overlay(
                    Circle()
                        .stroke(isOn ? CanonColor.brass : Color.clear, lineWidth: 2)
                        .padding(-3)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(hueName)
    }

    // MARK: - Grid

    private var styleGrid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24, pinnedViews: []) {
                ForEach(visibleCollections) { collection in
                    let items = filteredStyles.filter { $0.collection == collection.key }
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(canonColor(fromHex: collection.dotColorHex))
                                    .frame(width: 9, height: 9)
                                Text(collection.name)
                                    .font(CanonType.editorial(16, weight: .semibold))
                                    .foregroundStyle(CanonColor.ink)
                                Text("\(items.count)")
                                    .font(CanonType.archive(10))
                                    .foregroundStyle(CanonColor.muted)
                            }
                            Text(collection.description)
                                .font(CanonType.interface(11))
                                .foregroundStyle(CanonColor.muted)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 172), spacing: 12)], spacing: 12) {
                                ForEach(items) { style in
                                    styleCard(style)
                                }
                            }
                        }
                    }
                }
                if filteredStyles.isEmpty {
                    Text("No styles match those filters.")
                        .font(CanonType.interface(13))
                        .foregroundStyle(CanonColor.muted)
                        .padding(.top, 40)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(16)
        }
    }

    private func styleCard(_ style: StyleBrowseStyle) -> some View {
        let pickerSlot = selectedStyleSlot?.wrappedValue
        let isPickerMode = selectedStyleSlot != nil
        let isPickerSelected = pickerSlot?.styleId == style.id
        let role = isPickerMode ? nil : role(of: style.id)
        let borderColor: Color? = switch role {
        case .primary: CanonColor.rolePrimary
        case .accent(let index): CanonColor.roleTint(forSlotIndex: index + 1)
        case nil: nil
        }
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                onPreviewStyle(StyleImagePreviewRequest(url: style.url, label: style.displayLabel, detail: style.medium))
            } label: {
                AsyncImage(url: URL(string: style.url)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        CanonColor.paperInset
                    }
                }
                .frame(height: 124)
                .clipped()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 6) {
                Text(style.displayLabel)
                    .font(CanonType.editorial(12.5, weight: .medium))
                    .foregroundStyle(CanonColor.ink)
                    .lineLimit(2, reservesSpace: true)
                HStack(spacing: 6) {
                    Circle()
                        .fill(canonColor(fromHex: style.hueHex))
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(CanonColor.hairlinePaper))
                    Text(style.medium.uppercased())
                        .font(CanonType.archive(8.5))
                        .kerning(0.5)
                        .foregroundStyle(CanonColor.muted)
                        .lineLimit(1)
                }
                if let selectedStyleSlot {
                    cardButton(
                        isPickerSelected ? "Selected ✓" : "Use Style",
                        emphasized: isPickerSelected,
                        tint: CanonColor.brass
                    ) {
                        selectedStyleSlot.wrappedValue = style.treatmentSlot(weight: 100)
                    }
                } else {
                    HStack(spacing: 6) {
                        cardButton(
                            role == .primary ? "Primary ✓" : "Set primary",
                            emphasized: role == .primary,
                            tint: CanonColor.rolePrimary
                        ) {
                            setPrimary(style)
                        }
                        cardButton(
                            accentButtonLabel(for: style.id, role: role),
                            emphasized: isAccent(role),
                            tint: CanonColor.roleAccentOne
                        ) {
                            toggleAccent(style)
                        }
                        .disabled(role == nil && accentSlots.count >= 2)
                        .opacity(role == nil && accentSlots.count >= 2 ? 0.4 : 1)
                    }
                }
            }
            .padding(9)
        }
        .background(CanonColor.paper)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    isPickerSelected ? CanonColor.brass : (borderColor ?? CanonColor.hairlinePaper),
                    lineWidth: isPickerSelected || borderColor != nil ? 1.8 : 1
                )
        )
        .help(style.caption)
    }

    private func isAccent(_ role: TreatmentRole?) -> Bool {
        if case .accent = role { return true }
        return false
    }

    private func accentButtonLabel(for styleId: String, role: TreatmentRole?) -> String {
        if isAccent(role) { return "Accent ✓" }
        if accentSlots.count >= 2 { return "Accents full" }
        return "+ Accent"
    }

    private func cardButton(_ label: String, emphasized: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label.uppercased())
                .font(CanonType.archive(8.5, weight: .semibold))
                .kerning(0.4)
                .foregroundStyle(emphasized ? CanonColor.paper : tint)
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6).fill(emphasized ? tint : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6).stroke(emphasized ? tint : tint.opacity(0.5), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Selection logic

    private enum TreatmentRole: Equatable {
        case primary
        case accent(index: Int)
    }

    private func role(of styleId: String) -> TreatmentRole? {
        if primarySlot?.styleId == styleId { return .primary }
        if let index = accentSlots.firstIndex(where: { $0.styleId == styleId }) { return .accent(index: index) }
        return nil
    }

    private func setPrimary(_ style: StyleBrowseStyle) {
        if primarySlot?.styleId == style.id {
            primarySlot = nil
            return
        }
        accentSlots.removeAll { $0.styleId == style.id }
        let weight = primarySlot?.weight ?? 60
        primarySlot = style.treatmentSlot(weight: weight)
    }

    private func toggleAccent(_ style: StyleBrowseStyle) {
        if primarySlot?.styleId == style.id { return }
        if let index = accentSlots.firstIndex(where: { $0.styleId == style.id }) {
            accentSlots.remove(at: index)
            return
        }
        guard accentSlots.count < 2 else { return }
        accentSlots.append(style.treatmentSlot(weight: accentSlots.isEmpty ? 25 : 15))
    }

    // MARK: - Filtering

    private var filteredStyles: [StyleBrowseStyle] {
        catalog.styles.filter { style in
            if !selectedCollectionKey.isEmpty, style.collection != selectedCollectionKey {
                return false
            }
            if !selectedMoods.isEmpty, !style.moods.contains(where: { selectedMoods.contains($0) }) {
                return false
            }
            if !selectedHues.isEmpty, !selectedHues.contains(style.hueName) {
                return false
            }
            return true
        }
    }

    private var visibleCollections: [StyleBrowseCollection] {
        if selectedCollectionKey.isEmpty {
            return catalog.displayCollections
        }
        return catalog.displayCollections.filter { $0.key == selectedCollectionKey }
    }

    private var filteredCollectionCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for style in catalog.styles {
            if !selectedMoods.isEmpty, !style.moods.contains(where: { selectedMoods.contains($0) }) {
                continue
            }
            if !selectedHues.isEmpty, !selectedHues.contains(style.hueName) {
                continue
            }
            counts[style.collection, default: 0] += 1
        }
        return counts
    }

    private var moodCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for style in catalog.styles {
            for mood in style.moods {
                counts[mood, default: 0] += 1
            }
        }
        return counts
    }

    private var hueOrder: [String] {
        var counts: [String: Int] = [:]
        for style in catalog.styles {
            counts[style.hueName, default: 0] += 1
        }
        return counts.sorted { lhs, rhs in
            if lhs.value != rhs.value {
                return lhs.value > rhs.value
            }
            return lhs.key < rhs.key
        }
        .map(\.key)
    }

    private var hueHexByName: [String: String] {
        var mapping: [String: String] = [:]
        for style in catalog.styles where mapping[style.hueName] == nil {
            mapping[style.hueName] = style.hueHex
        }
        return mapping
    }

    private func toggle(_ set: inout Set<String>, _ value: String) {
        if set.contains(value) {
            set.remove(value)
        } else {
            set.insert(value)
        }
    }

    private func loadCatalog(force: Bool = false) async {
        isLoading = true
        loadError = ""
        do {
            catalog = try await StyleBrowseCatalogRuntime.shared.loadCatalog(force: force)
            loadWarning = await CatalogManifestRuntime.shared.currentWarning()
            catalogVersion = catalog.version
            isLoading = false
        } catch {
            catalog = .empty
            loadWarning = ""
            isLoading = false
            loadError = "Style catalog unavailable: \(error.localizedDescription)"
        }
    }
}
