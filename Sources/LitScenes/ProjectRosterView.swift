import SwiftUI
import UniformTypeIdentifiers

/// Which roster the project roster sheet opens on.
enum RosterKind: String, CaseIterable, Identifiable {
    case characters = "Characters"
    case objects = "Objects"

    var id: String { rawValue }
}

/// A request to open the roster sheet, optionally focused on one entry — the sheet is
/// reached through a character/object card, so it opens as that entry's detail view.
struct RosterDetailRequest: Identifiable {
    let kind: RosterKind
    var entryId: String? = nil

    var id: String { "\(kind.rawValue):\(entryId ?? "")" }
}

/// Project character/object roster, master-detail: a list rail of entries, a detail
/// pane where the selected entry's name and description stay editable and its ordered
/// reference images are organized, and a media tray of sources. For characters the
/// leading two references are first-class "render slots" — exactly those two attach at
/// generation, keyed by the entry's name — and the rest shelve below, drag-promotable.
/// Object references are organizational only (no render attachment path yet).
struct ProjectRosterView: View {
    @ObservedObject var library: LibraryEngine

    @Environment(\.dismiss) private var dismiss

    @State private var kind: RosterKind
    @State private var selectedCharacterId: String?
    @State private var selectedObjectId: String?
    @State private var nameDraft = ""
    @State private var descriptionDraft = ""
    @State private var isCreateDraftActive = false
    @State private var createDraftName = ""
    @State private var statusMessage = ""
    @State private var pendingDelete: RosterEntry?
    @State private var trayTab: TrayTab = .moodboard
    @State private var imagePreview: StyleImagePreviewRequest?
    @State private var generatePromptDraft = ""
    @State private var generateShot: RosterCharacterRenderPrompt.Shot = .fullFigure
    @State private var generateStackId: String?
    @State private var generateRefineInput = ""
    @State private var isRefiningGeneratePrompt = false
    @FocusState private var focus: FocusTarget?

    init(library: LibraryEngine, initialKind: RosterKind = .characters, initialSelectedEntryId: String? = nil) {
        self.library = library
        _kind = State(initialValue: initialKind)
        switch initialKind {
        case .characters:
            _selectedCharacterId = State(initialValue: initialSelectedEntryId)
        case .objects:
            _selectedObjectId = State(initialValue: initialSelectedEntryId)
        }
    }

    private enum FocusTarget: Hashable {
        case createName
        case entryName
        case entryDescription
    }

    private enum TrayTab: String, CaseIterable, Identifiable {
        case moodboard = "MEDIA"
        case generated = "GENERATED FRAMES"

        var id: String { rawValue }
    }

    /// One roster row regardless of kind; actions route back through the kind switch.
    private struct RosterEntry: Identifiable {
        let id: String
        let name: String
        let descriptionPrompt: String
        let referenceMediaIds: [String]
        let referenceLabels: [String: String]
    }

    private var entries: [RosterEntry] {
        switch kind {
        case .characters:
            return library.projectCharacters.characters.map {
                RosterEntry(id: $0.characterId, name: $0.name, descriptionPrompt: $0.descriptionPrompt, referenceMediaIds: $0.referenceMediaIds, referenceLabels: $0.referenceLabels)
            }
        case .objects:
            return library.projectObjects.objects.map {
                RosterEntry(id: $0.objectId, name: $0.name, descriptionPrompt: $0.descriptionPrompt, referenceMediaIds: $0.referenceMediaIds, referenceLabels: $0.referenceLabels)
            }
        }
    }

    private var entryIds: [String] { entries.map(\.id) }

    /// Tray candidates: curated moodboard images only.
    private var mediaCandidates: [MediaItemRecord] {
        library.enabledContentItems.filter { $0.kind == .image }
    }

    /// Reference-resolution candidates: the full image inventory, so references archived
    /// rejected-by-default (adopted generated frames) still render in slots and shelves.
    private var bucketCandidates: [MediaItemRecord] {
        library.items.filter { $0.kind == .image }
    }

    private var generatedFrames: [ProjectLensHeroImage] {
        var seen = Set<String>()
        return library.projectLenses.lenses.flatMap(\.readyHeroImages).filter { seen.insert($0.imageId).inserted }
    }

    private func selectedId(for kind: RosterKind) -> String? {
        kind == .characters ? selectedCharacterId : selectedObjectId
    }

    private var selectedEntryId: String? { selectedId(for: kind) }

    private func setSelectedEntryId(_ id: String?) {
        switch kind {
        case .characters: selectedCharacterId = id
        case .objects: selectedObjectId = id
        }
    }

    private var selectedEntry: RosterEntry? {
        guard let selectedEntryId else { return nil }
        return entries.first { $0.id == selectedEntryId }
    }

