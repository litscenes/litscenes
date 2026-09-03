import SwiftUI

/// A ready lens take offered as a reference-picker candidate. `adoptedMediaId`
/// is its frame_reference twin's mediaId when the take was already adopted into
/// the library — the twin and the take are one logical image, so they share one
/// selection token (and one roman numeral).
struct GeneratedFrameCandidate: Identifiable, Hashable {
    var lensId: String
    var lensTitle: String
    var image: ProjectLensHeroImage
    var adoptedMediaId: String?

    var id: String { image.imageId }
    var displayLabel: String {
        let label = image.label.trimmed
        return label.isEmpty ? "Generated frame" : label
    }
    var caption: String {
        [lensTitle, displayLabel].filter { !$0.isEmpty }.joined(separator: " · ")
    }
    /// Canonical selection identity: the adopted twin's mediaId when one exists,
    /// else a `take:`-prefixed token that can't collide with media ids.
    var selectionToken: String { adoptedMediaId ?? "take:\(image.imageId)" }
}

/// One confirmed pick, in selection order.
enum MediaPickerPick {
    case media(MediaItemRecord)
    case generatedFrame(GeneratedFrameCandidate)
}

/// Live reference-capacity context for the footer honesty line; nil hides it.
struct MediaPickerCapacityContext {
    var stackLabel: String
    var capacity: FrameReferenceCapacity
    /// Slots spoken for before these picks (the clip seed). Mention
    /// displacement deliberately stays a reference-well concern.
    var reservedSlots: Int
}

/// Ready takes across all lenses as picker candidates — the roster/Creations
/// idiom: dedupe by imageId, and resolve each take's adopted `frame_reference`
/// twin (by sourceMediaId, with an imagePath fallback).
func generatedFrameReferenceCandidates(
    lenses: [ProjectLens],
    items: [MediaItemRecord]
) -> [GeneratedFrameCandidate] {
    let twins = items.filter { $0.derivativeKind == MediaItemRecord.frameReferenceDerivativeKind }
    let twinBySourceId = Dictionary(
        twins.compactMap { twin in twin.sourceMediaId.map { ($0, twin.mediaId) } },
        uniquingKeysWith: { first, _ in first }
    )
    let twinByPath = Dictionary(
        twins.compactMap { twin in twin.path.trimmed.isEmpty ? nil : (twin.path, twin.mediaId) },
        uniquingKeysWith: { first, _ in first }
    )
    var seen = Set<String>()
    return lenses.flatMap { lens -> [GeneratedFrameCandidate] in
        let title = lens.body.title.trimmed
        let lensTitle = title.isEmpty ? "Scene \(String(lens.lensId.suffix(4)))" : title
        return lens.readyHeroImages.compactMap { image in
            // An adopted photo already lists as its own media item.
            guard !image.isAdoptedPhoto, seen.insert(image.imageId).inserted else { return nil }
            return GeneratedFrameCandidate(
                lensId: lens.lensId,
                lensTitle: lensTitle,
                image: image,
                adoptedMediaId: twinBySourceId[image.imageId] ?? twinByPath[image.imagePath]
            )
        }
    }
}

/// A generic plate-styled media chooser: scope chips, a filename/caption search,
/// and an ordered multi-select grid. Callers scope the candidate list — the
/// sheet never reaches into the engine (generated-frame adoption happens in the
/// caller's onConfirm). First consumer is the Frame Creator's reference well;
/// the Media overhaul reuses it anywhere library images are consumed.
struct MediaPickerSheet: View {
    let title: String
    let subtitle: String
    /// Candidate items, caller-ordered. Non-images are ignored.
    let items: [MediaItemRecord]
    /// Analysis observations by mediaId — drives hover captions and search.
    let observationsById: [String: ImageObservationResult]
    /// Media ids promoted as Story Inputs (enabled content) — powers the scope
    /// chip. Empty hides the Story Inputs scope.
    let storyInputMediaIds: Set<String>
    /// Generated frames (lens takes) offerable as picks. Empty hides the
    /// Generated Frames scope.
    let generatedFrameCandidates: [GeneratedFrameCandidate]
    /// 0 = unlimited.
    let selectionLimit: Int
    let confirmLabel: String
    /// The active stack's reference capacity, for the footer honesty line and
    /// the over-capacity numeral tint. Nil hides both.
    let capacityContext: MediaPickerCapacityContext?
    let onConfirm: ([MediaPickerPick]) -> Void
    let onCancel: () -> Void