    private func entry(withId id: String, kind: RosterKind) -> RosterEntry? {
        switch kind {
        case .characters:
            return library.projectCharacters.character(withId: id).map {
                RosterEntry(id: $0.characterId, name: $0.name, descriptionPrompt: $0.descriptionPrompt, referenceMediaIds: $0.referenceMediaIds, referenceLabels: $0.referenceLabels)
            }
        case .objects:
            return library.projectObjects.object(withId: id).map {
                RosterEntry(id: $0.objectId, name: $0.name, descriptionPrompt: $0.descriptionPrompt, referenceMediaIds: $0.referenceMediaIds, referenceLabels: $0.referenceLabels)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(CanonColor.hairlinePaper).frame(height: 1)
            HStack(alignment: .top, spacing: 0) {
                rosterListColumn
                    .frame(width: 264)
                    .frame(maxHeight: .infinity)
                Rectangle().fill(CanonColor.hairlinePaper).frame(width: 1)
                detailPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Rectangle().fill(CanonColor.hairlinePaper).frame(width: 1)
                mediaTray
                    .frame(width: 296)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(minWidth: 940, minHeight: 620)
        .background(CanonColor.paper)
        .environment(\.colorScheme, .light)
        .foregroundStyle(CanonColor.ink)
        .onAppear {
            reconcileSelection()
            loadDrafts()
        }
        .onDisappear {
            commitPendingEdits(for: kind)
        }
        .onChange(of: kind) { oldKind, _ in
            commitPendingEdits(for: oldKind)
            statusMessage = ""
            isCreateDraftActive = false
            createDraftName = ""
            reconcileSelection()
            loadDrafts()
        }
        .onChange(of: entryIds) { _, _ in
            reconcileSelection()
        }
        .onChange(of: focus) { oldFocus, newFocus in
            handleFocusChange(from: oldFocus, to: newFocus)
        }
        .onChange(of: selectedEntry?.name) { _, newValue in
            if focus != .entryName, let newValue {
                nameDraft = newValue
            }
        }
        .onChange(of: selectedEntry?.descriptionPrompt) { _, newValue in
            if focus != .entryDescription, let newValue {
                descriptionDraft = newValue
            }
        }
        .onDeleteCommand {
            if focus == nil, let entry = selectedEntry {
                pendingDelete = entry
            }
        }
        .confirmationDialog(
            Text("Delete \(pendingDelete?.name ?? "")?"),
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { entry in
            Button("Delete \(entry.name)", role: .destructive) { performDelete(entry) }
            Button("Cancel", role: .cancel) {}
        } message: { entry in
            Text(deleteMessage(for: entry))
        }
        .sheet(item: $imagePreview) { request in
            StyleImagePreviewModal(request: request)
        }
    }

    /// Click-to-enlarge for slot, shelf, and composite-sheet thumbnails.
    private func enlarge(_ item: MediaItemRecord, label: String) {
        imagePreview = StyleImagePreviewRequest(
            url: URL(fileURLWithPath: item.path).absoluteString,
            label: label.isEmpty ? item.filename : label,
            detail: item.isRosterCompositeSheet ? "Composite reference sheet" : item.filename
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Picker("", selection: $kind) {
                ForEach(RosterKind.allCases) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)
            Text(entries.isEmpty ? "" : "\(entries.count) defined")
                .font(CanonType.archive(11))
                .foregroundStyle(CanonColor.muted)
            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(CanonType.interface(11))
                    .foregroundStyle(CanonColor.brass)
                    .lineLimit(1)
            }
            Spacer()
            Button("Done") {
                commitPendingEdits(for: kind)
                dismiss()
            }
            .buttonStyle(.plain)
            .font(CanonType.interface(12, weight: .semibold))
            .foregroundStyle(CanonColor.brass)
        }
        .padding(.horizontal, 20)
        .frame(height: 52)
    }

    // MARK: - List rail

    private var rosterListColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            newEntryAffordance
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(entries) { entry in
                        RosterListRow(
                            entry: entry,
                            kind: kind,
                            isSelected: entry.id == selectedEntryId,
                            candidates: bucketCandidates,
                            onSelect: { select(entry.id) },
                            onRenameRequest: {
                                select(entry.id)
                                DispatchQueue.main.async { focus = .entryName }
                            },
                            onDeleteRequest: { pendingDelete = entry },
                            onDropMediaIds: { ids in
                                appendReferences(entry, mediaIds: ids)
                                select(entry.id)
                            }
                        )
                    }
                    if entries.isEmpty {
                        Text(kind == .characters
                            ? "No characters yet — create one above."
                            : "No objects yet — create one above.")
                            .font(CanonType.interface(11))
                            .foregroundStyle(CanonColor.muted)
                            .padding(.horizontal, 6)
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .background(CanonColor.paperInset.opacity(0.35))
    }

    @ViewBuilder
    private var newEntryAffordance: some View {
        if isCreateDraftActive {
            TextField(kind == .characters ? "Character name — Return creates" : "Object name — Return creates", text: $createDraftName)
                .textFieldStyle(.roundedBorder)
                .font(CanonType.interface(12.5))
                .focused($focus, equals: .createName)
                .onSubmit(createEntry)
                .onExitCommand {
                    isCreateDraftActive = false
                    createDraftName = ""
                    focus = nil
                }
        } else {
            Button {
                isCreateDraftActive = true
                DispatchQueue.main.async { focus = .createName }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                    Text(kind == .characters ? "New character" : "New object")
                        .font(CanonType.interface(12, weight: .semibold))
                }
                .foregroundStyle(CanonColor.brass)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private struct RosterListRow: View {
        let entry: RosterEntry
        let kind: RosterKind
        let isSelected: Bool
        let candidates: [MediaItemRecord]
        var onSelect: () -> Void
        var onRenameRequest: () -> Void
        var onDeleteRequest: () -> Void
        var onDropMediaIds: ([String]) -> Void

        @State private var isDropTargeted = false
        @State private var isHovered = false

        var body: some View {
            Button(action: onSelect) {
                HStack(spacing: 10) {
                    rosterBucketThumbnail(name: entry.name, referenceMediaIds: entry.referenceMediaIds, candidates: candidates, side: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name)
                            .font(CanonType.editorial(13.5, weight: .semibold))
                            .foregroundStyle(CanonColor.ink)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(microLabel.text)
                            .font(CanonType.archive(9, weight: .semibold))
                            .kerning(1.1)
                            .foregroundStyle(microLabel.color)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .frame(height: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(rowFill, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isDropTargeted ? CanonColor.brass : (isSelected ? CanonColor.brass.opacity(0.7) : Color.clear),
                        style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1.5, dash: isDropTargeted ? [5, 4] : [])
                    )
            )
            .contextMenu {
                Button("Rename", action: onRenameRequest)
                Button("Delete…", role: .destructive, action: onDeleteRequest)
            }
            .onHover { isHovered = $0 }
            .dropDestination(for: MediaIDTransfer.self) { payloads, _ in
                let ids = payloads.map(\.mediaId)
                guard !ids.isEmpty else { return false }
                onDropMediaIds(ids)
                return true
            } isTargeted: { isDropTargeted = $0 }
        }

        private var rowFill: Color {
            if isDropTargeted { return CanonColor.softGold.opacity(0.16) }
            if isSelected { return CanonColor.paperInset.opacity(0.85) }
            if isHovered { return CanonColor.paperInset.opacity(0.5) }
            return Color.clear
        }

        private var microLabel: (text: String, color: Color) {
            let count = entry.referenceMediaIds.count
            switch kind {
            case .characters:
                if count == 0 { return ("NO REFS", CanonColor.rust.opacity(0.85)) }
                return ("\(count) REF\(count == 1 ? "" : "S")", CanonColor.muted)
            case .objects:
                if count == 0 { return ("NO IMAGES", CanonColor.muted) }
                return ("\(count) IMAGE\(count == 1 ? "" : "S")", CanonColor.muted)
            }
        }
    }

    // MARK: - Detail pane

    @ViewBuilder
    private var detailPane: some View {
        if entries.isEmpty {
            noEntriesState
        } else if let entry = selectedEntry {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    detailHeader(entry)
                    descriptionEditor(entry)
                    if kind == .characters,
                       let castMember = library.goalCastMember(forCharacterId: entry.id, name: entry.name) {
                        castIdentitySection(castMember)
                    }
                    if kind == .characters {
                        characterGenerateSection(entry)
                    }
                    if entry.referenceMediaIds.isEmpty {
                        EmptyReferenceWell(
                            kind: kind,
                            onUpload: { uploadReferences(entry) },
                            onDrop: { appendReferences(entry, mediaIds: $0) },
                            onGenerate: kind == .characters ? { seedGeneratePrompt() } : nil
                        )
                    } else {
                        if kind == .characters {
                            characterSlotsSection(entry)
                        }
                        referenceShelfSection(entry)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Color.clear
        }
    }

    private var noEntriesState: some View {
        VStack(spacing: 10) {
            Image(systemName: kind == .characters ? "person.2.badge.plus" : "shippingbox")
                .font(.system(size: 24))
                .foregroundStyle(CanonColor.muted)
            Text(kind == .characters
                ? "Define the recurring people of this project."
                : "Define the recurring objects of this project.")
                .font(CanonType.editorial(15))
                .foregroundStyle(CanonColor.ink.opacity(0.8))
            Text(kind == .characters
                ? "Create a character, add reference images, and every scene that casts them attaches the two slot images automatically."
                : "Create an object and keep its reference images organized with it.")
                .font(CanonType.interface(11.5))
                .foregroundStyle(CanonColor.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button {
                isCreateDraftActive = true
                DispatchQueue.main.async { focus = .createName }
            } label: {
                Text(kind == .characters ? "+ New character" : "+ New object")
            }
            .buttonStyle(CanonPrimaryButtonStyle())
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func detailHeader(_ entry: RosterEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                TextField(kind == .characters ? "Character name" : "Object name", text: $nameDraft)
                    .textFieldStyle(.plain)
                    .font(CanonType.editorial(19, weight: .semibold))
                    .foregroundStyle(CanonColor.ink)
                    .focused($focus, equals: .entryName)
                    .onSubmit { commitName(kind: kind, entryId: entry.id) }
                Rectangle()
                    .fill(focus == .entryName ? CanonColor.brass : CanonColor.hairlinePaper.opacity(0.8))
                    .frame(height: focus == .entryName ? 1.5 : 1)
            }
            Spacer()
            Text(referenceCountLabel(entry))
                .font(CanonType.archive(9.5))
                .foregroundStyle(CanonColor.muted)
            Button {
                pendingDelete = entry
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(CanonUtilityButtonStyle())
            .help(kind == .characters
                ? "Delete \(entry.name) — scenes casting them keep the name but lose the roster link"
                : "Delete \(entry.name)")
        }
    }

    private func referenceCountLabel(_ entry: RosterEntry) -> String {
        let count = entry.referenceMediaIds.count
        switch kind {
        case .characters: return "\(count) REFERENCE\(count == 1 ? "" : "S")"
        case .objects: return "\(count) IMAGE\(count == 1 ? "" : "S")"
        }
    }

    private func descriptionEditor(_ entry: RosterEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DESCRIPTION")
                .font(CanonType.archive(8.5, weight: .semibold))
                .kerning(1.4)
                .foregroundStyle(CanonColor.muted)
            ZStack(alignment: .topLeading) {
                TextEditor(text: $descriptionDraft)
                    .font(CanonType.interface(12.5))
                    .foregroundColor(CanonColor.ink)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 56, maxHeight: 110)
                    .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(focus == .entryDescription ? CanonColor.brass.opacity(0.7) : CanonColor.hairlinePaper)
                    )
                    .focused($focus, equals: .entryDescription)
                if descriptionDraft.isEmpty {
                    Text(kind == .characters
                        ? "Visual description — build, dress, bearing"
                        : "Visual description — material, shape, wear")
                        .font(CanonType.interface(12.5))
                        .foregroundStyle(CanonColor.muted.opacity(0.8))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    /// Read-only STORY IDENTITY mirror of the GOAL-stage cast member linked to this
    /// character (by characterId, else case-insensitive name). Steering lives in the
    /// GOAL rail; the roster only reflects the active take.
    private func castIdentitySection(_ member: GoalCastMember) -> some View {
        let identity = member.activeIdentity
        let pinned = member.pinnedDimensionSet
        let rows: [(label: String, dimension: GoalCastDimension, value: String)] = [
            ("FUNCTION", .publicFunction, identity.publicFunction),
            ("WANTS", .desire, identity.desire),
            ("RULE", .operatingRule, identity.operatingRule),
            ("COST", .cost, identity.cost),
            ("TELL", .signature, identity.signature)
        ]
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("STORY IDENTITY")
                    .font(CanonType.archive(8.5, weight: .semibold))
                    .kerning(1.4)
                    .foregroundStyle(CanonColor.muted)
                Text(String(format: "STRANGENESS %.2f", identity.strangeness))
                    .font(CanonType.archive(8.5))
                    .kerning(1.1)
                    .foregroundStyle(CanonColor.brass)
                Spacer()
                Text("STEER THIS IN GOAL")
                    .font(CanonType.archive(8))
                    .kerning(1.2)
                    .foregroundStyle(CanonColor.muted.opacity(0.8))
            }
            VStack(alignment: .leading, spacing: 5) {
                if !identity.essence.isEmpty {
                    Text(identity.essence)
                        .font(CanonType.editorial(12).italic())
                        .foregroundStyle(CanonColor.ink.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(rows.filter { !$0.value.isEmpty }, id: \.label) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        HStack(spacing: 3) {
                            Text(row.label)
                                .font(CanonType.archive(8.5, weight: .semibold))
                                .kerning(1.3)
                                .foregroundStyle(pinned.contains(row.dimension) ? CanonColor.brass : CanonColor.muted)
                            if pinned.contains(row.dimension) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 7))
                                    .foregroundStyle(CanonColor.brass)
                            }
                        }
                        .frame(width: 74, alignment: .leading)
                        Text(row.value)
                            .font(CanonType.interface(11.5))
                            .foregroundStyle(CanonColor.ink.opacity(0.86))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(CanonColor.hairlinePaper)
            )
        }
    }

    // MARK: - Generate (characters)

    private var hasOpenAICredential: Bool {
        library.videoProviderCredentialStatuses.first { $0.provider == .openAI }?.isConfigured == true
    }

    private var hasCivitaiCredential: Bool {
        library.videoProviderCredentialStatuses.first { $0.provider == .civitai }?.isConfigured == true
    }

    private var hasFALCredential: Bool {
        library.videoProviderCredentialStatuses.first { $0.provider == .fal }?.isConfigured == true
    }

    private var hasStabilityCredential: Bool {
        library.videoProviderCredentialStatuses.first { $0.provider == .stability }?.isConfigured == true
    }

    private func generateCredentialBlocker(for stack: RenderStack) -> String? {
        switch stack.credentialProvider {
        case .openAI:
            return hasOpenAICredential ? nil : "Add an OpenAI API key in App Settings."
        case .civitai:
            return hasCivitaiCredential ? nil : "Add a CivitAI API key in App Settings."
        case .fal:
            if !hasFALCredential { return "Add a FAL API key in App Settings." }
            if !hasOpenAICredential { return "Add an OpenAI API key for prompt writing." }
            return nil
        case .stability:
            if !hasStabilityCredential { return "Add a Stability AI API key in App Settings." }
            if !hasOpenAICredential { return "Add an OpenAI API key for prompt writing." }
            return nil
        default:
            return "\(stack.credentialProvider.label) key gating is not supported for render stacks."
        }
    }

    private var selectedGenerateStack: RenderStack? {
        let stacks = RenderStackRegistry.shared.stacks()
        if let generateStackId,
           let stack = stacks.first(where: { $0.id == generateStackId }),
           generateCredentialBlocker(for: stack) == nil {
            return stack
        }
        return RenderStackRegistry.shared.defaultStack(
            hasOpenAI: hasOpenAICredential,
            hasCivitai: hasCivitaiCredential,
            hasFAL: hasFALCredential,
            hasStability: hasStabilityCredential
        )
    }

    /// `isWarning` renders the note in rust: the selected stack is about to
    /// silently DROP the character's existing reference images — the exact
    /// setup that produced an off-identity render before this note existed.
    private func generateAnchorNote(_ entry: RosterEntry) -> (text: String, isWarning: Bool) {
        guard let stack = selectedGenerateStack else {
            return ("Add an API key in App Settings to enable rendering.", false)
        }
        guard stack.reframeCapable else {
            if entry.referenceMediaIds.isEmpty {
                return ("\(stack.label) renders from text only — the prompt carries the identity.", false)
            }
            let count = entry.referenceMediaIds.count
            return (
                "\(stack.label) cannot attach reference images — \(entry.name)'s \(count) ref\(count == 1 ? "" : "s") will NOT ride this render; likeness comes from the prompt alone.",
                true
            )
        }
        let referenced = entry.referenceMediaIds.compactMap { mediaId in
            library.items.first { $0.mediaId == mediaId }
        }
        let picks = RosterCharacterRenderPrompt.identityAnchorPicks(
            referenced: referenced,
            referenceLabels: entry.referenceLabels,
            capOne: stack.isFAL
        )
        if picks.isEmpty {
            return ("No references yet — renders from the prompt alone; promote the result and the next render anchors on it.", false)
        }
        if picks.first?.isSheet == true {
            return ("Anchors identity on the reference sheet.", false)
        }
        if stack.isFAL, entry.referenceMediaIds.count > 1 {
            return ("\(stack.label) attaches one image — anchoring on slot 1.", false)
        }
        if stack.isStability, picks.count > 1 {
            return ("\(stack.label) combines all \(picks.count) identity references into one labeled sheet.", false)
        }
        return ("Anchors identity on \(picks.count) reference\(picks.count == 1 ? "" : "s").", false)
    }

    private func characterGenerateSection(_ entry: RosterEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("GENERATE — RENDER A NEW REFERENCE")
                    .font(CanonType.archive(8.5, weight: .semibold))
                    .kerning(1.4)
                    .foregroundStyle(CanonColor.muted)
                Spacer()
                ForEach(RosterCharacterRenderPrompt.Shot.allCases) { shot in
                    generateShotChip(shot)
                }
                Button {
                    seedGeneratePrompt()
                } label: {
                    Label("Re-seed", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(CanonUtilityButtonStyle())
                .help("Recompose the prompt from the name, description, and shot")
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: $generatePromptDraft)
                    .font(CanonType.interface(12.5))
                    .foregroundColor(CanonColor.ink)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 90, maxHeight: 150)
                    .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlinePaper))
                if generatePromptDraft.isEmpty {
                    Text("Describe the reference to render — Re-seed composes one from the description")
                        .font(CanonType.interface(12.5))
                        .foregroundStyle(CanonColor.muted.opacity(0.8))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
            }
            HStack(spacing: 6) {
                TextField("Same sentiment, but… (refine the prompt)", text: $generateRefineInput)
                    .textFieldStyle(.plain)
                    .font(CanonType.interface(11.5))
                    .foregroundStyle(CanonColor.ink)
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .background(Color.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(CanonColor.hairlinePaper))
                    .onSubmit(sendGenerateRefine)
                    .disabled(isRefiningGeneratePrompt)
                if isRefiningGeneratePrompt {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 26, height: 26)
                } else {
                    Button(action: sendGenerateRefine) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(CanonColor.paper)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(CanonColor.ink.opacity(0.85)))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(generateRefineInput.trimmed.isEmpty || generatePromptDraft.trimmed.isEmpty)
                    .help("Rewrite the prompt per this direction, preserving its sentiment")
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(RenderStackRegistry.shared.stacks()) { stack in
                        generateStackChip(stack)
                    }
                }
            }
            HStack(alignment: .center, spacing: 10) {
                Button {
                    guard let stack = selectedGenerateStack else { return }
                    let prompt = generatePromptDraft
                    let shot = generateShot
                    let characterId = entry.id
                    Task { @MainActor in
                        _ = await library.startCharacterReferenceRender(
                            characterId: characterId,
                            prompt: prompt,
                            shot: shot,
                            stack: stack
                        )
                        statusMessage = library.aestheticStatus
                    }
                } label: {
                    Label(library.isGeneratingCharacterRender ? "Rendering…" : "Generate", systemImage: "sparkles")
                }
                .buttonStyle(CanonPrimaryButtonStyle())
                .disabled(
                    library.isGeneratingCharacterRender
                        || generatePromptDraft.trimmed.isEmpty
                        || selectedGenerateStack == nil
                )
                .help("Render a new \(entry.name) reference — it lands in the pool below")
                if library.isGeneratingCharacterRender {
                    ProgressView()
                        .controlSize(.small)
                }
                let anchorNote = generateAnchorNote(entry)
                Text(anchorNote.text)
                    .font(CanonType.interface(10.5))
                    .foregroundStyle(anchorNote.isWarning ? CanonColor.rust.opacity(0.9) : CanonColor.muted)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
        }
    }

    private func generateShotChip(_ shot: RosterCharacterRenderPrompt.Shot) -> some View {
        let isActive = generateShot == shot
        return Button {
            generateShot = shot
            seedGeneratePrompt()
        } label: {
            Text(shot.label)
                .font(CanonType.archive(8, weight: isActive ? .semibold : .regular))
                .kerning(0.7)
                .foregroundStyle(isActive ? CanonColor.paper : CanonColor.ink.opacity(0.6))
                .padding(.horizontal, 8)
                .frame(height: 20)
                .background(Capsule().fill(isActive ? CanonColor.ink.opacity(0.85) : Color.white.opacity(0.5)))
                .overlay(Capsule().stroke(isActive ? CanonColor.ink.opacity(0.85) : CanonColor.hairlinePaper))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Seed a \(shot.label.lowercased()) prompt")
    }

    private func generateStackChip(_ stack: RenderStack) -> some View {
        let blocker = generateCredentialBlocker(for: stack)
        let isActive = selectedGenerateStack?.id == stack.id
        return Button {
            generateStackId = stack.id
        } label: {
            HStack(spacing: 4) {
                if blocker != nil {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 7, weight: .semibold))
                }
                Text(stack.label)
                    .font(CanonType.interface(10, weight: isActive ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(blocker != nil ? CanonColor.muted.opacity(0.7) : (isActive ? CanonColor.ink : CanonColor.ink.opacity(0.6)))
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 6).fill(isActive ? Color.white.opacity(0.75) : Color.white.opacity(0.35)))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isActive ? CanonColor.brass.opacity(0.6) : CanonColor.hairlinePaper, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(blocker != nil)
        .help(blocker ?? (stack.reframeCapable
            ? "\(stack.label) — can anchor identity on reference images"
            : "\(stack.label) — renders from text only"))
    }

    private func sendGenerateRefine() {
        let directive = generateRefineInput.trimmed
        guard !directive.isEmpty, !isRefiningGeneratePrompt, !generatePromptDraft.trimmed.isEmpty else { return }
        let current = generatePromptDraft
        generateRefineInput = ""
        isRefiningGeneratePrompt = true
        Task { @MainActor in
            let result = await library.transformFormPrompt(prompt: current, directive: directive, priorDirectives: [])
            isRefiningGeneratePrompt = false
            guard let result else {
                statusMessage = "Refine failed — check the OpenAI key and try again."
                generateRefineInput = directive
                return
            }
            generatePromptDraft = result.prompt
        }
    }

    private func characterSlotsSection(_ entry: RosterEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ATTACHES AT RENDER")
                .font(CanonType.archive(8.5, weight: .semibold))
                .kerning(1.4)
                .foregroundStyle(CanonColor.muted)
            HStack(alignment: .top, spacing: 10) {
                ForEach(0..<2, id: \.self) { slotIndex in
                    let mediaId = slotIndex < entry.referenceMediaIds.count ? entry.referenceMediaIds[slotIndex] : nil
                    RenderSlotCell(
                        slotIndex: slotIndex,
                        mediaId: mediaId,
                        item: mediaId.flatMap { id in bucketCandidates.first { $0.mediaId == id } },
                        label: mediaId.flatMap { entry.referenceLabels[$0] } ?? "",
                        onPlace: { placeReference(entry, mediaId: $0, at: slotIndex) },
                        onRemove: { removeReference(entry, mediaId: $0) },
                        onLabelCommit: { label in
                            if let mediaId {
                                setReferenceLabel(entry, mediaId: mediaId, label: label)
                            }
                        },
                        onEnlarge: {
                            if let mediaId, let item = bucketCandidates.first(where: { $0.mediaId == mediaId }) {
                                enlarge(item, label: entry.referenceLabels[mediaId] ?? "")
                            }
                        }
                    )
                }
                Text("When \(entry.name)'s studies render — or you @mention them in the Frame Creator — these two images attach to the prompt; labels ride along (\"young \(entry.name)\"). Slot 1 is strongest.")
                    .font(CanonType.interface(10.5))
                    .foregroundStyle(CanonColor.muted)
                    .frame(maxWidth: 220, alignment: .leading)
                    .padding(.top, 2)
            }
        }
    }

    private func referenceShelfSection(_ entry: RosterEntry) -> some View {
        let startIndex = kind == .characters ? min(2, entry.referenceMediaIds.count) : 0
        let shelfIds = Array(entry.referenceMediaIds.dropFirst(startIndex))
        let hasSheet = library.rosterCompositeSheetItem(referenceMediaIds: entry.referenceMediaIds) != nil
        let sheetSourceCount = library.rosterCompositeSheetSourceCount(referenceMediaIds: entry.referenceMediaIds)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(kind == .characters
                    ? "ALSO SAVED — DRAG INTO A SLOT TO PROMOTE"
                    : "REFERENCE IMAGES — ORDER IS SAVED")
                    .font(CanonType.archive(8.5, weight: .semibold))
                    .kerning(1.4)
                    .foregroundStyle(CanonColor.muted)
                Spacer()
                Button {
                    buildCompositeSheet(entry)
                } label: {
                    Label(hasSheet ? "Rebuild sheet" : "Composite sheet", systemImage: "square.grid.2x2")
                }
                .buttonStyle(CanonUtilityButtonStyle())
                .disabled(sheetSourceCount < 2)
                .help(sheetSourceCount < 2
                    ? "Add at least 2 reference images to build a labeled contact sheet"
                    : "Compose up to 4 references into one labeled sheet — one attachment that carries several views. Rebuilds automatically when references or labels change.")
                Button {
                    uploadReferences(entry)
                } label: {
                    Label("Upload files…", systemImage: "photo.badge.plus")
                }
                .buttonStyle(CanonUtilityButtonStyle())
                .help("Upload image files as \(entry.name) references")
            }
            if kind == .objects {
                Text("Kept with this object for organization. Object references attach at render only when you @mention the object in the Frame Creator.")
                    .font(CanonType.interface(10.5))
                    .foregroundStyle(CanonColor.muted)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 66), spacing: 6, alignment: .top)], alignment: .leading, spacing: 6) {
                ForEach(Array(shelfIds.enumerated()), id: \.element) { offsetIndex, mediaId in
                    ReferenceShelfTile(
                        mediaId: mediaId,
                        item: bucketCandidates.first { $0.mediaId == mediaId },
                        label: entry.referenceLabels[mediaId] ?? "",
                        onRemove: { removeReference(entry, mediaId: mediaId) },
                        onDropBefore: { placeReference(entry, mediaId: $0, at: startIndex + offsetIndex) },
                        onLabelCommit: { setReferenceLabel(entry, mediaId: mediaId, label: $0) },
                        onEnlarge: {
                            if let item = bucketCandidates.first(where: { $0.mediaId == mediaId }) {
                                enlarge(item, label: entry.referenceLabels[mediaId] ?? "")
                            }
                        }
                    )
                }
                GhostAppendTile(
                    onTap: { uploadReferences(entry) },
                    onDrop: { appendReferences(entry, mediaIds: $0) }
                )
            }
        }
    }

    /// Inline per-reference label editor ("young Ava"): local draft while typing,
    /// committed on submit or focus loss so the roster document isn't rewritten per
    /// keystroke.
    private struct ReferenceLabelField: View {
        let label: String
        var width: CGFloat
        var onCommit: (String) -> Void

        @State private var draft = ""
        @FocusState private var isFocused: Bool

        var body: some View {
            TextField("Add label", text: $draft)
                .textFieldStyle(.plain)
                .font(CanonType.interface(9.5))
                .foregroundStyle(CanonColor.ink.opacity(0.75))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .focused($isFocused)
                .onSubmit { commit() }
                .onChange(of: isFocused) { _, focused in
                    if !focused {
                        commit()
                    }
                }
                .onAppear { draft = label }
                .onChange(of: label) { _, newValue in
                    if !isFocused {
                        draft = newValue
                    }
                }
                .frame(width: width)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isFocused ? Color.white.opacity(0.55) : Color.clear)
                )
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(isFocused ? CanonColor.brass : CanonColor.hairlinePaper.opacity(0.6))
                        .frame(height: isFocused ? 1.2 : 0.5)
                }
                .help(label.isEmpty ? "Label what this reference shows — e.g. \"young Ava\"" : label)
        }

        private func commit() {
            guard draft.trimmed != label.trimmed else { return }
            onCommit(draft)
        }
    }

    private struct RenderSlotCell: View {
        let slotIndex: Int
        let mediaId: String?
        let item: MediaItemRecord?
        var label: String = ""
        var onPlace: (String) -> Void
        var onRemove: (String) -> Void
        var onLabelCommit: (String) -> Void = { _ in }
        var onEnlarge: (() -> Void)? = nil

        @State private var isDropTargeted = false
        @State private var isHovered = false

        var body: some View {
            let decorated = content
                .onTapGesture { if item != nil { onEnlarge?() } }
                .overlay(alignment: .topLeading) {
                    if mediaId != nil {
                        Text("\(slotIndex + 1)")
                            .font(CanonType.archive(8, weight: .bold))
                            .foregroundStyle(CanonColor.paper)
                            .padding(3)
                            .background(Circle().fill(CanonColor.brass))
                            .padding(3)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if let mediaId, isHovered {
                        Button {
                            onRemove(mediaId)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.white)
                                .shadow(radius: 1)
                        }
                        .buttonStyle(.plain)
                        .padding(3)
                    }
                }
                .background(isDropTargeted ? CanonColor.softGold.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isDropTargeted ? CanonColor.brass : Color.clear, lineWidth: 2)
                )
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
                .help(item.map { "\(label.isEmpty ? $0.filename : label) — attaches at render · click to view larger" }
                    ?? (mediaId != nil ? "Missing media" : "Drop an image — slot \(slotIndex + 1) attaches at render"))

            VStack(spacing: 3) {
                Group {
                    if let mediaId {
                        decorated.draggable(MediaIDTransfer(mediaId: mediaId))
                    } else {
                        decorated
                    }
                }
                .dropDestination(for: MediaIDTransfer.self) { payloads, _ in
                    guard let first = payloads.first else { return false }
                    onPlace(first.mediaId)
                    return true
                } isTargeted: { isDropTargeted = $0 }
                if mediaId != nil {
                    ReferenceLabelField(label: label, width: 96, onCommit: onLabelCommit)
                }
            }
        }

        @ViewBuilder
        private var content: some View {
            if let item {
                mediaItemThumbnail(item, side: 96)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlinePaper.opacity(0.85)))
                    .overlay(alignment: .bottomLeading) {
                        if item.isRosterCompositeSheet {
                            rosterSheetBadge()
                        }
                    }
            } else if mediaId != nil {
                RoundedRectangle(cornerRadius: 8)
                    .fill(CanonColor.paperInset)
                    .frame(width: 96, height: 96)
                    .overlay(
                        Image(systemName: "questionmark")
                            .font(.system(size: 14))
                            .foregroundStyle(CanonColor.muted)
                    )
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(CanonColor.hairlinePaper, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .frame(width: 96, height: 96)
                    .overlay(
                        VStack(spacing: 5) {
                            Image(systemName: "plus")
                                .font(.system(size: 12))
                                .foregroundStyle(CanonColor.muted)
                            Text("SLOT \(slotIndex + 1)")
                                .font(CanonType.archive(8, weight: .semibold))
                                .kerning(1.2)
                                .foregroundStyle(CanonColor.muted)
                        }
                    )
            }
        }
    }

    private struct ReferenceShelfTile: View {
        let mediaId: String
        let item: MediaItemRecord?
        var label: String = ""
        var onRemove: () -> Void
        var onDropBefore: (String) -> Void
        var onLabelCommit: (String) -> Void = { _ in }
        var onEnlarge: (() -> Void)? = nil

        @State private var isDropTargeted = false
        @State private var isHovered = false

        var body: some View {
            VStack(spacing: 3) {
                Group {
                    if let item {
                        mediaItemThumbnail(item, side: 66)
                            .onTapGesture { onEnlarge?() }
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(CanonColor.paperInset)
                            .frame(width: 66, height: 66)
                            .overlay(
                                Image(systemName: "questionmark")
                                    .font(.system(size: 11))
                                    .foregroundStyle(CanonColor.muted)
                            )
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if item?.isRosterCompositeSheet == true {
                        rosterSheetBadge()
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if isHovered {
                        Button(action: onRemove) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.white)
                                .shadow(radius: 1)
                        }
                        .buttonStyle(.plain)
                        .padding(2)
                    }
                }
                .background(isDropTargeted ? CanonColor.softGold.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isDropTargeted ? CanonColor.brass : Color.clear, lineWidth: 2)
                )
                .onHover { isHovered = $0 }
                .help(label.isEmpty ? (item?.filename ?? "Missing media — remove to clear") : label)
                .draggable(MediaIDTransfer(mediaId: mediaId))
                .dropDestination(for: MediaIDTransfer.self) { payloads, _ in
                    guard let first = payloads.first, first.mediaId != mediaId else { return false }
                    onDropBefore(first.mediaId)
                    return true
                } isTargeted: { isDropTargeted = $0 }
                ReferenceLabelField(label: label, width: 66, onCommit: onLabelCommit)
            }
        }
    }

    private struct GhostAppendTile: View {
        var onTap: () -> Void
        var onDrop: ([String]) -> Void

        @State private var isDropTargeted = false

        var body: some View {
            Button(action: onTap) {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        isDropTargeted ? CanonColor.brass : CanonColor.hairlinePaper,
                        style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: [5, 4])
                    )
                    .frame(width: 66, height: 66)
                    .background(isDropTargeted ? CanonColor.softGold.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        Image(systemName: "plus")
                            .font(.system(size: 12))
                            .foregroundStyle(CanonColor.muted)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Upload image files, or drop images here")
            .dropDestination(for: MediaIDTransfer.self) { payloads, _ in
                let ids = payloads.map(\.mediaId)
                guard !ids.isEmpty else { return false }
                onDrop(ids)
                return true
            } isTargeted: { isDropTargeted = $0 }
        }
    }

    private struct EmptyReferenceWell: View {
        let kind: RosterKind
        var onUpload: () -> Void
        var onDrop: ([String]) -> Void
        var onGenerate: (() -> Void)? = nil

        @State private var isDropTargeted = false

        var body: some View {
            VStack(spacing: 9) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 18))
                    .foregroundStyle(CanonColor.muted)
                Text(kind == .characters
                    ? "Drag images from the tray, tap a tray image, upload files — or generate a first reference above. The first two fill the render slots."
                    : "Drag images from the tray, tap a tray image, or upload files. Images are saved with this object.")
                    .font(CanonType.interface(11.5))
                    .foregroundStyle(CanonColor.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                HStack(spacing: 8) {
                    Button(action: onUpload) {
                        Label("Upload files…", systemImage: "photo.badge.plus")
                    }
                    .buttonStyle(CanonUtilityButtonStyle())
                    if let onGenerate {
                        Button(action: onGenerate) {
                            Label("Generate from description", systemImage: "sparkles")
                        }
                        .buttonStyle(CanonUtilityButtonStyle())
                        .help("Seed the generate prompt above from this character's description")
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 150)
            .background(isDropTargeted ? CanonColor.softGold.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isDropTargeted ? CanonColor.brass : CanonColor.hairlinePaper,
                        style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: [6, 4])
                    )
            )
            .dropDestination(for: MediaIDTransfer.self) { payloads, _ in
                let ids = payloads.map(\.mediaId)
                guard !ids.isEmpty else { return false }
                onDrop(ids)
                return true
            } isTargeted: { isDropTargeted = $0 }
        }
    }

    // MARK: - Media tray

    private var mediaTray: some View {
        VStack(alignment: .leading, spacing: 0) {
            trayTargetBanner
                .padding(.horizontal, 14)
                .padding(.top, 12)
            trayTabs
                .padding(.horizontal, 14)
                .padding(.top, 10)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    switch trayTab {
                    case .moodboard:
                        moodboardGrid
                    case .generated:
                        generatedGrid
                    }
                }
                .padding(14)
            }
        }
        .background(CanonColor.paperInset.opacity(0.4))
    }

    private var trayTargetBanner: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let entry = selectedEntry {
                Text("ADDING TO — \(entry.name.uppercased())")
                    .font(CanonType.archive(9, weight: .semibold))
                    .kerning(1.2)
                    .foregroundStyle(CanonColor.brass)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("Tap an image to add · drag anywhere on the left")
                    .font(CanonType.interface(10))
                    .foregroundStyle(CanonColor.muted)
            } else {
                Text(kind == .characters ? "CREATE A CHARACTER FIRST" : "CREATE AN OBJECT FIRST")
                    .font(CanonType.archive(9, weight: .semibold))
                    .kerning(1.2)
                    .foregroundStyle(CanonColor.muted)
                Text(kind == .characters
                    ? "References organize under each character."
                    : "References organize under each object.")
                    .font(CanonType.interface(10))
                    .foregroundStyle(CanonColor.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var trayTabs: some View {
        HStack(spacing: 10) {
            ForEach(TrayTab.allCases) { tab in
                Button {
                    trayTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(CanonType.archive(9, weight: .semibold))
                        .kerning(1.6)
                        .foregroundStyle(trayTab == tab ? CanonColor.ink : CanonColor.muted)
                        .padding(.bottom, 4)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(trayTab == tab ? CanonColor.brass : .clear)
                                .frame(height: 2)
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var moodboardGrid: some View {
        if mediaCandidates.isEmpty {
            Text("Enable image media in the project library to use as references.")
                .font(CanonType.interface(11.5))
                .foregroundStyle(CanonColor.muted)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 8)], spacing: 8) {
                ForEach(mediaCandidates) { item in
                    TrayImageTile(
                        item: item,
                        isReferenced: selectedEntry?.referenceMediaIds.contains(item.mediaId) == true,
                        targetName: selectedEntry?.name,
                        onTap: { toggleReference(mediaId: item.mediaId) }
                    )
                }
            }
        }
    }

    private struct TrayImageTile: View {
        let item: MediaItemRecord
        let isReferenced: Bool
        let targetName: String?
        var onTap: () -> Void

        @State private var isHovered = false

        var body: some View {
            mediaItemThumbnail(item, side: 78)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isReferenced ? CanonColor.brass : CanonColor.hairlinePaper.opacity(0.8), lineWidth: isReferenced ? 1.5 : 1)
                )
                .overlay(alignment: .topTrailing) {
                    if isReferenced {
                        rosterReferencedBadge()
                    }
                }
                .overlay(alignment: .bottom) {
                    if isHovered, let targetName {
                        Text(isReferenced ? "REMOVE" : "ADD TO \(targetName.uppercased())")
                            .font(CanonType.archive(7.5, weight: .semibold))
                            .kerning(0.8)
                            .lineLimit(1)
                            .foregroundStyle(CanonColor.paper)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(CanonColor.ink.opacity(0.72)))
                            .padding(.bottom, 4)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: onTap)
                .onHover { isHovered = $0 }
                .draggable(MediaIDTransfer(mediaId: item.mediaId))
                .help(targetName.map { isReferenced ? "Remove from \($0)" : "Add to \($0)" } ?? item.filename)
        }
    }

    @ViewBuilder
    private var generatedGrid: some View {
        if generatedFrames.isEmpty {
            Text("Render frames on the FRAMES board to use them as references.")
                .font(CanonType.interface(11.5))
                .foregroundStyle(CanonColor.muted)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 124), spacing: 8)], spacing: 8) {
                ForEach(generatedFrames, id: \.imageId) { hero in
                    generatedFrameTile(hero)
                }
            }
        }
    }

    private func generatedFrameTile(_ hero: ProjectLensHeroImage) -> some View {
        let adopted = adoptedItem(for: hero)
        let isReferenced = adopted.map { selectedEntry?.referenceMediaIds.contains($0.mediaId) == true } ?? false
        let base = Color.clear
            .overlay(
                Group {
                    if let nsImage = NSImage(contentsOfFile: hero.imagePath) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        CanonColor.paperInset
                    }
                }
            )
            .frame(width: 124, height: 70)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isReferenced ? CanonColor.brass : CanonColor.hairlinePaper.opacity(0.8), lineWidth: isReferenced ? 1.5 : 1)
            )
            .overlay(alignment: .topTrailing) {
                if isReferenced {
                    rosterReferencedBadge()
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                toggleGeneratedFrame(hero)
            }
            .help(selectedEntry.map { isReferenced ? "Remove from \($0.name)" : "Tap to add to \($0.name)" }
                ?? (hero.label.trimmed.isEmpty ? "Generated frame" : hero.label))
        return Group {
            if let adopted {
                base.draggable(MediaIDTransfer(mediaId: adopted.mediaId))
            } else {
                base
            }
        }
    }

    /// The media item a generated frame was previously adopted as, if any.
    private func adoptedItem(for hero: ProjectLensHeroImage) -> MediaItemRecord? {
        bucketCandidates.first {
            $0.derivativeKind == MediaItemRecord.frameReferenceDerivativeKind && $0.sourceMediaId == hero.imageId
        }
    }

    // MARK: - Selection & drafts

    private func select(_ id: String?) {
        guard id != selectedEntryId else { return }
        commitPendingEdits(for: kind)
        focus = nil
        setSelectedEntryId(id)
        loadDrafts()
    }

    private func reconcileSelection() {
        let ids = entryIds
        if let current = selectedEntryId, ids.contains(current) { return }
        setSelectedEntryId(ids.first)
        loadDrafts()
    }

    private func loadDrafts() {
        nameDraft = selectedEntry?.name ?? ""
        descriptionDraft = selectedEntry?.descriptionPrompt ?? ""
        seedGeneratePrompt()
    }

    /// Recomposes the generate prompt from the character's current identity
    /// (live description edits included) and the selected shot preset.
    private func seedGeneratePrompt() {
        guard kind == .characters, let entry = selectedEntry else {
            generatePromptDraft = ""
            return
        }
        let character = library.projectCharacters.character(withId: entry.id)
        generatePromptDraft = RosterCharacterRenderPrompt.prompt(
            name: nameDraft.trimmed.nilIfEmpty ?? entry.name,
            description: descriptionDraft.trimmed.nilIfEmpty ?? entry.descriptionPrompt,
            signatureProps: character?.signatureProps ?? [],
            shot: generateShot
        )
    }

    private func handleFocusChange(from oldFocus: FocusTarget?, to newFocus: FocusTarget?) {
        if oldFocus == .entryName, newFocus != .entryName, let entryId = selectedEntryId {
            commitName(kind: kind, entryId: entryId)
        }
        if oldFocus == .entryDescription, newFocus != .entryDescription, let entryId = selectedEntryId {
            commitDescription(kind: kind, entryId: entryId)
        }
        if oldFocus == .createName, newFocus != .createName, createDraftName.trimmed.isEmpty {
            isCreateDraftActive = false
            createDraftName = ""
        }
    }

    private func commitPendingEdits(for kind: RosterKind) {
        guard let entryId = selectedId(for: kind) else { return }
        commitName(kind: kind, entryId: entryId)
        commitDescription(kind: kind, entryId: entryId)
    }

    private func commitName(kind: RosterKind, entryId: String) {
        guard let entry = entry(withId: entryId, kind: kind) else { return }
        let trimmed = nameDraft.trimmed
        guard !trimmed.isEmpty, trimmed != entry.name else {
            if trimmed.isEmpty { nameDraft = entry.name }
            return
        }
        let renamed: Bool
        switch kind {
        case .characters:
            renamed = library.renameCharacter(characterId: entryId, name: trimmed)
        case .objects:
            renamed = library.renameObject(objectId: entryId, name: trimmed)
        }
        if renamed {
            statusMessage = "Renamed to \(trimmed)"
        } else {
            nameDraft = entry.name
            statusMessage = library.aestheticStatus
        }
    }

    private func commitDescription(kind: RosterKind, entryId: String) {
        guard let entry = entry(withId: entryId, kind: kind) else { return }
        let trimmed = descriptionDraft.trimmed
        guard trimmed != entry.descriptionPrompt else { return }
        let saved: Bool
        switch kind {
        case .characters:
            saved = library.renameCharacter(characterId: entryId, name: entry.name, descriptionPrompt: trimmed)
        case .objects:
            saved = library.renameObject(objectId: entryId, name: entry.name, descriptionPrompt: trimmed)
        }
        if !saved {
            descriptionDraft = entry.descriptionPrompt
            statusMessage = library.aestheticStatus
        }
    }

    // MARK: - Reference ordering

    /// Places `mediaId` at `targetIndex` in the ordered reference list, moving it when
    /// already present (with index adjustment) and clamping out-of-range targets.
    nonisolated static func reorderedReferences(placing mediaId: String, at targetIndex: Int, in mediaIds: [String]) -> [String] {
        var list = mediaIds
        var index = targetIndex
        if let existing = list.firstIndex(of: mediaId) {
            list.remove(at: existing)
            if existing < index { index -= 1 }
        }
        list.insert(mediaId, at: min(max(0, index), list.count))
        return list
    }

    // MARK: - Actions

    private func createEntry() {
        let name = createDraftName.trimmed
        guard !name.isEmpty else {
            isCreateDraftActive = false
            createDraftName = ""
            focus = nil
            return
        }
        switch kind {
        case .characters:
            guard let character = library.createCharacter(name: name) else {
                statusMessage = library.aestheticStatus
                return
            }
            statusMessage = "Created \(character.name)"
            selectedCharacterId = character.characterId
        case .objects:
            guard let object = library.createObject(name: name) else {
                statusMessage = library.aestheticStatus
                return
            }
            statusMessage = "Created \(object.name)"
            selectedObjectId = object.objectId
        }
        createDraftName = ""
        isCreateDraftActive = false
        loadDrafts()
        DispatchQueue.main.async { focus = .entryDescription }
    }

    private func performDelete(_ entry: RosterEntry) {
        let ids = entryIds
        let neighbor: String? = {
            guard let index = ids.firstIndex(of: entry.id) else { return nil }
            if index + 1 < ids.count { return ids[index + 1] }
            if index > 0 { return ids[index - 1] }
            return nil
        }()
        let deleted: Bool
        switch kind {
        case .characters:
            deleted = library.deleteCharacter(characterId: entry.id)
        case .objects:
            deleted = library.deleteObject(objectId: entry.id)
        }
        if deleted {
            statusMessage = "Deleted \(entry.name)"
            setSelectedEntryId(neighbor)
            loadDrafts()
        } else {
            statusMessage = library.aestheticStatus
        }
        pendingDelete = nil
    }

    private func deleteMessage(for entry: RosterEntry) -> String {
        let refCount = entry.referenceMediaIds.count
        let refsLine = refCount == 0
            ? ""
            : " The \(refCount) reference image\(refCount == 1 ? "" : "s") stay\(refCount == 1 ? "s" : "") in your library."
        switch kind {
        case .characters:
            let casting = library.lensesCastingCharacter(characterId: entry.id)
            guard !casting.isEmpty else {
                return "\"\(entry.name)\" isn't in any scene.\(refsLine)"
            }
            let titles = casting.prefix(2).map { lens -> String in
                let title = lens.body.title.trimmed
                if !title.isEmpty { return title }
                if let slice = lens.body.goalSliceTitle?.trimmed, !slice.isEmpty { return slice }
                return "Untitled scene"
            }
            var titleSuffix = " (\(titles.joined(separator: ", ")))"
            if casting.count > titles.count {
                titleSuffix = " (\(titles.joined(separator: ", ")) and \(casting.count - titles.count) more)"
            }
            return "\"\(entry.name)\" is in \(casting.count) scene\(casting.count == 1 ? "" : "s")\(titleSuffix). Their takes keep the name and description but stop attaching reference images.\(refsLine)"
        case .objects:
            return "\"\(entry.name)\" is removed from the roster.\(refsLine)"
        }
    }

    private func setReferences(_ entry: RosterEntry, mediaIds: [String]) {
        let saved: Bool
        switch kind {
        case .characters:
            saved = library.setCharacterReferenceMedia(characterId: entry.id, mediaIds: mediaIds)
        case .objects:
            saved = library.setObjectReferenceMedia(objectId: entry.id, mediaIds: mediaIds)
        }
        statusMessage = saved ? "Updated \(entry.name) references" : library.aestheticStatus
    }

    private func appendReferences(_ entry: RosterEntry, mediaIds incoming: [String]) {
        let valid = incoming.filter { id in bucketCandidates.contains { $0.mediaId == id } }
        guard !valid.isEmpty else { return }
        var updated = entry.referenceMediaIds.filter { !valid.contains($0) }
        updated.append(contentsOf: valid)
        guard updated != entry.referenceMediaIds else { return }
        setReferences(entry, mediaIds: updated)
    }

    private func removeReference(_ entry: RosterEntry, mediaId: String) {
        setReferences(entry, mediaIds: entry.referenceMediaIds.filter { $0 != mediaId })
    }

    private func buildCompositeSheet(_ entry: RosterEntry) {
        Task { @MainActor in
            switch kind {
            case .characters:
                _ = await library.buildCharacterCompositeSheet(characterId: entry.id)
            case .objects:
                _ = await library.buildObjectCompositeSheet(objectId: entry.id)
            }
            statusMessage = library.aestheticStatus
        }
    }

    private func setReferenceLabel(_ entry: RosterEntry, mediaId: String, label: String) {
        let saved: Bool
        switch kind {
        case .characters:
            saved = library.setCharacterReferenceLabel(characterId: entry.id, mediaId: mediaId, label: label)
        case .objects:
            saved = library.setObjectReferenceLabel(objectId: entry.id, mediaId: mediaId, label: label)
        }
        if !saved {
            statusMessage = library.aestheticStatus
        }
    }

    private func placeReference(_ entry: RosterEntry, mediaId: String, at targetIndex: Int) {
        let known = entry.referenceMediaIds.contains(mediaId) || bucketCandidates.contains { $0.mediaId == mediaId }
        guard known else { return }
        let updated = Self.reorderedReferences(placing: mediaId, at: targetIndex, in: entry.referenceMediaIds)
        guard updated != entry.referenceMediaIds else { return }
        setReferences(entry, mediaIds: updated)
    }

    private func toggleReference(mediaId: String) {
        guard let entry = selectedEntry else {
            statusMessage = kind == .characters ? "Create a character first" : "Create an object first"
            return
        }
        if entry.referenceMediaIds.contains(mediaId) {
            setReferences(entry, mediaIds: entry.referenceMediaIds.filter { $0 != mediaId })
        } else {
            setReferences(entry, mediaIds: entry.referenceMediaIds + [mediaId])
        }
    }

    private func toggleGeneratedFrame(_ hero: ProjectLensHeroImage) {
        guard let entry = selectedEntry else {
            statusMessage = kind == .characters ? "Create a character first" : "Create an object first"
            return
        }
        if let adopted = adoptedItem(for: hero), entry.referenceMediaIds.contains(adopted.mediaId) {
            setReferences(entry, mediaIds: entry.referenceMediaIds.filter { $0 != adopted.mediaId })
            return
        }
        Task { @MainActor in
            guard let item = await library.archiveHeroFrameAsReference(hero) else {
                statusMessage = "Could not adopt that frame"
                return
            }
            guard let current = self.entry(withId: entry.id, kind: kind) else { return }
            if !current.referenceMediaIds.contains(item.mediaId) {
                setReferences(current, mediaIds: current.referenceMediaIds + [item.mediaId])
            }
        }
    }

    private func uploadReferences(_ entry: RosterEntry) {
        Task { @MainActor in
            let imported = await library.chooseRosterReferenceImages()
            guard !imported.isEmpty else { return }
            guard let current = self.entry(withId: entry.id, kind: kind) else { return }
            let incoming = imported.map(\.mediaId).filter { !current.referenceMediaIds.contains($0) }
            guard !incoming.isEmpty else {
                statusMessage = "Those images are already \(entry.name) references"
                return
            }
            setReferences(current, mediaIds: current.referenceMediaIds + incoming)
        }
    }
}

/// Brass check badge marking a tray image already referenced by the selected entry.
fileprivate func rosterReferencedBadge() -> some View {
    Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 12))
        .foregroundStyle(CanonColor.brass)
        .background(Circle().fill(CanonColor.paper))
        .padding(3)
}

/// Grid glyph marking a composite reference sheet (several views in one image).
fileprivate func rosterSheetBadge() -> some View {
    Image(systemName: "square.grid.2x2.fill")
        .font(.system(size: 8, weight: .semibold))
        .foregroundStyle(CanonColor.paper)
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 4).fill(CanonColor.brass.opacity(0.9)))
        .padding(3)
        .help("Composite reference sheet — several labeled views in one image")
}