    private enum Scope: String, CaseIterable {
        case all = "All Images"
        case storyInputs = "Story Inputs"
        case generated = "Generated Frames"
    }

    @State private var scope: Scope = .all
    @State private var search = ""
    /// Ordered selection of canonical tokens (media ids / take tokens) — order
    /// is meaningful (it becomes attachment order).
    @State private var selectedIds: [String]

    init(
        title: String,
        subtitle: String,
        items: [MediaItemRecord],
        observationsById: [String: ImageObservationResult],
        storyInputMediaIds: Set<String> = [],
        generatedFrameCandidates: [GeneratedFrameCandidate] = [],
        preselectedIds: [String] = [],
        selectionLimit: Int = 0,
        confirmLabel: String = "Attach",
        capacityContext: MediaPickerCapacityContext? = nil,
        onConfirm: @escaping ([MediaPickerPick]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.items = items
        self.observationsById = observationsById
        self.storyInputMediaIds = storyInputMediaIds
        self.generatedFrameCandidates = generatedFrameCandidates
        self.selectionLimit = selectionLimit
        self.confirmLabel = confirmLabel
        self.capacityContext = capacityContext
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        // Preselection keeps the caller's order so reopened numerals mirror the
        // reference well's attachment order.
        _selectedIds = State(initialValue: preselectedIds.filter { token in
            items.contains { $0.mediaId == token && $0.kind == .image }
                || generatedFrameCandidates.contains { $0.selectionToken == token }
        })
    }

    private var imageItems: [MediaItemRecord] {
        items.filter { $0.kind == .image }
    }

    private var availableScopes: [Scope] {
        var scopes: [Scope] = [.all]
        if !storyInputMediaIds.isEmpty { scopes.append(.storyInputs) }
        if !generatedFrameCandidates.isEmpty { scopes.append(.generated) }
        return scopes
    }

    private var visibleItems: [MediaItemRecord] {
        let scoped = scope == .storyInputs
            ? imageItems.filter { storyInputMediaIds.contains($0.mediaId) }
            : imageItems
        let query = search.trimmed
        guard !query.isEmpty else { return scoped }
        return scoped.filter { item in
            if item.filename.localizedCaseInsensitiveContains(query) { return true }
            if item.relativePath.localizedCaseInsensitiveContains(query) { return true }
            if let observation = observationsById[item.mediaId],
               observation.plainCaption.localizedCaseInsensitiveContains(query) {
                return true
            }
            return false
        }
    }

    private var visibleCandidates: [GeneratedFrameCandidate] {
        let query = search.trimmed
        guard !query.isEmpty else { return generatedFrameCandidates }
        return generatedFrameCandidates.filter { candidate in
            candidate.displayLabel.localizedCaseInsensitiveContains(query)
                || candidate.lensTitle.localizedCaseInsensitiveContains(query)
        }
    }

    /// Confirmed picks in selection order. An adopted take's token IS its twin
    /// media id, so it resolves as `.media` — adopted takes never re-adopt.
    private var selectedPicks: [MediaPickerPick] {
        selectedIds.compactMap { token in
            if let item = imageItems.first(where: { $0.mediaId == token }) {
                return .media(item)
            }
            if let candidate = generatedFrameCandidates.first(where: { $0.selectionToken == token }) {
                return .generatedFrame(candidate)
            }
            return nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(PlateColor.hairline).frame(height: 1)
            controls
            Rectangle().fill(PlateColor.hairline).frame(height: 1)
            grid
            Rectangle().fill(PlateColor.hairline).frame(height: 1)
            footer
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(PlateColor.cream)
                .shadow(color: Color.black.opacity(0.28), radius: 16, y: 8)
        )
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(PlateColor.ink.opacity(0.55), lineWidth: 1))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                PlateLabel(text: title, size: 12, weight: .semibold)
                Text(subtitle)
                    .font(PlateType.label(9.5))
                    .foregroundStyle(PlateColor.inkFaint)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button {
                onCancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PlateColor.inkFaint)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close without changing references")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var controls: some View {
        HStack(spacing: 8) {
            if availableScopes.count > 1 {
                ForEach(availableScopes, id: \.self) { candidate in
                    scopeChip(candidate)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(PlateColor.inkFaint)
                TextField("Search filename or caption", text: $search)
                    .textFieldStyle(.plain)
                    .font(PlateType.label(10))
                    .foregroundStyle(PlateColor.ink)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: 240)
            .background(RoundedRectangle(cornerRadius: 3).fill(PlateColor.creamDeep.opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(PlateColor.hairline, lineWidth: 1))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func scopeChip(_ candidate: Scope) -> some View {
        let isActive = scope == candidate
        return Button {
            scope = candidate
        } label: {
            Text(candidate.rawValue)
                .font(PlateType.label(9, weight: .semibold))
                .foregroundStyle(isActive ? PlateColor.cream : PlateColor.ink)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(isActive ? PlateColor.ink : PlateColor.creamDeep.opacity(0.7)))
                .overlay(Capsule().stroke(isActive ? PlateColor.ink : PlateColor.hairline, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(scopeHelp(candidate))
    }

    private func scopeHelp(_ candidate: Scope) -> String {
        switch candidate {
        case .all: "Every library image"
        case .storyInputs: "Only images promoted as Story Inputs"
        case .generated: "Frames rendered in this project — picking one adopts it as a library reference"
        }
    }

    private var grid: some View {
        ScrollView {
            if scope == .generated ? visibleCandidates.isEmpty : visibleItems.isEmpty {
                Text(emptyCopy)
                    .font(PlateType.label(10))
                    .foregroundStyle(PlateColor.inkFaint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
                    if scope == .generated {
                        ForEach(visibleCandidates) { candidate in
                            takeTile(candidate)
                        }
                    } else {
                        ForEach(visibleItems) { item in
                            tile(item)
                        }
                    }
                }
                .padding(12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyCopy: String {
        if !search.trimmed.isEmpty { return "No images match “\(search.trimmed)”." }
        if scope == .storyInputs { return "No Story Inputs yet — promote images in the Library first." }
        if scope == .generated { return "No generated frames yet — render frames on the FRAMES board first." }
        return "No library images yet — add media in the Library first."
    }

    private func tile(_ item: MediaItemRecord) -> some View {
        let selectionIndex = selectedIds.firstIndex(of: item.mediaId)
        let isSelected = selectionIndex != nil
        let atLimit = selectionLimit > 0 && selectedIds.count >= selectionLimit && !isSelected
        return Button {
            toggle(token: item.mediaId)
        } label: {
            ZStack(alignment: .topTrailing) {
                mediaItemThumbnail(item, side: 88)
                    .opacity(atLimit ? 0.45 : 1)
                if let selectionIndex {
                    selectionBadge(index: selectionIndex)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? PlateColor.ink : PlateColor.hairline, lineWidth: isSelected ? 1.8 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(atLimit)
        .help(tileHelp(item, atLimit: atLimit))
    }

    private func takeTile(_ candidate: GeneratedFrameCandidate) -> some View {
        let selectionIndex = selectedIds.firstIndex(of: candidate.selectionToken)
        let isSelected = selectionIndex != nil
        let atLimit = selectionLimit > 0 && selectedIds.count >= selectionLimit && !isSelected
        return Button {
            toggle(token: candidate.selectionToken)
        } label: {
            ZStack(alignment: .topTrailing) {
                takeThumbnail(candidate)
                    .opacity(atLimit ? 0.45 : 1)
                if let selectionIndex {
                    selectionBadge(index: selectionIndex)
                }
            }
            .overlay(alignment: .bottomLeading) {
                Text("TAKE")
                    .font(PlateType.label(6.5, weight: .bold))
                    .kerning(0.5)
                    .foregroundStyle(PlateColor.cream)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(RoundedRectangle(cornerRadius: 2).fill(PlateColor.ink.opacity(0.72)))
                    .padding(4)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? PlateColor.ink : PlateColor.hairline, lineWidth: isSelected ? 1.8 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(atLimit)
        .help(atLimit ? "Selection limit reached — deselect an image first." : candidate.caption)
    }

    /// A take's thumbnail straight from its full-res imagePath (takes have no
    /// thumbnail derivative — the roster tray renders the same way).
    private func takeThumbnail(_ candidate: GeneratedFrameCandidate) -> some View {
        Color.clear
            .overlay(
                Group {
                    if let nsImage = NSImage(contentsOfFile: candidate.image.imagePath) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        CanonColor.paperInset
                    }
                }
            )
            .frame(width: 88, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func selectionBadge(index: Int) -> some View {
        Text(FrameCreatorModal.romanNumeral(index + 1))
            .font(PlateType.figure(9, weight: .semibold))
            .foregroundStyle(PlateColor.cream)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 2).fill(isOverCapacity(index: index) ? CanonColor.rust : PlateColor.ink))
            .padding(4)
    }

    /// Whether the pick at `index` falls beyond what the active stack can carry
    /// (selection stays allowed — the tint and footer carry the honesty).
    private func isOverCapacity(index: Int) -> Bool {
        guard let capacityContext else { return false }
        return index >= max(0, capacityContext.capacity.planningCap - capacityContext.reservedSlots)
    }

    private func tileHelp(_ item: MediaItemRecord, atLimit: Bool) -> String {
        if atLimit { return "Selection limit reached — deselect an image first." }
        if let observation = observationsById[item.mediaId], !observation.plainCaption.trimmed.isEmpty {
            return "\(item.filename) — \(observation.plainCaption)"
        }
        return item.filename
    }

    private func toggle(token: String) {
        if let index = selectedIds.firstIndex(of: token) {
            selectedIds.remove(at: index)
        } else if selectionLimit <= 0 || selectedIds.count < selectionLimit {
            selectedIds.append(token)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectionSummary)
                    .font(PlateType.figure(9.5, weight: .medium))
                    .foregroundStyle(PlateColor.inkFaint)
                if let line = capacityLine {
                    Text(line.text)
                        .font(PlateType.figure(9.5))
                        .foregroundStyle(line.isWarning ? CanonColor.rust : PlateColor.inkFaint)
                }
            }
            Spacer(minLength: 0)
            Button("Cancel") {
                onCancel()
            }
            .buttonStyle(PlateButtonStyle())
            Button(selectedIds.isEmpty ? confirmLabel : "\(confirmLabel) \(selectedIds.count)") {
                onConfirm(selectedPicks)
            }
            .buttonStyle(PlateButtonStyle(isProminent: true))
            .help("Apply the current selection")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var selectionSummary: String {
        if selectionLimit > 0 {
            return "\(selectedIds.count) / \(selectionLimit) selected"
        }
        return "\(selectedIds.count) selected"
    }

    /// The active stack's capacity as one footer line, rust once the current
    /// selection outruns what would ride.
    private var capacityLine: (text: String, isWarning: Bool)? {
        guard let context = capacityContext else { return nil }
        let budget = FrameReferenceCapacity.attachmentBudget
        let over = selectedIds.count > max(0, context.capacity.planningCap - context.reservedSlots)
        switch context.capacity {
        case .textOnly:
            return ("\(context.stackLabel) renders from text only — picked images won't attach to the render.", true)
        case .slots:
            let cap = context.capacity.planningCap
            if cap == 1 {
                if context.reservedSlots > 0 {
                    return ("\(context.stackLabel) attaches one image — the clip seed holds the slot, so these picks won't ride.", true)
                }
                return ("\(context.stackLabel) attaches one image — the first pick rides.", over)
            }
            let reservedNote = context.reservedSlots > 0 ? " — the clip seed holds one" : ""
            if cap == budget {
                // The model's ceiling meets or exceeds the app's shared
                // budget — attribute the cap to the budget, like `.budget`.
                return ("\(context.stackLabel) attaches up to \(budget) images\(reservedNote).", over)
            }
            let remaining = max(0, cap - context.reservedSlots)
            return ("\(context.stackLabel) attaches up to \(cap) images\(reservedNote) — the first \(remaining) picks ride.", over)
        case .compositeSheet:
            return ("\(context.stackLabel) combines picks into one labeled sheet (up to \(budget)).", over)
        case .budget:
            let reservedNote = context.reservedSlots > 0 ? " — the clip seed holds one" : ""
            return ("\(context.stackLabel) attaches up to \(budget) images\(reservedNote).", over)
        }
    }
}
