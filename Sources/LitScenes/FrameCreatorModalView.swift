import AppKit
import SwiftUI

/// Which impulse spawned a frame from a placed clip's moment.
enum ClipMomentIntent: String, Hashable {
    /// Author what happens AFTER the clip's out point.
    case continueFrom = "continue"
    /// Author the moment that leads INTO the clip's in point.
    case precede
    /// Recreate the seeded moment's composition (the style wheel is the
    /// transform surface).
    case transform
}

/// A clip moment captured as a still and carried into the Frame Creator as
/// the render's visual anchor.
struct ClipMomentSeed: Hashable, Identifiable {
    var shotId: String
    var entryId: String
    var clipMediaId: String
    var clipFilename: String
    var stillMediaId: String
    var stillPath: String
    var timestampSeconds: Double
    var intent: ClipMomentIntent
    var placeIntoShot: Bool

    var id: String {
        "\(entryId)|\(intent.rawValue)|\(String(format: "%.2f", timestampSeconds))"
    }
}

/// The seed still's manifest descriptor — content-only language (style rides
/// the style slot, never words), appended OUTSIDE enrichment like every other
/// attachment descriptor.
func clipMomentAttachmentDescriptor(intent: ClipMomentIntent, clipFilename: String) -> String {
    switch intent {
    case .continueFrom:
        return "This reference is the exact final frame of preceding real footage (\(clipFilename)). Generate the moment that follows it — same scene, same subject, continuous action."
    case .precede:
        return "This reference is the exact first frame of following real footage (\(clipFilename)). Generate the moment just before it — same scene, same subject."
    case .transform:
        return "Recreate this reference frame's exact composition, scene, and subject."
    }
}

/// A direct library reference's manifest descriptor — content-only language
/// (style rides the style slot, never words), appended OUTSIDE enrichment like
/// every other attachment descriptor.
func mediaReferenceAttachmentDescriptor(filename: String) -> String {
    "Reference image from the project library (\(filename)). Use it as visual source context — subject, composition, structure, and material cues may draw from it — while the written prompt remains the primary instruction."
}

/// The variation/restyle template's manifest descriptor. Without the source
/// image riding, a "variation" was a text-only regeneration that landed
/// either unrelated to the original or as a near-copy of it (user testing:
/// the render read as a plain copy) — the source frame is the anchor
/// that makes "variation OF this frame" literally true.
func variationTemplateAttachmentDescriptor(restyle: Bool) -> String {
    restyle
        ? "RESTYLE SOURCE — the exact frame this render restyles. Keep its subject, composition, and world; re-render it in the style the written prompt describes. Do not return the image unchanged and do not invent a different scene."
        : "VARIATION SOURCE — the exact frame this render varies. Produce a variation of THIS image: keep its subject, composition, world, and continuity, applying only the changes the written prompt asks for. Do not return the image unchanged and do not invent an unrelated scene."
}

/// Which stratum a planned attachment came from. The merge order is
/// seed → direct → mention, and fate lookups are stratum-qualified so the same
/// image planned as both a direct reference and a mention reference can't
/// cross-tag.
enum FrameCreatorAttachmentStratum: Hashable {
    case seed
    case direct
    case mention
}

/// The structured result of the attachment-merge law: every planned attachment
/// with its fate under the active stack's capacity, plus the honesty notes
/// derived from those fates. The reference well's live readouts and the
/// submitted request consume this one plan, so they can never disagree.
struct FrameCreatorAttachmentPlan: Hashable {
    enum Fate: Hashable {
        /// Attaches natively.
        case rides
        /// Attaches via the engine's labeled composite sheet (Stability, ≥2 riding).
        case ridesInSheet
        /// Dropped: the stack renders from text only.
        case droppedTextOnly
        /// Dropped: the stack's `keptCount` native slots are already held —
        /// by `keptLabel` when there is exactly one slot.
        case droppedOverSlotLimit(keptCount: Int, keptLabel: String)
        /// Dropped: beyond the shared attachment budget.
        case droppedOverBudget

        var rides: Bool {
            switch self {
            case .rides, .ridesInSheet: true
            case .droppedTextOnly, .droppedOverSlotLimit, .droppedOverBudget: false
            }
        }
    }

    struct Entry: Hashable {
        var attachment: LensPromptImageAttachment
        var stratum: FrameCreatorAttachmentStratum
        var fate: Fate
    }

    var stackLabel: String
    var capacity: FrameReferenceCapacity
    var entries: [Entry]

    /// The attachments that actually ride the render, in merge order.
    var attachments: [LensPromptImageAttachment] {
        entries.filter { $0.fate.rides }.map(\.attachment)
    }

    /// Everything the user has planned, riding or not.
    var plannedCount: Int { entries.count }
    var ridingCount: Int { entries.filter { $0.fate.rides }.count }

    func fate(sourceId: String, stratum: FrameCreatorAttachmentStratum) -> Fate? {
        entries.first { $0.stratum == stratum && $0.attachment.sourceId == sourceId }?.fate
    }

    /// The honesty notes, derived from the fates so note text and chip states
    /// can never tell different stories.
    var notes: [String] {
        var notes: [String] = []
        if capacity == .textOnly, entries.contains(where: { $0.stratum != .mention }) {
            // The mention strip already explains text-only mentions; only the
            // seed/direct inputs need a note here.
            notes.append("\(stackLabel) can't attach reference images — these references won't ride this render.")
        }
        let overSlotLimit = entries.lazy.compactMap { entry -> (keptCount: Int, keptLabel: String)? in
            if case .droppedOverSlotLimit(let keptCount, let keptLabel) = entry.fate { return (keptCount, keptLabel) }
            return nil
        }.first
        if let overSlotLimit {
            if overSlotLimit.keptCount == 1 {
                let keptIsMention = entries.first?.stratum == .mention
                notes.append(keptIsMention
                    ? "\(stackLabel) attaches one image — using \(overSlotLimit.keptLabel). Build composite sheets to carry more views in one slot."
                    : "\(stackLabel) attaches one image — using \(overSlotLimit.keptLabel).")
            } else if case .slots(let declared) = capacity, declared > FrameReferenceCapacity.attachmentBudget {
                // The model accepts more than the app plans — the cut is the
                // shared budget's, so say so (same copy as the budget fate).
                notes.append("Attachment budget: using the first \(overSlotLimit.keptCount) reference images.")
            } else {
                notes.append("\(stackLabel) attaches up to \(overSlotLimit.keptCount) images — using the first \(overSlotLimit.keptCount).")
            }
        }
        if entries.contains(where: { $0.fate == .droppedOverBudget }) {
            notes.append("Attachment budget: using the first \(FrameReferenceCapacity.attachmentBudget) reference images.")
        }
        if capacity == .compositeSheet, ridingCount > 1 {
            notes.append("\(stackLabel) accepts one native image — all \(ridingCount) references will be combined into one labeled sheet.")
        }
        return notes
    }
}

/// The single attachment-merge law for a Frame Creator submit: the clip-moment
/// seed leads (it is the render's visual anchor), direct library references
/// follow, mention references last. Every provider cap and its honesty note is
/// computed here and nowhere else.
func frameCreatorAttachmentPlan(
    seed: LensPromptImageAttachment?,
    direct: [LensPromptImageAttachment],
    mention: [LensPromptImageAttachment],
    stack: RenderStack
) -> FrameCreatorAttachmentPlan {
    let ordered: [(attachment: LensPromptImageAttachment, stratum: FrameCreatorAttachmentStratum)] =
        (seed.map { [($0, FrameCreatorAttachmentStratum.seed)] } ?? [])
            + direct.map { ($0, .direct) }
            + mention.map { ($0, .mention) }
    let capacity = stack.frameReferenceCapacity
    let entries: [FrameCreatorAttachmentPlan.Entry]
    switch capacity {
    case .textOnly:
        entries = ordered.map { .init(attachment: $0.attachment, stratum: $0.stratum, fate: .droppedTextOnly) }
    case .slots:
        // The slot count caps before the budget can (planningCap ≤ budget),
        // so over-budget never applies here.
        let cap = capacity.planningCap
        let keptLabel = ordered.first.map { $0.attachment.label.isEmpty ? "the first reference" : $0.attachment.label }
            ?? "the first reference"
        entries = ordered.enumerated().map { index, pair in
            .init(
                attachment: pair.attachment,
                stratum: pair.stratum,
                fate: index < cap ? .rides : .droppedOverSlotLimit(keptCount: cap, keptLabel: keptLabel)
            )
        }
    case .compositeSheet, .budget:
        let budget = FrameReferenceCapacity.attachmentBudget
        let inSheet = capacity == .compositeSheet && min(ordered.count, budget) > 1
        entries = ordered.enumerated().map { index, pair in
            .init(
                attachment: pair.attachment,
                stratum: pair.stratum,
                fate: index >= budget ? .droppedOverBudget : (inSheet ? .ridesInSheet : .rides)
            )
        }
    }
    return FrameCreatorAttachmentPlan(stackLabel: stack.label, capacity: capacity, entries: entries)
}

/// Tuple view of the merge law — the plan's attachments and notes without the
/// per-entry fates.
func frameCreatorCombinedAttachments(
    seed: LensPromptImageAttachment?,
    direct: [LensPromptImageAttachment],
    mention: [LensPromptImageAttachment],
    stack: RenderStack
) -> (attachments: [LensPromptImageAttachment], notes: [String]) {
    let plan = frameCreatorAttachmentPlan(seed: seed, direct: direct, mention: mention, stack: stack)
    return (plan.attachments, plan.notes)
}

/// What the Frame Creator is making — drives header copy, prompt seeding, the
/// resettable style seed, and (as the theater's sheet item) which render path
/// the submit takes. Every context initially renders with no style.
enum FrameCreationContext: Identifiable {
    /// A frame from scratch: empty prompt, resettable lens-primary style seed,
    /// no ancestry.
    case blankFrame(category: LensConceptCategory)
    /// A riff on one specific frame, seeded from it.
    case variation(of: ProjectLensHeroImage)
    /// A style-forward riff: same seeding as `variation`, but the header
    /// states the intent — the operator came to change the LOOK of this
    /// frame, and the style wheel is the control they reach for first.
    case restyle(of: ProjectLensHeroImage)
    /// Another take of an identity group (character/object), seeded from the
    /// group's latest take — the group IS the template, and the UI says so.
    case groupTake(groupName: String, template: ProjectLensHeroImage)
    /// Fulfills a planned suggestion card in place: seeded from the plan's prompt
    /// with its style retained for an explicit reset, and the submit renders back
    /// into the SAME row — no sibling.
    case plannedFrame(ProjectLensHeroImage)
    /// A frame spawned from a placed clip's moment (the Inspector's deck):
    /// the captured still attaches as the render's visual anchor.
    case clipMoment(ClipMomentSeed)
    /// A frame gathered for a STAGE: the generating row joins the stage's
    /// palette the moment it exists. `appendToCutId` additionally lands it at
    /// the end of one of the stage's cuts (the cut-rail "+" path).
    case stageFrame(stageId: String, appendToCutId: String?)
    /// A Frame created from the flat workspace. With a Shot id it lands at
    /// that row's end; nil leaves it in Source Material only.
    case shotFrame(appendToShotId: String?)

    var templateImage: ProjectLensHeroImage? {
        switch self {
        case .blankFrame, .clipMoment, .stageFrame, .shotFrame:
            return nil
        case .variation(let image), .restyle(let image):
            return image
        case .groupTake(_, let template):
            return template
        case .plannedFrame(let image):
            return image
        }
    }

    var clipMomentSeed: ClipMomentSeed? {
        if case .clipMoment(let seed) = self { return seed }
        return nil
    }

    var id: String {
        switch self {
        case .blankFrame(let category):
            return "blank_\(category.rawValue)"
        case .variation(let image):
            return "variation_\(image.imageId)"
        case .restyle(let image):
            return "restyle_\(image.imageId)"
        case .groupTake(_, let template):
            return "group_\(template.imageId)"
        case .plannedFrame(let image):
            return "planned_\(image.imageId)"
        case .clipMoment(let seed):
            return "clipmoment_\(seed.id)"
        case .stageFrame(let stageId, let appendToCutId):
            return "stageframe_\(stageId)_\(appendToCutId ?? "pool")"
        case .shotFrame(let appendToShotId):
            return "shotframe_\(appendToShotId ?? "source")"
        }
    }
}

/// The Frame Creator: engraved-plate replacement for the Render New Take
/// composer. A rotating style-catalog wheel feeds the Frame through a fixed
/// pointer; MOODS contribute text-only analysis lines; the FORM prompt sits
/// under the stack selector. Emits the same `LensNewTakeRenderRequest` the old
/// composer did.
struct FrameCreatorModal: View {
    private static let fallbackModalSize = CGSize(width: 1240, height: 720)
    private static let maxMoodSelections = LensNewTakeRenderRequest.maxMoodInfluences
    private static let mentionPickerLayer = 20.0
    /// Frames render 16:9; the hero and the reference preview both honour it.
    static let frameHeroAspectRatio = 16.0 / 9.0
    private static let referencePreviewLayer = 40.0

    let lens: ProjectLens
    let context: FrameCreationContext
    let workspaceSize: CGSize

    private var templateImage: ProjectLensHeroImage? { context.templateImage }
    let moodboardItems: [MediaItemRecord]
    let moodObservationsById: [String: ImageObservationResult]
    let hasOpenAICredential: Bool
    let hasCivitaiCredential: Bool
    let hasFALCredential: Bool
    let hasStabilityCredential: Bool
    let isRenderBlocked: Bool
    let renderBlockerHelp: String?
    /// Free slots in the engine's parallel Frame take lane — the batch cap:
    /// Render refuses while more stacks are selected than lanes are free.
    var takeLaneFreeSlots: Int = .max
    let formGenerations: [[LensFrameFormOption]]
    /// True while the library's media analysis pass is running (drives the
    /// mini spinners on un-analyzed mood tiles).
    var isAnalyzingMoods: Bool = false
    /// Fired once on appear when any mood tile lacks an analysis observation,
    /// so un-analyzed moodboard images become selectable without a trip to the
    /// Library.
    var onAutoAnalyzeMoods: () -> Void = {}
    var onOpenAppSettings: (() -> Void)?
    var onPreviewStyle: (StyleImagePreviewRequest) -> Void
    var onExpandFormOption: ((LensFrameFormOption, String?) async -> [LensFrameFormOption])?
    /// Refine chat: (currentPrompt, directive, priorDirectives) → the rewrite
    /// + a change note, or nil on failure.
    var onTransformFormPrompt: ((String, String, [String]) async -> LensFormPromptTransform?)?
    /// One request per selected stack, in stack-list order — the parent fans
    /// them out as parallel renders (the take lane holds them all at once).
    var onSubmit: ([LensNewTakeRenderRequest]) -> Void
    var onCancel: () -> Void
    /// Roster characters/objects mentionable via `@Name` in the prompt — a mention
    /// attaches that entry's reference images (or its composite sheet) to the render.
    var mentionEntries: [RosterMentionResolver.Entry] = []
    /// Full image inventory, for resolving mentioned entries' reference paths.
    var mentionReferenceItems: [MediaItemRecord] = []
    /// Builds a mentioned entry's composite reference sheet on demand, so a first
    /// @mention of an entry with ≥2 references attaches one labeled sheet instead of
    /// loose images. Nil keeps the loose-reference fallback.
    var onEnsureMentionSheet: ((RosterMentionResolver.Entry) async -> MediaItemRecord?)? = nil
    /// SCENES v2 law: a character's identity rides only as its rendered sheet; without
    /// one the mention renders from text. V1 keeps the composite/loose ladder.
    var identityFromSheetsOnly = false
    /// Library images offerable as direct prompt-image references (the reference
    /// well's picker candidates). Empty hides the well entirely.
    var referenceLibraryItems: [MediaItemRecord] = []
    /// References pre-attached at launch (a Media "Use in Frame Creator"
    /// hand-off); removable like any picked reference.
    var initialReferenceItems: [MediaItemRecord] = []
    /// Generated frames (lens takes) offerable in the reference picker. Picking
    /// one runs `onAdoptGeneratedFrame` at confirm time.
    var generatedFrameCandidates: [GeneratedFrameCandidate] = []
    /// Adopts a picked take as a frame_reference media record (idempotent — the
    /// deterministic mediaId re-uses one record per take). Nil hides the
    /// Generated Frames picker scope.
    var onAdoptGeneratedFrame: ((ProjectLensHeroImage) async -> MediaItemRecord?)? = nil
    /// Upload…: import image files from disk and return the records to attach
    /// directly as references. Nil hides the button.
    var onUploadReferences: (() async -> [MediaItemRecord])? = nil

    @State private var prompt: String
    @State private var isUploadingReferences = false
    /// The prompt-transform switch — seeded from the template frame so a
    /// verbatim frame's variation/retake opens verbatim.
    @State private var isPromptTransformEnabled: Bool
    /// Stability reference fidelity (strength override); seeded from the
    /// template frame so retakes reuse the choice.
    @State private var stabilityReferenceStrength: Double?
    /// Once the user touches the stack picker, reference-aware routing may
    /// only SUGGEST a capable stack — never auto-switch.
    @State private var hasUserPickedStack = false
    /// MULTI-SELECT: every checked stack renders its own frame from this one
    /// submit, in parallel. Order is irrelevant here — display and submit
    /// both follow registry order.
    @State private var selectedStackIds: Set<String>
    @State private var promptCaretUTF16Offset = 0
    @State private var promptCaretAnchor = CGPoint(x: 10, y: 24)
    @State private var promptCaretRequest: FramePromptCaretRequest?
    @State private var isPromptFocused = false
    @State private var mentionPickerSuppressed = false
    @State private var mentionPickerSelectionId = ""
    /// True while submit awaits composite-sheet builds or picker confirm awaits
    /// take adoption; guards double-submit (Render reads "Preparing references…").
    @State private var isPreparingAttachments = false
    /// Direct library references attached to this render (the well's chips).
    @State private var referenceItems: [MediaItemRecord]
    @State private var isReferencePickerPresented = false
    /// Rust notes for takes whose adoption failed at picker confirm (missing
    /// file on disk); cleared on the next picker open.
    @State private var referenceAdoptionFailureNotes: [String] = []
    /// Style is opt-in for every Frame Creator launch. Seed styles remain
    /// recoverable through Reset to seed style without affecting this default.
    @State private var isStyleDisabled = true
    @State private var styleOverrideSlot: LensStyleTreatmentSlot?
    @State private var styleOverrideCatalogVersion = ""
    @State private var stylePickerCatalogVersion = ""
    @State private var styleModeByStack: [String: LensRenderStyleMode] = [:]
    @State private var debugParametersByStack: [String: String] = [:]
    @State private var selectedMoodMediaIds: [String] = []
    @State private var didRequestMoodAnalysis = false
    /// Moods open collapsed every time — the grid is a large, occasional
    /// surface and the prompt is what the Frame Creator is usually opened for.
    @State private var isMoodsExpanded = false
    /// The reference under inspection in the floating preview panel.
    @State private var previewedReferenceId = ""
    @State private var referencePreviewOffset: CGSize = .zero
    @State private var referencePreviewDragBase: CGSize = .zero
    @State private var selectedMedium: LensMediumPreset?
    /// Plate light/dark, scoped to this interface only (drives a local colorScheme
    /// override — independent of the app/system appearance).
    @State private var plateIsDark = false
    /// The hosting window's content height, measured live so the sheet fills 95%
    /// of the whole app rather than 95% of the content pane it was handed.
    @State private var measuredWindowHeight: CGFloat = 0
    /// Form-route pages: trios of knowledge-graph Form options. Seeded from the
    /// persisted document; expansion trios append while the sheet stays open.
    @State private var formPages: [[LensFrameFormOption]]
    @State private var activeFormPage = 0
    @State private var activeFormOptionId = ""
    @State private var expandedFormOptionIds: Set<String> = []
    @State private var isExpandingFormOptions = false
    /// Refine-chat thread: each turn is a restorable checkpoint of the prompt
    /// AFTER that directive was applied. Ephemeral — dies with the sheet.
    @State private var formChatTurns: [FormChatTurn] = []
    @State private var formChatInput = ""
    @State private var isFormChatRunning = false
    @State private var formChatError = ""
    @State private var formChatOriginalPrompt = ""

    private struct FormChatTurn: Identifiable {
        let id: String
        var directive: String
        var note: String
        var resultPrompt: String
    }

    init(
        lens: ProjectLens,
        context: FrameCreationContext,
        workspaceSize: CGSize,
        moodboardItems: [MediaItemRecord],
        moodObservationsById: [String: ImageObservationResult],
        hasOpenAICredential: Bool,
        hasCivitaiCredential: Bool,
        hasFALCredential: Bool,
        hasStabilityCredential: Bool,
        isRenderBlocked: Bool,
        renderBlockerHelp: String?,
        takeLaneFreeSlots: Int = .max,
        formGenerations: [[LensFrameFormOption]] = [],
        isAnalyzingMoods: Bool = false,
        onAutoAnalyzeMoods: @escaping () -> Void = {},
        onOpenAppSettings: (() -> Void)?,
        onPreviewStyle: @escaping (StyleImagePreviewRequest) -> Void,
        onExpandFormOption: ((LensFrameFormOption, String?) async -> [LensFrameFormOption])? = nil,
        onTransformFormPrompt: ((String, String, [String]) async -> LensFormPromptTransform?)? = nil,
        onSubmit: @escaping ([LensNewTakeRenderRequest]) -> Void,
        onCancel: @escaping () -> Void,
        mentionEntries: [RosterMentionResolver.Entry] = [],
        mentionReferenceItems: [MediaItemRecord] = [],
        onEnsureMentionSheet: ((RosterMentionResolver.Entry) async -> MediaItemRecord?)? = nil,
        referenceLibraryItems: [MediaItemRecord] = [],
        initialReferenceItems: [MediaItemRecord] = [],
        generatedFrameCandidates: [GeneratedFrameCandidate] = [],
        onAdoptGeneratedFrame: ((ProjectLensHeroImage) async -> MediaItemRecord?)? = nil,
        onUploadReferences: (() async -> [MediaItemRecord])? = nil,
        identityFromSheetsOnly: Bool = false
    ) {
        self.lens = lens
        self.context = context
        self.workspaceSize = workspaceSize
        self.moodboardItems = moodboardItems
        self.moodObservationsById = moodObservationsById
        self.hasOpenAICredential = hasOpenAICredential
        self.hasCivitaiCredential = hasCivitaiCredential
        self.hasFALCredential = hasFALCredential
        self.hasStabilityCredential = hasStabilityCredential
        self.isRenderBlocked = isRenderBlocked
        self.renderBlockerHelp = renderBlockerHelp
        self.takeLaneFreeSlots = takeLaneFreeSlots
        self.formGenerations = formGenerations
        self.isAnalyzingMoods = isAnalyzingMoods
        self.onAutoAnalyzeMoods = onAutoAnalyzeMoods
        self.onOpenAppSettings = onOpenAppSettings
        self.onPreviewStyle = onPreviewStyle
        self.onExpandFormOption = onExpandFormOption
        self.onTransformFormPrompt = onTransformFormPrompt
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        self.mentionEntries = mentionEntries
        self.mentionReferenceItems = mentionReferenceItems
        self.onEnsureMentionSheet = onEnsureMentionSheet
        self.referenceLibraryItems = referenceLibraryItems
        self.initialReferenceItems = initialReferenceItems
        self.generatedFrameCandidates = generatedFrameCandidates
        self.onAdoptGeneratedFrame = onAdoptGeneratedFrame
        self.onUploadReferences = onUploadReferences
        self.identityFromSheetsOnly = identityFromSheetsOnly
        var seededReferences: [MediaItemRecord] = []
        for item in initialReferenceItems where item.kind == .image {
            guard !seededReferences.contains(where: { $0.mediaId == item.mediaId }) else { continue }
            seededReferences.append(item)
        }
        _referenceItems = State(initialValue: seededReferences)
        _formPages = State(initialValue: formGenerations.filter { !$0.isEmpty })
        let seededPrompt: String
        if let seed = context.clipMomentSeed {
            seededPrompt = seed.intent == .transform
                ? "The same scene and subject as the attached reference frame."
                : ""
        } else if let template = context.templateImage {
            let attachesTemplateSeed: Bool
            switch context {
            case .variation, .restyle: attachesTemplateSeed = true
            case .blankFrame, .groupTake, .plannedFrame, .clipMoment, .stageFrame, .shotFrame: attachesTemplateSeed = false
            }
            // A reframe child's persisted prompt is the CAMERA INSTRUCTION that
            // made it ("Zoom into the selected source region…"), not a scene
            // description — seeding it into a Variation/Restyle would re-run
            // the camera move on a frame that already IS its result. Those
            // contexts attach the template as the seed image, so the neutral
            // reference line carries the intent instead.
            if attachesTemplateSeed, template.reframe != nil {
                seededPrompt = "The same scene and subject as the attached reference frame."
            } else {
                seededPrompt = Self.seedPrompt(from: template)
            }
        } else {
            seededPrompt = ""
        }
        _prompt = State(initialValue: seededPrompt)
        _isPromptTransformEnabled = State(initialValue: !(context.templateImage?.promptEnrichmentDisabled ?? false))
        _stabilityReferenceStrength = State(initialValue: context.templateImage?.stabilityStrength)
        _stylePickerCatalogVersion = State(initialValue: context.templateImage?.sourceRecipeVersion ?? lens.body.styleTreatment?.catalogVersion ?? "")
        let seededStack = RenderStackRegistry.shared.defaultStack(
            hasOpenAI: hasOpenAICredential,
            hasCivitai: hasCivitaiCredential,
            hasFAL: hasFALCredential,
            hasStability: hasStabilityCredential
        )
        // Reference-aware default: when the context ALREADY carries
        // references (clip-moment seeds, retakes with refs) and the seeded
        // default is text-only, open on the first capable stack instead —
        // a default, not a substitution: no user choice existed yet.
        var resolvedSeed = seededStack
        let contextCarriesSeed: Bool
        switch context {
        case .clipMoment, .variation, .restyle: contextCarriesSeed = true
        case .blankFrame, .groupTake, .plannedFrame, .stageFrame, .shotFrame: contextCarriesSeed = false
        }
        if let seed = resolvedSeed,
           seed.frameReferenceCapacity.planningCap == 0,
           !initialReferenceItems.isEmpty || contextCarriesSeed {
            let capable = RenderStackRegistry.shared.stacks().first { candidate in
                candidate.frameReferenceCapacity.planningCap > 0 && Self.seedCredentialSatisfied(
                    candidate,
                    hasOpenAI: hasOpenAICredential,
                    hasCivitai: hasCivitaiCredential,
                    hasFAL: hasFALCredential,
                    hasStability: hasStabilityCredential
                )
            }
            if let capable { resolvedSeed = capable }
        }
        _selectedStackIds = State(initialValue: resolvedSeed.map { [$0.id] } ?? [])
    }

    /// The checked stacks in registry order — display order IS submit order.
    private var selectedStacks: [RenderStack] {
        RenderStackRegistry.shared.stacks().filter { selectedStackIds.contains($0.id) }
    }

    /// The first selected stack (registry order) — drives the single-stack
    /// preview surfaces (reference-well readout, seed fate, mention strip).
    /// Each render still applies its own stack's capacity at submit.
    private var primaryStack: RenderStack? { selectedStacks.first }

    private var selectedStacksCaption: String {
        let stacks = selectedStacks
        guard !stacks.isEmpty else { return "" }
        return stacks.count == 1 ? stacks[0].label : "\(stacks.count) stacks"
    }

    /// Init-time credential check (conservative: the OpenAI prompt-writing
    /// key is required for FAL/Stability because the transform defaults on).
    private static func seedCredentialSatisfied(
        _ stack: RenderStack,
        hasOpenAI: Bool,
        hasCivitai: Bool,
        hasFAL: Bool,
        hasStability: Bool
    ) -> Bool {
        switch stack.credentialProvider {
        case .openAI: return hasOpenAI
        case .civitai: return hasCivitai
        case .fal: return hasFAL && hasOpenAI
        case .stability: return hasStability && hasOpenAI
        default: return false
        }
    }

    var body: some View {
        let size = modalSize
        let leftWidth = max(400, min(size.width * 0.38, 520))
        let bodyHeight = max(560, size.height - 64)
        VStack(spacing: 0) {
            header
            Rectangle().fill(PlateColor.hairline).frame(height: 1)
            HStack(alignment: .top, spacing: 0) {
                leftColumn
                    .frame(width: leftWidth, height: bodyHeight)
                    // The style wheel's dial geometry (rotating thumbs, pointer
                    // station) can extend invisibly past its region's left edge in
                    // tight windows; the options column must always win those
                    // overlapping hit tests or clicks die intermittently.
                    .zIndex(1)
                Rectangle().fill(PlateColor.hairline).frame(width: 1)
                FrameCreatorStyleWheel(
                    selectedStyleId: isStyleDisabled ? nil : styleOverrideSlot?.styleId,
                    isStyleDisabled: isStyleDisabled,
                    statusText: styleSelectionStatus,
                    showsSeedReset: styleOverrideSlot != nil || isStyleDisabled,
                    onPreviewStyle: onPreviewStyle,
                    onCatalogLoaded: { version in
                        if !version.trimmed.isEmpty {
                            stylePickerCatalogVersion = version
                        }
                    },
                    onSelectStyle: { style, catalogVersion in
                        isStyleDisabled = false
                        styleOverrideSlot = style.treatmentSlot(weight: 100).normalized()
                        styleOverrideCatalogVersion = catalogVersion.trimmed
                        styleModeByStack = [:]
                        debugParametersByStack = [:]
                    },
                    onSelectNoStyle: { selectNoStyle() },
                    onResetToSeed: { resetToSeedStyle() }
                )
                .frame(maxWidth: .infinity)
                .frame(height: bodyHeight)
                .overlay(alignment: .topLeading) {
                    projectStylesPanel
                        .padding(.top, 14)
                        .padding(.leading, 16)
                }
            }
            .overlay(alignment: .topTrailing) {
                colorSchemeToggle
                    .padding(.top, 12)
                    .padding(.trailing, 14)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(PlateColor.cream)
        .plateEngravedBorder(cornerRadius: 0, inset: 6)
        .overlay {
            if let previewedReference {
                referencePreviewPanel(previewedReference, size: size)
            }
        }
        .overlay {
            if isReferencePickerPresented {
                referencePickerLayer(size: size)
            }
        }
        .background(keyboardShortcuts)
        .background(FrameCreatorWindowHeightReader { height in
            if abs(height - measuredWindowHeight) > 1 {
                measuredWindowHeight = height
            }
        })
        .environment(\.colorScheme, plateIsDark ? .dark : .light)
    }

    /// The reference picker as a plate-level overlay — never a nested sheet
    /// (sheet-on-sheet chrome fights the engraved plate, and the plate's own
    /// Escape handling stays deterministic).
    private func referencePickerLayer(size: CGSize) -> some View {
        ZStack {
            PlateColor.ink.opacity(0.22)
                .contentShape(Rectangle())
                .onTapGesture { isReferencePickerPresented = false }
            MediaPickerSheet(
                title: "Add reference images",
                subtitle: "Chosen images — library uploads or generated frames — attach to this render as visual references; the written prompt stays primary.",
                items: referenceLibraryItems,
                observationsById: moodObservationsById,
                storyInputMediaIds: Set(moodboardItems.map(\.mediaId)),
                generatedFrameCandidates: onAdoptGeneratedFrame == nil ? [] : generatedFrameCandidates,
                preselectedIds: referenceItems.map(\.mediaId),
                capacityContext: primaryStack.map {
                    MediaPickerCapacityContext(
                        stackLabel: $0.label,
                        capacity: $0.frameReferenceCapacity,
                        reservedSlots: seedPromptAttachment == nil ? 0 : 1
                    )
                },
                onConfirm: { picks in
                    isReferencePickerPresented = false
                    applyReferencePicks(picks)
                },
                onCancel: { isReferencePickerPresented = false }
            )
            .frame(
                width: min(720, max(420, size.width - 160)),
                height: min(560, max(380, size.height - 140))
            )
        }
    }

    private var colorSchemeToggle: some View {
        Button {
            plateIsDark.toggle()
        } label: {
            Image(systemName: plateIsDark ? "moon.stars.fill" : "sun.max.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(PlateColor.ink)
                .frame(width: 32, height: 26)
                .background(RoundedRectangle(cornerRadius: 3).fill(PlateColor.creamDeep.opacity(0.5)))
                .plateEngravedBorder(cornerRadius: 3, inset: 2)
        }
        .buttonStyle(.plain)
        .help(plateIsDark ? "Switch to light plate" : "Switch to dark plate")
    }

    // MARK: - Project styles (the GOAL-generated blend, as one-tap shortcuts)

    private func selectProjectStyle(_ slot: LensStyleTreatmentSlot) {
        isStyleDisabled = false
        styleOverrideSlot = slot.normalized()
        styleOverrideCatalogVersion = lens.body.styleTreatment?.catalogVersion.trimmed ?? ""
        styleModeByStack = [:]
        debugParametersByStack = [:]
    }

    /// The lens's GOAL-generated style blend as three floating shortcut plates —
    /// one large primary and two smaller ancillary accents, staggered, unbounded
    /// (no container, no title). One tap sets the frame's style; no wheel hunt.
    @ViewBuilder
    private var projectStylesPanel: some View {
        let treatment = lens.body.styleTreatment?.normalized()
        if let primary = treatment?.primary {
            let accents = Array((treatment?.accents ?? []).prefix(2))
            ZStack(alignment: .topLeading) {
                projectStylePlate(primary, size: 96)
                    .offset(x: 0, y: 0)
                if accents.indices.contains(0) {
                    projectStylePlate(accents[0], size: 66)
                        .offset(x: 108, y: 22)
                }
                if accents.indices.contains(1) {
                    projectStylePlate(accents[1], size: 66)
                        .offset(x: 30, y: 112)
                }
            }
            .frame(width: 178, height: 182, alignment: .topLeading)
        }
    }

    private func projectStylePlate(_ slot: LensStyleTreatmentSlot, size: CGFloat) -> some View {
        let isSelected = !isStyleDisabled && styleOverrideSlot?.styleId == slot.styleId
        let label = slot.label.trimmed.isEmpty ? slot.styleId : slot.label
        return Button {
            selectProjectStyle(slot)
        } label: {
            styleSlotImage(slot)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(PlateColor.ink, lineWidth: isSelected ? 2 : 0)
                )
                .shadow(color: .black.opacity(isSelected ? 0.28 : 0.16), radius: isSelected ? 7 : 3, x: 0, y: 2)
                .scaleEffect(isSelected ? 1.04 : 1)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isSelected)
        }
        .buttonStyle(.plain)
        .help("Project style — \(label)")
    }

    /// The modal is a sheet, so it must wire its own keyboard affordances: Escape
    /// and ⌘W dismiss it, ⌘Q quits the app (a sheet can otherwise swallow these).
    /// Zero-size hidden buttons keep the shortcuts live without drawing anything.
    private var keyboardShortcuts: some View {
        Group {
            Button("") {
                // Escape closes the reference picker before it closes the plate.
                if isReferencePickerPresented {
                    isReferencePickerPresented = false
                } else {
                    onCancel()
                }
            }
            .keyboardShortcut(.cancelAction)
            Button("", action: onCancel)
                .keyboardShortcut("w", modifiers: .command)
            Button("") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private var modalSize: CGSize {
        let measuredWidth = workspaceSize.width > 0 ? workspaceSize.width : Self.fallbackModalSize.width
        // Prefer the real hosting-window height so the sheet reaches 95% of the
        // whole app, not 95% of the (smaller) lens-detail content pane.
        let baseHeight: CGFloat
        if measuredWindowHeight > 0 {
            baseHeight = measuredWindowHeight
        } else if workspaceSize.height > 0 {
            baseHeight = workspaceSize.height
        } else {
            baseHeight = Self.fallbackModalSize.height / 0.95
        }
        return CGSize(
            width: max(860, measuredWidth),
            height: max(620, baseHeight * 0.95)
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Rectangle().fill(PlateColor.hairline).frame(height: 1)
                .frame(maxWidth: 60)
            PlateLabel(text: "Frame Creator", size: 15, weight: .semibold)
                .fixedSize()
            Rectangle().fill(PlateColor.hairline).frame(height: 1)
            PlateLabel(
                text: headerContextLabel,
                size: 9,
                color: PlateColor.inkFaint
            )
            .lineLimit(1)
            Button {
                onCancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PlateColor.inkFaint)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    // MARK: - Left column

    private var leftColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                moodCluster
                frameSquare
                    .zIndex(isMentionPickerPresented ? Self.mentionPickerLayer : 0)
                formPane
            }
            .padding(16)
        }
    }

    // MARK: - Moods

    private var moodItems: [MediaItemRecord] {
        moodboardItems
            .filter { $0.kind == .image && !attachmentPath(for: $0).isEmpty }
            .sorted { lhs, rhs in
                if lhs.modifiedAt == rhs.modifiedAt {
                    return lhs.filename.localizedCaseInsensitiveCompare(rhs.filename) == .orderedAscending
                }
                return lhs.modifiedAt > rhs.modifiedAt
            }
    }

    private var moodCluster: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    isMoodsExpanded.toggle()
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    PlateLabel(text: "Moods", size: 11, weight: .semibold)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(PlateColor.inkFaint)
                        .rotationEffect(.degrees(isMoodsExpanded ? 90 : 0))
                    Spacer()
                    Text("\(selectedMoodMediaIds.count) / \(Self.maxMoodSelections)")
                        .font(PlateType.figure(10.5, weight: .medium))
                        .foregroundStyle(PlateColor.inkFaint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isMoodsExpanded ? "Collapse moods" : "Expand moods")

            if isMoodsExpanded {
                // MUST NOT be a .move transition. A `.move(edge: .top)` here
                // leaves a hit-test region parked over the header even after
                // the animation settles, so the disclosure would expand once
                // and then swallow every click that tried to close it. Proven
                // by click-injection: with .move the second click never
                // reaches the button; with .opacity it does. The slide comes
                // from the container's animated height under .clipped(), not
                // from the transition.
                moodClusterContent
                    .transition(.opacity)
            }
        }
        // Reveals the body from under the header as the stack grows — and
        // keeps it from painting over the frame hero on the way.
        .clipped()
        .onChange(of: referenceItems.map(\.mediaId)) { _, _ in
            autoRouteForReferences()
        }
        .onChange(of: isMoodsExpanded) { _, expanded in
            // Analysis is a paid per-image vision call, so it waits for the
            // panel to actually be opened rather than firing behind a
            // collapsed surface the user may never expand.
            guard expanded else { return }
            requestMoodAnalysisIfNeeded()
        }
    }

    @ViewBuilder
    private var moodClusterContent: some View {
        if moodItems.isEmpty {
            Text("No Story Input images yet. Promote images in Media (they analyze on promotion) to influence frames.")
                .font(PlateType.label(10))
                .foregroundStyle(PlateColor.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 9) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
                    ForEach(moodItems) { item in
                        moodTile(item)
                    }
                }
                Text("Selected moods lend their analysis descriptions to this frame — the images themselves are not attached.")
                    .font(PlateType.label(8.5))
                    .foregroundStyle(PlateColor.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Un-analyzed moodboard images are un-selectable; analyzing them keeps the
    /// grid from reading as broken. Fires once, on first expansion.
    private func requestMoodAnalysisIfNeeded() {
        guard !didRequestMoodAnalysis,
              moodItems.contains(where: { moodObservationsById[$0.mediaId] == nil }) else { return }
        didRequestMoodAnalysis = true
        onAutoAnalyzeMoods()
    }

    private func moodTile(_ item: MediaItemRecord) -> some View {
        let observation = moodObservationsById[item.mediaId]
        let selectionIndex = selectedMoodMediaIds.firstIndex(of: item.mediaId)
        let isSelected = selectionIndex != nil
        let isSelectable = observation != nil
        let influence = observation.map { moodInfluenceLine(filename: item.filename, observation: $0) } ?? ""
        return Button {
            toggleMood(item.mediaId)
        } label: {
            ZStack(alignment: .topTrailing) {
                plateThumbnail(path: displayPath(for: item))
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .opacity(isSelectable ? 1 : 0.35)
                if !isSelectable, isAnalyzingMoods {
                    ZStack {
                        RoundedRectangle(cornerRadius: 3).fill(PlateColor.cream.opacity(0.35))
                        ProgressView()
                            .controlSize(.small)
                    }
                    .frame(width: 72, height: 72)
                }
                if let selectionIndex {
                    Text(Self.romanNumeral(selectionIndex + 1))
                        .font(PlateType.figure(9, weight: .semibold))
                        .foregroundStyle(PlateColor.cream)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 2).fill(PlateColor.ink))
                        .padding(3)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(isSelected ? PlateColor.ink : PlateColor.hairline, lineWidth: isSelected ? 1.6 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isSelectable)
        .help(
            isSelectable
                ? (influence.isEmpty ? item.filename : influence)
                : (isAnalyzingMoods
                    ? "Analyzing this image — it becomes selectable when done."
                    : "Analyze this image in the Library to use it as a mood influence.")
        )
    }

    private func toggleMood(_ mediaId: String) {
        if let index = selectedMoodMediaIds.firstIndex(of: mediaId) {
            selectedMoodMediaIds.remove(at: index)
        } else if selectedMoodMediaIds.count < Self.maxMoodSelections {
            selectedMoodMediaIds.append(mediaId)
        }
    }

    private var selectedMoodInfluences: [LensMoodInfluence] {
        selectedMoodMediaIds.compactMap { mediaId in
            guard let item = moodboardItems.first(where: { $0.mediaId == mediaId }),
                  let observation = moodObservationsById[mediaId] else { return nil }
            let line = moodInfluenceLine(filename: item.filename, observation: observation)
            guard !line.isEmpty else { return nil }
            return LensMoodInfluence(mediaId: mediaId, label: item.filename, line: line)
        }
    }

    // MARK: - Frame square

    private var frameSquare: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Rectangle().fill(PlateColor.creamDeep)
                if let slot = currentStyleSlot {
                    // Show the selected style itself, dimmed behind the caption card.
                    styleSlotImage(slot)
                        .opacity(0.85)
                } else {
                    plateThumbnail(path: templateImage?.imagePath ?? "")
                        .opacity(0.30)
                }
                VStack(spacing: 7) {
                    PlateLabel(text: "Frame", size: 12, weight: .semibold)
                    Text(frameStyleCaption)
                        .font(PlateType.label(9.5))
                        .foregroundStyle(PlateColor.ink.opacity(0.78))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 10) {
                        if let hue = currentStyleSlot?.hueHex.trimmed.nilIfEmpty, !isStyleDisabled {
                            Circle()
                                .fill(canonColor(fromHex: hue, fallback: PlateColor.inkFaint))
                                .frame(width: 8, height: 8)
                                .overlay(Circle().stroke(PlateColor.ink, lineWidth: 0.5))
                        }
                        Text("Moods · \(Self.romanNumeral(selectedMoodMediaIds.count))")
                            .font(PlateType.figure(9.5, weight: .medium))
                            .foregroundStyle(PlateColor.inkFaint)
                        if !selectedStacks.isEmpty {
                            Text(selectedStacksCaption)
                                .font(PlateType.figure(9.5, weight: .medium))
                                .foregroundStyle(PlateColor.inkFaint)
                        }
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(PlateColor.cream.opacity(0.82))
                )
            }
            .frame(maxWidth: .infinity)
            // 16:9 — the shape the frame actually renders at. A fixed height
            // made the hero a wide letterbox that previewed the wrong crop.
            .aspectRatio(Self.frameHeroAspectRatio, contentMode: .fit)
            .clipped()
            .plateEngravedBorder(cornerRadius: 2, inset: 4)
            .overlay(alignment: .trailing) {
                // The wheel's pointer lands here: the style feeds the frame's right edge.
                PlatePointer()
                    .fill(PlateColor.ink)
                    .frame(width: 22, height: 14)
                    .offset(x: 22)
                    .allowsHitTesting(false)
            }
            formSection
                .zIndex(isMentionPickerPresented ? Self.mentionPickerLayer : 0)
            Button(isPreparingAttachments ? "Preparing references…" : submitButtonTitle) {
                submitSelected()
            }
            .buttonStyle(PlateButtonStyle(isProminent: true, isFullWidth: true))
            .disabled(renderStartBlocker != nil || isPreparingAttachments)
            .help(renderStartBlocker ?? "\(submitButtonTitle) with \(selectedStacksCaption.isEmpty ? "the selected stack" : selectedStacksCaption) — selected stacks render in parallel")
            if let reason = renderStartBlocker {
                blockerNotice(reason)
            }
        }
    }

    private var frameStyleCaption: String {
        if isStyleDisabled { return "No style — prompt only" }
        if let styleOverrideSlot {
            let label = styleOverrideSlot.label.trimmed.isEmpty ? styleOverrideSlot.styleId : styleOverrideSlot.label
            return "Style · \(label)"
        }
        if let inheritedStyleSlot {
            let label = inheritedStyleSlot.label.trimmed.isEmpty ? inheritedStyleSlot.styleId : inheritedStyleSlot.label
            return "Seed style · \(label)"
        }
        return "No style guidance"
    }

    /// The batch blocker: the parent's block reason first (pause, exclusive
    /// Scene Plan work, a full lane), then the batch-vs-free-lanes check,
    /// then each selected stack's own blockers in submit order.
    private var renderStartBlocker: String? {
        if let renderBlockerHelp { return renderBlockerHelp }
        let stacks = selectedStacks
        guard !stacks.isEmpty else { return "Choose a stack first." }
        if stacks.count > takeLaneFreeSlots {
            return takeLaneFreeSlots == 0
                ? "All Frame render lanes are busy — wait for one to finish"
                : "\(stacks.count) stacks selected but only \(takeLaneFreeSlots) render lane\(takeLaneFreeSlots == 1 ? "" : "s") free — deselect \(stacks.count - takeLaneFreeSlots) or wait"
        }
        for stack in stacks {
            if let blocker = startBlocker(for: stack) {
                return stacks.count == 1 ? blocker : "\(stack.label): \(blocker)"
            }
        }
        return nil
    }

    // MARK: - Form area (story-route prompt; sits between the style hero and Render)

    private var formSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                PlateLabel(text: "Form", size: 11, weight: .semibold)
                Spacer()
                if !formPages.isEmpty {
                    formCycler
                }
            }
            if let caption = activeFormCaption {
                Text(caption)
                    .font(PlateType.label(9))
                    .italic()
                    .foregroundStyle(PlateColor.inkFaint)
                    .lineLimit(1)
            }
            mediumControl
            stabilityFidelityControl
            referenceRoutingSuggestion
            promptEditor
            clipSeedStrip
            referenceWell
            mentionStrip
            if onTransformFormPrompt != nil {
                formRefineChat
            }
            Text(footerCaption)
                .font(PlateType.label(8.5))
                .foregroundStyle(PlateColor.inkFaint)
        }
    }

    private var promptEditor: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                FrameCreatorPromptTextEditor(
                    text: $prompt,
                    caretRequest: promptCaretRequest,
                    isMentionPickerPresented: isMentionPickerPresented,
                    onCaretChange: { offset, anchor in
                        promptCaretUTF16Offset = offset
                        promptCaretAnchor = anchor
                        mentionPickerSuppressed = false
                    },
                    onFocusChange: { isFocused in
                        isPromptFocused = isFocused
                        if !isFocused {
                            mentionPickerSuppressed = true
                        }
                    },
                    onPickerMove: moveMentionPickerSelection,
                    onPickerSelect: completeSelectedMention,
                    onPickerDismiss: {
                        mentionPickerSuppressed = true
                    }
                )
                .padding(7)

                if isMentionPickerPresented {
                    let pickerWidth = min(310, max(230, geometry.size.width - 16))
                    mentionPicker
                        .frame(width: pickerWidth)
                        .offset(
                            x: min(max(8, promptCaretAnchor.x), max(8, geometry.size.width - pickerWidth - 8)),
                            y: min(max(26, promptCaretAnchor.y + 3), geometry.size.height - 12)
                        )
                        .zIndex(Self.mentionPickerLayer)
                }
            }
        }
        .frame(height: 150)
        .background(RoundedRectangle(cornerRadius: 3).fill(PlateColor.creamDeep.opacity(0.55)))
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(prompt.trimmed.isEmpty ? PlateColor.ink.opacity(0.65) : PlateColor.hairline, lineWidth: 1)
        )
        .zIndex(isMentionPickerPresented ? Self.mentionPickerLayer : 0)
    }

    /// The seed anchor chip: a clip moment or a variation/restyle template —
    /// a non-removable strip stating that this render is pinned to real
    /// source pixels, and how.
    @ViewBuilder
    private var clipSeedStrip: some View {
        if let seed = context.clipMomentSeed {
            seedStrip(
                sourceId: seed.stillMediaId,
                imagePath: seed.stillPath,
                caption: seedStripCaption(seed)
            )
        } else if let template = variationSeedTemplate, seedPromptAttachment != nil {
            let restyle: Bool = {
                if case .restyle = context { return true }
                return false
            }()
            seedStrip(
                sourceId: template.imageId,
                imagePath: template.imagePath,
                caption: restyle
                    ? "Attaches this frame — the render restyles it, keeping its subject and composition."
                    : "Attaches this frame — the render is a variation of it, changed only where the prompt says."
            )
        }
    }

    private func seedStrip(sourceId: String, imagePath: String, caption: String) -> some View {
        let fate = primaryStack.flatMap { stack in
            attachmentMerge(for: stack, resolution: mentionResolution).plan
                .fate(sourceId: sourceId, stratum: .seed)
        }
        let dropped = fate.map { !$0.rides } ?? false
        return HStack(spacing: 7) {
            PlateLabel(text: "Seed", size: 9, weight: .semibold)
            plateThumbnail(path: imagePath)
                .frame(width: 46, height: 26)
                .overlay(Rectangle().stroke(dropped ? CanonColor.rust.opacity(0.6) : PlateColor.hairline, lineWidth: 1))
                .opacity(dropped ? 0.45 : 1)
            Text(caption)
                .font(PlateType.label(9.5))
                .foregroundStyle(PlateColor.inkFaint)
                .lineLimit(2)
                .opacity(dropped ? 0.45 : 1)
            Spacer(minLength: 0)
        }
        .help(attachmentFateNote(fate) ?? caption)
    }

    private func seedStripCaption(_ seed: ClipMomentSeed) -> String {
        switch seed.intent {
        case .continueFrom:
            return "Attaches the footage's final frame — this render is the moment that follows it."
        case .precede:
            return "Attaches the footage's first frame — this render is the moment just before it."
        case .transform:
            return "Attaches this footage moment — the render recreates its composition in your chosen style."
        }
    }

    private var footerCaption: String {
        var caption = formPages.isEmpty
            ? "Describe the frame. Story-route Forms appear here once the GOAL's Frame Context is ready."
            : "Load a Form above, or write your own. Choosing one charts three more routes from it."
        if !mentionEntries.isEmpty {
            caption += " Type @ to choose a Character, Object, or Place reference."
        }
        return caption
    }

    // MARK: - Reference well (direct library attachments)

    /// Direct references: arbitrary library images or adopted generated frames
    /// attached as prompt-image references — the third attachment stratum after
    /// the clip seed and before @mentions. Hidden when the launcher offered no
    /// candidates of either kind.
    @ViewBuilder
    private var referenceWell: some View {
        // The upload path must exist even on an empty library — otherwise a
        // fresh project has no way to attach its first reference.
        if onUploadReferences != nil
            || !referenceLibraryItems.isEmpty || !referenceItems.isEmpty
            || (!generatedFrameCandidates.isEmpty && onAdoptGeneratedFrame != nil) {
            let merge = primaryStack.map { stack in
                (stack: stack, result: attachmentMerge(for: stack, resolution: mentionResolution))
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    PlateLabel(text: "References", size: 9, weight: .semibold)
                    if let merge {
                        referenceCapacityReadout(stack: merge.stack, plan: merge.result.plan)
                    }
                    if referenceItems.isEmpty {
                        Text("Attach library images or generated frames as visual sources for this render.")
                            .font(PlateType.label(9))
                            .foregroundStyle(PlateColor.inkFaint)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if onUploadReferences != nil {
                        Button(isUploadingReferences ? "Uploading…" : "Upload…") {
                            uploadReferences()
                        }
                        .buttonStyle(PlateButtonStyle())
                        .disabled(isUploadingReferences)
                        .help("Import image files from disk — they join the library and attach as references in one step")
                    }
                    if !referenceLibraryItems.isEmpty || !generatedFrameCandidates.isEmpty {
                        Button("Add reference…") {
                            referenceAdoptionFailureNotes = []
                            isReferencePickerPresented = true
                        }
                        .buttonStyle(PlateButtonStyle())
                        .help("Choose library images or generated frames to ride this render as visual references")
                    }
                }
                if !referenceItems.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 6)], alignment: .leading, spacing: 6) {
                        ForEach(referenceItems) { item in
                            referenceChip(item, fate: merge?.result.plan.fate(sourceId: item.mediaId, stratum: .direct))
                        }
                    }
                }
                if let merge {
                    ForEach(merge.result.notes, id: \.self) { note in
                        Text(note)
                            .font(PlateType.label(8.5))
                            .foregroundStyle(CanonColor.rust)
                    }
                    if selectedStacks.count > 1 {
                        Text("Capacity shown for \(merge.stack.label) — each selected stack attaches within its own limits.")
                            .font(PlateType.label(8.5))
                            .foregroundStyle(PlateColor.inkFaint)
                    }
                }
                ForEach(referenceAdoptionFailureNotes, id: \.self) { note in
                    Text(note)
                        .font(PlateType.label(8.5))
                        .foregroundStyle(CanonColor.rust)
                }
            }
            .dropDestination(for: MediaIDTransfer.self) { transfers, _ in
                addReferences(mediaIds: transfers.map(\.mediaId))
                return true
            }
        }
    }

    /// The header's honest capacity readout: planned images (clip seed, direct
    /// references, and @mention images together) against the active stack.
    @ViewBuilder
    private func referenceCapacityReadout(stack: RenderStack, plan: FrameCreatorAttachmentPlan) -> some View {
        let planned = plan.plannedCount
        let budget = FrameReferenceCapacity.attachmentBudget
        switch plan.capacity {
        case .textOnly:
            Text("TEXT-ONLY")
                .font(PlateType.label(7.5, weight: .bold))
                .kerning(0.45)
                .foregroundStyle(CanonColor.rust)
                .help("\(stack.label) renders from text only — reference images won't attach.")
        case .slots:
            let cap = plan.capacity.planningCap
            Text("\(planned) / \(cap)")
                .font(PlateType.figure(9.5, weight: .medium))
                .foregroundStyle(planned > cap ? CanonColor.rust : PlateColor.inkFaint)
                .help(cap == 1
                    ? "\(stack.label) attaches one image — the first planned reference rides."
                    : (cap == budget
                        ? "Planned images for this render — clip seed, references, and @mention images together — against \(stack.label)'s \(budget)-image budget."
                        : "\(stack.label) attaches up to \(cap) images — the first \(cap) planned references ride."))
        case .compositeSheet:
            Text(planned > budget
                ? "\(planned) / \(budget) → 1 sheet"
                : (planned > 1 ? "\(planned) → 1 sheet" : "\(planned) / \(budget)"))
                .font(PlateType.figure(9.5, weight: .medium))
                .foregroundStyle(planned > budget ? CanonColor.rust : PlateColor.inkFaint)
                .help("\(stack.label) accepts one native image — planned references combine into one labeled sheet.")
        case .budget:
            Text("\(planned) / \(budget)")
                .font(PlateType.figure(9.5, weight: .medium))
                .foregroundStyle(planned > budget ? CanonColor.rust : PlateColor.inkFaint)
                .help("Planned images for this render — clip seed, references, and @mention images together — against \(stack.label)'s \(budget)-image budget.")
        }
    }

    private func referenceChip(_ item: MediaItemRecord, fate: FrameCreatorAttachmentPlan.Fate?) -> some View {
        let dropped = fate.map { !$0.rides } ?? false
        return HStack(spacing: 6) {
            Button {
                openReferencePreview(item)
            } label: {
                plateThumbnail(path: displayPath(for: item))
                    .frame(width: 46, height: 26)
                    .overlay(Rectangle().stroke(PlateColor.hairline, lineWidth: 1))
                    .opacity(dropped ? 0.45 : 1)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show \(item.filename) larger")
            Text(item.filename)
                .font(PlateType.label(9, weight: .medium))
                .foregroundStyle(PlateColor.ink)
                .lineLimit(1)
                .opacity(dropped ? 0.45 : 1)
            Spacer(minLength: 0)
            Button {
                referenceItems.removeAll { $0.mediaId == item.mediaId }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(PlateColor.inkFaint)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove this reference")
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 3).fill(PlateColor.creamDeep.opacity(0.7)))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(dropped ? CanonColor.rust.opacity(0.6) : PlateColor.hairline, lineWidth: 1))
        .help(referenceChipHelp(item, fate: fate))
    }

    // MARK: - Reference preview (floating, draggable inspector)

    private var previewedReference: MediaItemRecord? {
        guard !previewedReferenceId.isEmpty else { return nil }
        return referenceItems.first { $0.mediaId == previewedReferenceId }
    }

    private func openReferencePreview(_ item: MediaItemRecord) {
        // Re-opening re-centres: a panel dragged off to a corner in a previous
        // glance should not make the next one look like nothing happened.
        if previewedReferenceId != item.mediaId {
            referencePreviewOffset = .zero
            referencePreviewDragBase = .zero
        }
        previewedReferenceId = item.mediaId
    }

    private func closeReferencePreview() {
        previewedReferenceId = ""
    }

    /// A floating plate the size of the frame hero, showing the whole
    /// reference (fitted, never cropped — the point is to inspect it). Drag it
    /// by its header; the rest of the modal stays live underneath.
    private func referencePreviewPanel(_ item: MediaItemRecord, size: CGSize) -> some View {
        let panelWidth = min(max(size.width * 0.38, 400), 520) - 32
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(PlateColor.inkFaint)
                Text(item.filename)
                    .font(PlateType.label(9.5, weight: .medium))
                    .foregroundStyle(PlateColor.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button {
                    closeReferencePreview()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(PlateColor.inkFaint)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Close preview")
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(PlateColor.creamDeep.opacity(0.9))
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        referencePreviewOffset = CGSize(
                            width: referencePreviewDragBase.width + value.translation.width,
                            height: referencePreviewDragBase.height + value.translation.height
                        )
                    }
                    .onEnded { _ in
                        referencePreviewDragBase = referencePreviewOffset
                    }
            )

            Rectangle().fill(PlateColor.hairline).frame(height: 1)

            ZStack {
                PlateColor.creamDeep
                plateFittedImage(path: displayPath(for: item))
            }
            .frame(width: panelWidth, height: panelWidth / Self.frameHeroAspectRatio)
        }
        .frame(width: panelWidth)
        .background(PlateColor.cream)
        .plateEngravedBorder(cornerRadius: 2, inset: 3)
        .shadow(color: PlateColor.ink.opacity(0.28), radius: 14, y: 6)
        .offset(referencePreviewOffset)
        .zIndex(Self.referencePreviewLayer)
    }

    private func referenceChipHelp(_ item: MediaItemRecord, fate: FrameCreatorAttachmentPlan.Fate?) -> String {
        let base: String
        if let observation = moodObservationsById[item.mediaId], !observation.plainCaption.trimmed.isEmpty {
            base = "\(item.filename) — \(observation.plainCaption)"
        } else {
            base = item.filename
        }
        guard let fateNote = attachmentFateNote(fate) else { return base }
        return "\(fateNote) \(base)"
    }

    /// One-line fate explainer for hover help — nil when the attachment rides
    /// natively (nothing to explain).
    private func attachmentFateNote(_ fate: FrameCreatorAttachmentPlan.Fate?) -> String? {
        guard let stackLabel = primaryStack?.label else { return nil }
        switch fate {
        case .droppedTextOnly:
            return "Won't ride — \(stackLabel) renders from text only."
        case .droppedOverSlotLimit(let keptCount, let keptLabel):
            return keptCount == 1
                ? "Won't ride — \(stackLabel) attaches one image and \(keptLabel) holds the slot."
                : "Won't ride — \(stackLabel) attaches \(keptCount) images and the first \(keptCount) hold the slots."
        case .droppedOverBudget:
            return "Won't ride — beyond the \(FrameReferenceCapacity.attachmentBudget)-image budget."
        case .ridesInSheet:
            return "Rides in \(stackLabel)'s labeled composite sheet."
        case .rides, nil:
            return nil
        }
    }

    private func addReferences(mediaIds: [String]) {
        let candidates = referenceLibraryItems + mentionReferenceItems
        for mediaId in mediaIds {
            guard !referenceItems.contains(where: { $0.mediaId == mediaId }),
                  let item = candidates.first(where: { $0.mediaId == mediaId && $0.kind == .image }) else { continue }
            referenceItems.append(item)
        }
    }

    /// Upload…: imported records attach DIRECTLY — `addReferences` filters
    /// against the parent's `referenceLibraryItems` snapshot, which cannot
    /// yet contain just-imported items on the same tick.
    private func uploadReferences() {
        guard let onUploadReferences else { return }
        isUploadingReferences = true
        Task { @MainActor in
            let records = await onUploadReferences()
            for record in records where record.kind == .image
                && !referenceItems.contains(where: { $0.mediaId == record.mediaId }) {
                referenceItems.append(record)
            }
            isUploadingReferences = false
        }
    }

    /// Applies a picker confirm: media picks land directly; generated-frame
    /// picks adopt into the library first (idempotent), preserving selection
    /// order. Replace-wholesale semantics — the picker preselects the current
    /// well, so its confirmed selection IS the new well.
    private func applyReferencePicks(_ picks: [MediaPickerPick]) {
        referenceAdoptionFailureNotes = []
        let needsAdoption = picks.contains {
            if case .generatedFrame = $0 { return true }
            return false
        }
        guard needsAdoption, let onAdoptGeneratedFrame else {
            referenceItems = picks.compactMap {
                if case .media(let item) = $0 { return item }
                return nil
            }
            return
        }
        isPreparingAttachments = true
        Task {
            var resolved: [MediaItemRecord] = []
            var failures: [String] = []
            for pick in picks {
                switch pick {
                case .media(let item):
                    resolved.append(item)
                case .generatedFrame(let candidate):
                    if let adopted = await onAdoptGeneratedFrame(candidate.image) {
                        resolved.append(adopted)
                    } else {
                        failures.append("Couldn't attach \(candidate.displayLabel) — the frame's file is missing on disk.")
                    }
                }
            }
            var deduped: [MediaItemRecord] = []
            for item in resolved where !deduped.contains(where: { $0.mediaId == item.mediaId }) {
                deduped.append(item)
            }
            referenceItems = deduped
            referenceAdoptionFailureNotes = failures
            isPreparingAttachments = false
        }
    }

    /// The direct references as provider attachments (missing files drop out).
    private func directReferenceAttachments() -> [LensPromptImageAttachment] {
        referenceItems.compactMap { item in
            let path = attachmentPath(for: item)
            guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return nil }
            return LensPromptImageAttachment(
                source: .moodboardImage,
                sourceId: item.mediaId,
                label: item.filename,
                detail: mediaReferenceAttachmentDescriptor(filename: item.filename),
                imagePath: path
            ).normalized()
        }
    }

    /// The render's visual anchor as a provider attachment: the clip-moment
    /// seed, or — for variation/restyle — the TEMPLATE frame itself. A
    /// variation that never saw its source produced either an unrelated
    /// image or a text-described near-copy; anchoring on the source pixels
    /// is what makes the result a variation OF that frame.
    private var seedPromptAttachment: LensPromptImageAttachment? {
        if let seed = context.clipMomentSeed {
            return LensPromptImageAttachment(
                source: .moodboardImage,
                sourceId: seed.stillMediaId,
                label: "Clip seed — \(seed.clipFilename)",
                detail: clipMomentAttachmentDescriptor(intent: seed.intent, clipFilename: seed.clipFilename),
                imagePath: seed.stillPath
            ).normalized()
        }
        if let template = variationSeedTemplate,
           !template.imagePath.trimmed.isEmpty,
           FileManager.default.fileExists(atPath: template.imagePath) {
            let restyle: Bool
            if case .restyle = context { restyle = true } else { restyle = false }
            return LensPromptImageAttachment(
                source: .lensRenderVersion,
                sourceId: template.imageId,
                label: restyle ? "Restyle source" : "Variation source",
                detail: variationTemplateAttachmentDescriptor(restyle: restyle),
                imagePath: template.imagePath
            ).normalized()
        }
        return nil
    }

    /// The template rides as the seed ONLY for variation/restyle — group
    /// takes and planned frames keep their prompt-space contract (a group
    /// take deliberately re-renders the identity, not the pixels).
    private var variationSeedTemplate: ProjectLensHeroImage? {
        switch context {
        case .variation(let image), .restyle(let image):
            return image
        case .blankFrame, .groupTake, .plannedFrame, .clipMoment, .stageFrame, .shotFrame:
            return nil
        }
    }

    /// Seed + direct + mention attachments through the shared merge law, plus
    /// the view-dependent style-slot note. Rendered live in the reference well
    /// and used verbatim at submit.
    private func attachmentMerge(
        for stack: RenderStack,
        resolution: RosterMentionResolver.Resolution,
        sheetOverrides: [String: MediaItemRecord] = [:]
    ) -> (plan: FrameCreatorAttachmentPlan, notes: [String]) {
        let mention = mentionAttachments(for: stack, resolution: resolution, sheetOverrides: sheetOverrides)
        let plan = frameCreatorAttachmentPlan(
            seed: seedPromptAttachment,
            direct: directReferenceAttachments(),
            mention: mention.attachments,
            stack: stack
        )
        var notes = plan.notes
        if !plan.attachments.isEmpty, effectiveStyleMode(for: stack) == .attachStyleImage,
           !stack.isOpenAI {
            // Non-OpenAI providers have one image-input set: references fill
            // it, so the engine demotes their style image to prose. OpenAI
            // attaches the style image AND the references together — no note.
            notes.append("References fill \(stack.label)'s image inputs, so the style image can't attach too — the style will be described in the prompt instead.")
        }
        return (plan, notes)
    }

    // MARK: - @Mentions

    private var mentionResolution: RosterMentionResolver.Resolution {
        RosterMentionResolver.resolve(prompt: prompt, entries: mentionEntries)
    }

    /// The mentioned entry's attachable images: its composite sheet when it has one
    /// (one image, several views), else its leading two references. `sheetOverrides`
    /// carries sheets built moments ago during submit — the media list snapshot this
    /// view holds won't contain their ids yet, so the records ride in directly.
    private func mentionAttachmentPlan(
        for entry: RosterMentionResolver.Entry,
        sheetOverrides: [String: MediaItemRecord] = [:]
    ) -> (items: [(item: MediaItemRecord, label: String)], usesSheet: Bool, isCharacterSheet: Bool) {
        if identityFromSheetsOnly, entry.kind == .character {
            let activeSheet = mentionReferenceItems.first { $0.mediaId == entry.activeSheetMediaId }
            let picks = RosterCharacterRenderPrompt.identityAnchorPicks(
                referenced: [],
                referenceLabels: [:],
                capOne: false,
                activeSheet: activeSheet,
                looseReferenceFallback: false
            )
            return (picks.map { ($0.item, $0.label) }, !picks.isEmpty, picks.first?.item.isCharacterSheet == true)
        }
        // A generated character sheet is the identity anchor and rides alone.
        if !entry.activeSheetMediaId.isEmpty,
           let sheet = mentionReferenceItems.first(where: { $0.mediaId == entry.activeSheetMediaId }),
           sheet.kind == .image,
           FileManager.default.fileExists(atPath: sheet.path) {
            return ([(sheet, "character sheet")], true, true)
        }
        let referenced = entry.referenceMediaIds.compactMap { mediaId -> MediaItemRecord? in
            guard let item = mentionReferenceItems.first(where: { $0.mediaId == mediaId }) else { return nil }
            guard item.kind == .image, FileManager.default.fileExists(atPath: item.path) else { return nil }
            return item
        }
        if let sheet = referenced.first(where: { $0.isRosterCompositeSheet }) {
            return ([(sheet, entry.referenceLabels[sheet.mediaId] ?? "reference sheet")], true, false)
        }
        if let sheet = sheetOverrides[entry.id], FileManager.default.fileExists(atPath: sheet.path) {
            return ([(sheet, "reference sheet")], true, false)
        }
        let leading = referenced.filter { !$0.isRosterCompositeSheet }.prefix(2)
        return (leading.map { ($0, entry.referenceLabels[$0.mediaId] ?? "") }, false, false)
    }

    /// Attachments + honesty notes for the current mentions on a given stack.
    private func mentionAttachments(
        for stack: RenderStack,
        resolution: RosterMentionResolver.Resolution,
        sheetOverrides: [String: MediaItemRecord] = [:]
    ) -> (attachments: [LensPromptImageAttachment], notes: [String]) {
        guard !resolution.mentions.isEmpty else { return ([], []) }
        guard stack.reframeCapable else {
            return ([], ["\(stack.label) can't attach reference images — @mentions render as text only."])
        }
        var attachments: [LensPromptImageAttachment] = []
        var notes: [String] = []
        for entry in resolution.mentions {
            let plan = mentionAttachmentPlan(for: entry, sheetOverrides: sheetOverrides)
            guard !plan.items.isEmpty else {
                notes.append(
                    identityFromSheetsOnly && entry.kind == .character
                        ? "\(entry.name) has no reference sheet — the mention renders from text. Render \(entry.name)'s sheet in CHARACTERS."
                        : "\(entry.name) has no reference images — the mention renders as text only."
                )
                continue
            }
            for (item, label) in plan.items {
                attachments.append(LensPromptImageAttachment(
                    source: .moodboardImage,
                    sourceId: item.mediaId,
                    label: plan.usesSheet ? "\(entry.name) — reference sheet" : entry.name,
                    detail: RosterMentionResolver.attachmentDescriptor(for: entry, label: label, isCompositeSheet: plan.usesSheet, isCharacterSheet: plan.isCharacterSheet),
                    imagePath: item.path
                ).normalized())
            }
        }
        // Provider caps (the single slot, the shared budget, Stability's
        // composite) live in `frameCreatorAttachmentPlan` — the merge law sees
        // seed + direct + mention together, so per-mention building stays
        // cap-free here.
        return (attachments, notes)
    }

    private var activeMentionPartial: RosterMentionResolver.ActivePartial? {
        RosterMentionResolver.activePartial(
            in: prompt,
            caretUTF16Offset: promptCaretUTF16Offset,
            entries: mentionEntries
        )
    }

    private var mentionPickerSuggestions: [RosterMentionResolver.Entry] {
        guard let partial = activeMentionPartial else { return [] }
        return RosterMentionResolver.suggestions(
            for: partial,
            entries: mentionEntries,
            limit: max(mentionEntries.count, 1)
        )
    }

    private var enabledMentionPickerSuggestions: [RosterMentionResolver.Entry] {
        mentionPickerSuggestions.filter { entry in
            // Under the sheet-only law a sheetless character still mentions — as text.
            (identityFromSheetsOnly && entry.kind == .character) || !mentionAttachmentPlan(for: entry).items.isEmpty
        }
    }

    private var isMentionPickerPresented: Bool {
        isPromptFocused
            && !mentionPickerSuppressed
            && activeMentionPartial != nil
            && !mentionPickerSuggestions.isEmpty
    }

    private var mentionSuggestionFingerprint: String {
        mentionPickerSuggestions.map(\.id).joined(separator: "|")
    }

    private func normalizeMentionPickerSelection() {
        let enabled = enabledMentionPickerSuggestions
        guard !enabled.isEmpty else {
            mentionPickerSelectionId = ""
            return
        }
        if !enabled.contains(where: { $0.id == mentionPickerSelectionId }) {
            mentionPickerSelectionId = enabled[0].id
        }
    }

    private func moveMentionPickerSelection(_ delta: Int) {
        let enabled = enabledMentionPickerSuggestions
        guard !enabled.isEmpty else { return }
        let current = enabled.firstIndex(where: { $0.id == mentionPickerSelectionId }) ?? 0
        let next = min(max(current + delta, 0), enabled.count - 1)
        mentionPickerSelectionId = enabled[next].id
    }

    private func completeSelectedMention() -> Bool {
        guard let entry = enabledMentionPickerSuggestions.first(where: { $0.id == mentionPickerSelectionId })
            ?? enabledMentionPickerSuggestions.first else {
            return false
        }
        completeMention(entry)
        return true
    }

    private func completeMention(_ entry: RosterMentionResolver.Entry) {
        guard let partial = activeMentionPartial else { return }
        let replacement = "@\(entry.name) "
        let replacedRange = NSRange(partial.range, in: prompt)
        prompt = RosterMentionResolver.completing(text: prompt, partial: partial, with: entry)
        let caretOffset = replacedRange.location + replacement.utf16.count
        promptCaretUTF16Offset = caretOffset
        promptCaretRequest = FramePromptCaretRequest(utf16Offset: caretOffset)
        mentionPickerSelectionId = ""
        mentionPickerSuppressed = false
    }

    private var mentionPicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                PlateLabel(text: "Add reference", size: 9.5, weight: .semibold)
                Spacer()
                Text("↑↓ · Return · Esc")
                    .font(PlateType.figure(8.5, weight: .medium))
                    .foregroundStyle(PlateColor.inkFaint)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            Rectangle().fill(PlateColor.hairline).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    mentionPickerSection(kind: .character, title: "Characters")
                    mentionPickerSection(kind: .object, title: "Objects")
                    mentionPickerSection(kind: .place, title: "Places")
                }
                .padding(7)
            }
            .frame(maxHeight: 230)
        }
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(PlateColor.cream)
                .shadow(color: Color.black.opacity(0.22), radius: 10, y: 5)
        )
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(PlateColor.ink.opacity(0.55), lineWidth: 1))
        .onAppear(perform: normalizeMentionPickerSelection)
        .onChange(of: mentionSuggestionFingerprint) { _, _ in
            normalizeMentionPickerSelection()
        }
    }

    @ViewBuilder
    private func mentionPickerSection(kind: RosterMentionResolver.EntryKind, title: String) -> some View {
        let entries = mentionPickerSuggestions.filter { $0.kind == kind }
        if !entries.isEmpty {
            PlateLabel(text: title, size: 8.5, weight: .semibold, color: PlateColor.inkFaint)
                .padding(.horizontal, 3)
                .padding(.top, 2)
            ForEach(entries) { entry in
                mentionPickerRow(entry)
            }
        }
    }

    private func mentionPickerRow(_ entry: RosterMentionResolver.Entry) -> some View {
        let plan = mentionAttachmentPlan(for: entry)
        let isEnabled = !plan.items.isEmpty
        let isSelected = isEnabled && entry.id == mentionPickerSelectionId
        return Button {
            completeMention(entry)
        } label: {
            HStack(spacing: 8) {
                if let item = plan.items.first?.item {
                    plateThumbnail(path: displayPath(for: item))
                        .frame(width: 30, height: 30)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                } else {
                    Image(systemName: mentionPickerIcon(entry.kind))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(PlateColor.inkFaint)
                        .frame(width: 30, height: 30)
                        .background(RoundedRectangle(cornerRadius: 2).fill(PlateColor.creamDeep))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(PlateType.label(10.5, weight: .semibold))
                        .foregroundStyle(isEnabled ? PlateColor.ink : PlateColor.inkFaint)
                        .lineLimit(1)
                    Text(isEnabled ? mentionPickerReferenceLabel(plan) : "No references")
                        .font(PlateType.label(8.5))
                        .foregroundStyle(isEnabled ? PlateColor.inkFaint : CanonColor.rust)
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "return")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(PlateColor.inkFaint)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(isSelected ? PlateColor.creamDeep : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(!isEnabled)
        .onHover { hovering in
            if hovering, isEnabled {
                mentionPickerSelectionId = entry.id
            }
        }
        .help(isEnabled ? mentionChipHelp(entry) : "Add reference images before attaching \(entry.name).")
    }

    private func mentionPickerIcon(_ kind: RosterMentionResolver.EntryKind) -> String {
        switch kind {
        case .character: "person.crop.circle"
        case .object: "shippingbox"
        case .place: "building.2"
        }
    }

    private func mentionPickerReferenceLabel(
        _ plan: (items: [(item: MediaItemRecord, label: String)], usesSheet: Bool, isCharacterSheet: Bool)
    ) -> String {
        if plan.usesSheet { return "Reference sheet" }
        return "\(plan.items.count) image\(plan.items.count == 1 ? "" : "s")"
    }

    @ViewBuilder
    private var mentionStrip: some View {
        let resolution = mentionResolution
        if !resolution.mentions.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                if !resolution.mentions.isEmpty, let stack = primaryStack {
                    let merge = attachmentMerge(for: stack, resolution: resolution)
                    let mention = mentionAttachments(for: stack, resolution: resolution)
                    HStack(spacing: 5) {
                        PlateLabel(text: "Attaching", size: 9, weight: .semibold)
                        ForEach(resolution.mentions) { entry in
                            let plan = mentionAttachmentPlan(for: entry)
                            let droppedNote = mentionDroppedNote(plan: plan, mergePlan: merge.plan, stack: stack)
                            let tinted = plan.items.isEmpty || droppedNote != nil
                            HStack(spacing: 4) {
                                Image(systemName: mentionPickerIcon(entry.kind))
                                    .font(.system(size: 8.5))
                                Text(mentionChipTitle(entry, plan: plan))
                                    .font(PlateType.label(9.5, weight: .medium))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(tinted ? CanonColor.rust : PlateColor.ink)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .background(Capsule().fill(PlateColor.creamDeep.opacity(0.7)))
                            .overlay(Capsule().stroke(tinted ? CanonColor.rust.opacity(0.6) : PlateColor.hairline, lineWidth: 1))
                            .help(droppedNote.map { "\($0) \(mentionChipHelp(entry))" } ?? mentionChipHelp(entry))
                        }
                        Spacer(minLength: 0)
                    }
                    ForEach(mention.notes, id: \.self) { note in
                        Text(note)
                            .font(PlateType.label(8.5))
                            .foregroundStyle(CanonColor.rust)
                    }
                }
            }
        }
    }

    private func mentionChipTitle(_ entry: RosterMentionResolver.Entry, plan: (items: [(item: MediaItemRecord, label: String)], usesSheet: Bool, isCharacterSheet: Bool)) -> String {
        if plan.usesSheet { return "\(entry.name) · sheet" }
        if plan.items.isEmpty { return "\(entry.name) · no images" }
        return "\(entry.name) · \(plan.items.count) image\(plan.items.count == 1 ? "" : "s")"
    }

    /// A fate note when a mention has images but NONE of them ride the active
    /// stack — partial rides keep normal chrome (the well notes carry those).
    private func mentionDroppedNote(
        plan: (items: [(item: MediaItemRecord, label: String)], usesSheet: Bool, isCharacterSheet: Bool),
        mergePlan: FrameCreatorAttachmentPlan,
        stack: RenderStack
    ) -> String? {
        guard !plan.items.isEmpty else { return nil }
        if stack.frameReferenceCapacity == .textOnly {
            // Text-only mentions never enter the merge plan, so answer directly.
            return attachmentFateNote(.droppedTextOnly)
        }
        let fates = plan.items.compactMap { mergePlan.fate(sourceId: $0.item.mediaId, stratum: .mention) }
        guard !fates.isEmpty, !fates.contains(where: \.rides) else { return nil }
        return attachmentFateNote(fates.first)
    }

    private func mentionChipHelp(_ entry: RosterMentionResolver.Entry) -> String {
        let plan = mentionAttachmentPlan(for: entry)
        if plan.isCharacterSheet {
            return "Attaches \(entry.name)'s reference sheet — the identity anchor"
        }
        if plan.usesSheet {
            return "Attaches \(entry.name)'s composite reference sheet — several labeled views in one image"
        }
        if plan.items.isEmpty {
            if identityFromSheetsOnly, entry.kind == .character {
                return "\(entry.name) has no reference sheet — the mention renders from text. Render \(entry.name)'s sheet in CHARACTERS"
            }
            switch entry.kind {
            case .character:
                return "\(entry.name) has no reference images yet — click their card in the Characters sidebar to add some"
            case .object:
                return "\(entry.name) has no reference images yet — click its card in the Objects sidebar to add some"
            case .place:
                return "\(entry.name) has no reference images yet — click its card in the Places sidebar to add some"
            }
        }
        return "Attaches \(entry.name)'s leading \(plan.items.count) reference image\(plan.items.count == 1 ? "" : "s")"
    }

    // MARK: - Form refine chat

    /// The mini directive thread: each message rewrites the CURRENT editor
    /// text (hand-edits respected), the rewrite lands in the editor, and every
    /// turn stays clickable as a checkpoint.
    private var formRefineChat: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !formChatTurns.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        Button {
                            prompt = formChatOriginalPrompt
                        } label: {
                            Text("ORIGINAL")
                                .font(PlateType.label(8, weight: .semibold))
                                .foregroundStyle(PlateColor.inkFaint)
                                .padding(.horizontal, 6)
                                .frame(height: 16)
                                .overlay(RoundedRectangle(cornerRadius: 2).stroke(PlateColor.hairline, lineWidth: 1))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Restore the prompt as it was before the first refine")
                        ForEach(formChatTurns) { turn in
                            formChatTurnRow(turn)
                        }
                    }
                }
                .frame(maxHeight: 110)
            }
            HStack(spacing: 6) {
                TextField(
                    "Same sentiment, but… (e.g. a 1950s Earth farm, one relic from 2050+)",
                    text: $formChatInput
                )
                .textFieldStyle(.plain)
                .font(PlateType.label(10.5))
                .foregroundStyle(PlateColor.ink)
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 3).fill(PlateColor.creamDeep.opacity(0.55)))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(PlateColor.hairline, lineWidth: 1))
                .onSubmit(sendFormChat)
                .disabled(isFormChatRunning)
                if isFormChatRunning {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 26, height: 26)
                } else {
                    Button(action: sendFormChat) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(PlateColor.cream)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(PlateColor.ink))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(formChatInput.trimmed.isEmpty || prompt.trimmed.isEmpty)
                    .help("Rewrite the prompt per this direction — its sentiment stays, the world changes")
                }
            }
            if !formChatError.isEmpty {
                Text(formChatError)
                    .font(PlateType.label(8.5))
                    .foregroundStyle(CanonColor.rust)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func formChatTurnRow(_ turn: FormChatTurn) -> some View {
        Button {
            prompt = turn.resultPrompt
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text("→ \(turn.directive)")
                    .font(PlateType.label(9.5, weight: .medium))
                    .foregroundStyle(PlateColor.ink)
                    .lineLimit(1)
                if !turn.note.isEmpty {
                    Text("✓ \(turn.note)")
                        .font(PlateType.label(8.5))
                        .foregroundStyle(PlateColor.inkFaint)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 3).fill(PlateColor.creamDeep.opacity(0.4)))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(PlateColor.hairline.opacity(0.8), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
        .help("Restore the prompt as it was after this step")
    }

    private func sendFormChat() {
        guard let onTransformFormPrompt,
              !isFormChatRunning,
              !formChatInput.trimmed.isEmpty,
              !prompt.trimmed.isEmpty else { return }
        let directive = formChatInput.trimmed
        let currentText = prompt
        if formChatTurns.isEmpty {
            formChatOriginalPrompt = currentText
        }
        formChatInput = ""
        formChatError = ""
        isFormChatRunning = true
        Task {
            let result = await onTransformFormPrompt(currentText, directive, formChatTurns.map(\.directive))
            isFormChatRunning = false
            guard let result else {
                formChatError = "Refine failed — check the OpenAI key and try again."
                formChatInput = directive
                return
            }
            prompt = result.prompt
            formChatTurns.append(
                FormChatTurn(
                    id: UUID().uuidString,
                    directive: directive,
                    note: result.note,
                    resultPrompt: result.prompt
                )
            )
        }
    }

    /// One-chip medium picker: FILMED / ANIMATED / ILLUSTRATED / PAINTED.
    /// Tapping the active chip clears it (no medium block in the prompt).
    private var mediumControl: some View {
        HStack(spacing: 6) {
            PlateLabel(text: "Medium", size: 9, weight: .semibold)
                .padding(.trailing, 2)
            ForEach(LensMediumPreset.allCases, id: \.self) { preset in
                let isActive = selectedMedium == preset
                Button {
                    selectedMedium = isActive ? nil : preset
                } label: {
                    Text(preset.label)
                        .font(PlateType.label(8.5, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(isActive ? PlateColor.cream : PlateColor.inkFaint)
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(isActive ? PlateColor.ink : PlateColor.creamDeep.opacity(0.55))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(isActive ? PlateColor.ink : PlateColor.hairline, lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(preset.promptBlock)
            }
            Spacer(minLength: 0)
            promptTransformToggle
        }
    }

    /// Stability's reference-fidelity knob: how far the prompt may pull the
    /// output from the reference image (Stability strength; 0 ≈ identical).
    /// Shown when any selected stack is Stability and references are
    /// planned; the choice persists on the frame for retries and only the
    /// Stability renders of a batch consume it.
    @ViewBuilder
    private var stabilityFidelityControl: some View {
        if selectedStacks.contains(where: \.isStability), plannedReferenceCount > 0 {
            HStack(spacing: 6) {
                PlateLabel(text: "Reference fidelity", size: 9, weight: .semibold)
                    .padding(.trailing, 2)
                ForEach(StabilityFidelityChoice.allCases, id: \.self) { choice in
                    let isActive = choice.matches(stabilityReferenceStrength)
                    Button {
                        stabilityReferenceStrength = choice.strength
                    } label: {
                        Text(choice.label)
                            .font(PlateType.label(8.5, weight: isActive ? .semibold : .regular))
                            .foregroundStyle(isActive ? PlateColor.cream : PlateColor.inkFaint)
                            .padding(.horizontal, 8)
                            .frame(height: 20)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(isActive ? PlateColor.ink : PlateColor.creamDeep.opacity(0.55))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(isActive ? PlateColor.ink : PlateColor.hairline, lineWidth: 1)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(choice.help)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private enum StabilityFidelityChoice: CaseIterable {
        case exact
        case balanced
        case loose
        case stackDefault

        var label: String {
            switch self {
            case .exact: "EXACT"
            case .balanced: "BALANCED"
            case .loose: "LOOSE"
            case .stackDefault: "DEFAULT"
            }
        }

        var strength: Double? {
            switch self {
            case .exact: 0.25
            case .balanced: 0.5
            case .loose: 0.75
            case .stackDefault: nil
            }
        }

        var help: String {
            switch self {
            case .exact: "Stay very close to the reference image — the prompt only nudges (strength 0.25)"
            case .balanced: "Split the difference between the reference and the prompt (strength 0.5)"
            case .loose: "Let the prompt lead; the reference guides loosely (strength 0.75)"
            case .stackDefault: "The stack's declared strength (prompt-leaning 0.65 unless the recipe says otherwise)"
            }
        }

        func matches(_ value: Double?) -> Bool {
            switch self {
            case .stackDefault: return value == nil
            default: return value == strength
            }
        }
    }

    /// Honest routing: when EVERY selected stack would DROP the planned
    /// references, offer the first capable selectable stack — a suggestion
    /// after the user has touched the picker, an automatic default before.
    /// (A mixed selection warns per-row via the rust capacity hints instead.)
    @ViewBuilder
    private var referenceRoutingSuggestion: some View {
        if plannedReferenceCount > 0,
           !selectedStacks.isEmpty,
           selectedStacks.allSatisfy({ $0.frameReferenceCapacity.planningCap == 0 }),
           let capable = firstReferenceCapableStack() {
            HStack(spacing: 6) {
                Text(selectedStacks.count == 1
                    ? "\(selectedStacks[0].label) can't attach reference images — they won't ride this render."
                    : "None of the selected stacks can attach reference images — they won't ride these renders.")
                    .font(PlateType.label(8.5))
                    .foregroundStyle(CanonColor.rust)
                Button("Switch to \(capable.label)") {
                    hasUserPickedStack = true
                    withAnimation(.easeOut(duration: 0.16)) {
                        selectedStackIds = [capable.id]
                        seedDebugParametersIfNeeded(capable)
                    }
                }
                .buttonStyle(PlateButtonStyle())
                .help("\(capable.label) carries \(stackCapacityHint(capable)) — your references ride as pixels")
                Spacer(minLength: 0)
            }
        }
    }

    /// Auto-switch is legal only BEFORE the user touches the stack picker;
    /// afterwards `referenceRoutingSuggestion` offers the same move visibly.
    private func autoRouteForReferences() {
        guard !hasUserPickedStack,
              plannedReferenceCount > 0,
              !selectedStacks.isEmpty,
              selectedStacks.allSatisfy({ $0.frameReferenceCapacity.planningCap == 0 }),
              let capable = firstReferenceCapableStack() else { return }
        withAnimation(.easeOut(duration: 0.16)) {
            selectedStackIds = [capable.id]
            seedDebugParametersIfNeeded(capable)
        }
    }

    /// First selectable stack (registry order) that can carry references.
    private func firstReferenceCapableStack() -> RenderStack? {
        RenderStackRegistry.shared.stacks().first { stack in
            stack.frameReferenceCapacity.planningCap > 0 && credentialBlocker(for: stack) == nil
        }
    }

    /// The prompt transformer's hardline switch: OFF sends the authored scene
    /// text verbatim. The deterministic segments (style line, medium, moods,
    /// single-frame guard, reference manifest) ride either way; CivitAI always
    /// composes locally.
    private var promptTransformToggle: some View {
        HStack(spacing: 5) {
            Toggle("Transform prompt", isOn: $isPromptTransformEnabled)
                .toggleStyle(.checkbox)
                .font(PlateType.label(9))
                .foregroundStyle(PlateColor.inkFaint)
            if !isPromptTransformEnabled {
                PlateLabel(text: "VERBATIM", size: 7, weight: .semibold, color: CanonColor.rust)
            }
        }
        .help(isPromptTransformEnabled
            ? "An LLM rewrites your scene text into a provider-tuned prompt before rendering (references and style still ride separately). Turn off to send your words verbatim."
            : "Your scene text goes to the provider VERBATIM — no rewrite. Style line, medium, moods, and the reference manifest still ride. Also removes the OpenAI-key requirement for FAL/Stability renders. Persists on the frame: retries stay verbatim.")
    }

    // MARK: - Stack selector

    private var formPane: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                PlateLabel(text: "The Stack", size: 11, weight: .semibold)
                Spacer()
                if selectedStacks.count > 1 {
                    Text("\(selectedStacks.count) selected — render in parallel")
                        .font(PlateType.figure(9, weight: .medium))
                        .foregroundStyle(PlateColor.inkFaint)
                }
            }
            Text("Check one or more — each checked stack renders its own frame from this prompt, all at once.")
                .font(PlateType.label(8.5))
                .foregroundStyle(PlateColor.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
            // Stacks come from render_stacks.yaml (bundled defaults + the
            // Application Support overlay) — see App Settings → Stacks.
            ForEach(RenderStackRegistry.shared.stacks()) { stack in
                stackOption(title: stack.label, detail: stack.detail, stack: stack)
            }
        }
    }

    // MARK: - Form cycler (‹ i ii iii › over the knowledge-graph route pages)

    private var currentFormPageOptions: [LensFrameFormOption] {
        guard formPages.indices.contains(activeFormPage) else { return [] }
        return formPages[activeFormPage]
    }

    private var activeFormCaption: String? {
        guard let option = formPages.flatMap({ $0 }).first(where: { $0.id == activeFormOptionId }) else {
            return nil
        }
        var parts = [option.title]
        if !option.meaningName.isEmpty {
            parts.append("\(option.meaningName) · \(option.pole)")
        }
        if !option.relationToParent.isEmpty && option.relationToParent != "catalog" {
            parts.append(option.relationToParent.replacingOccurrences(of: "_", with: " "))
        }
        return parts.joined(separator: " — ")
    }

    private var formCycler: some View {
        HStack(spacing: 12) {
            ForEach(Array(currentFormPageOptions.enumerated()), id: \.element.id) { index, option in
                formCyclerNumeral(option: option, index: index)
            }
            if isExpandingFormOptions {
                ProgressView()
                    .controlSize(.mini)
            }
        }
    }

    private func formCyclerNumeral(option: LensFrameFormOption, index: Int) -> some View {
        let isActive = option.id == activeFormOptionId
        return Button {
            selectFormOption(option)
        } label: {
            VStack(spacing: 2) {
                Text(Self.romanNumeral(index + 1).lowercased())
                    .font(PlateType.figure(12, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? PlateColor.ink : PlateColor.inkFaint)
                Rectangle()
                    .fill(isActive ? PlateColor.ink : Color.clear)
                    .frame(width: 14, height: 0.75)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(option.title.isEmpty ? "Load this Form" : option.title)
    }

    /// Loading a Form IS selecting it: the prompt fills the editor (editable),
    /// and the knowledge-graph lambda charts three more routes from it once. With
    /// no chevrons, the cycler always shows the newest trio — selecting walks the
    /// route forward, and the fresh trio auto-advances into view.
    private func selectFormOption(_ option: LensFrameFormOption) {
        prompt = option.prompt
        activeFormOptionId = option.id
        guard let onExpandFormOption,
              !expandedFormOptionIds.contains(option.id),
              !isExpandingFormOptions else {
            return
        }
        let styleFitLine = isStyleDisabled ? nil : currentStyleSlot?.label.trimmed.nilIfEmpty
        isExpandingFormOptions = true
        Task {
            let trio = await onExpandFormOption(option, styleFitLine)
            isExpandingFormOptions = false
            if !trio.isEmpty {
                expandedFormOptionIds.insert(option.id)
                formPages.append(trio)
                activeFormPage = formPages.count - 1
            }
        }
    }

    private func stackOption(
        title: String,
        detail: String,
        stack: RenderStack
    ) -> some View {
        let isSelected = selectedStackIds.contains(stack.id)
        let credentialBlocker = credentialBlocker(for: stack)
        return VStack(alignment: .leading, spacing: 6) {
            if let credentialBlocker {
                stackRowChrome(title: title, detail: detail, isSelected: false, isLocked: true, capacityHint: stackCapacityHint(stack)) {
                    HStack(spacing: 2) {
                        Text("NEEDS API KEY —")
                            .font(PlateType.label(7.5, weight: .bold))
                            .kerning(0.45)
                            .foregroundStyle(PlateColor.inkFaint)
                            .lineLimit(1)
                        Button {
                            onCancel()
                            onOpenAppSettings?()
                        } label: {
                            Text("ADD NOW")
                                .font(PlateType.label(7.5, weight: .bold))
                                .kerning(0.45)
                                .foregroundStyle(PlateColor.ink)
                                .underline()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .help(credentialBlocker)
            } else {
                Button {
                    withAnimation(.easeOut(duration: 0.16)) {
                        hasUserPickedStack = true
                        toggleStackSelection(stack)
                    }
                } label: {
                    stackRowChrome(title: title, detail: detail, isSelected: isSelected, isLocked: false, capacityHint: stackCapacityHint(stack), capacityHintIsWarning: stackDropsPlannedReferences(stack)) {
                        // Checkbox, not radio: several stacks check at once and
                        // each checked stack renders its own frame in parallel.
                        RoundedRectangle(cornerRadius: 2)
                            .strokeBorder(PlateColor.ink, lineWidth: 1)
                            .background(
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(isSelected ? PlateColor.ink : Color.clear)
                                    .padding(2.5)
                            )
                            .frame(width: 11, height: 11)
                    }
                }
                .buttonStyle(.plain)
                .help(isSelected
                    ? "\(stack.label) renders one of this submit's frames — click to drop it"
                    : "Add \(stack.label) — every checked stack renders its own frame in parallel")
            }
            if isSelected && credentialBlocker == nil {
                stackControls(stack)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private func toggleStackSelection(_ stack: RenderStack) {
        if selectedStackIds.contains(stack.id) {
            selectedStackIds.remove(stack.id)
        } else {
            selectedStackIds.insert(stack.id)
            seedDebugParametersIfNeeded(stack)
        }
    }

    /// The stack row's one-glance reference capacity: how many planned images
    /// this stack can carry, before the user commits to it.
    private func stackCapacityHint(_ stack: RenderStack) -> String {
        switch stack.frameReferenceCapacity {
        case .textOnly: "text-only"
        case .slots(let count): "refs · \(min(max(count, 0), FrameReferenceCapacity.attachmentBudget))"
        case .compositeSheet: "refs · sheet"
        case .budget: "refs · \(FrameReferenceCapacity.attachmentBudget)"
        }
    }

    /// True when picking this stack would DROP the currently planned
    /// references — the hint turns rust to say so before the click.
    private func stackDropsPlannedReferences(_ stack: RenderStack) -> Bool {
        stack.frameReferenceCapacity.planningCap == 0 && plannedReferenceCount > 0
    }

    /// Planned references are stack-independent: seed (clip moment OR
    /// variation/restyle template) + direct + mentions.
    private var plannedReferenceCount: Int {
        (seedPromptAttachment != nil ? 1 : 0)
            + referenceItems.count
            + mentionResolution.mentions.count
    }

    private func stackRowChrome<Trailing: View>(
        title: String,
        detail: String,
        isSelected: Bool,
        isLocked: Bool,
        capacityHint: String? = nil,
        capacityHintIsWarning: Bool = false,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .center, spacing: 9) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(PlateType.label(11, weight: .semibold))
                    .foregroundStyle(isLocked ? PlateColor.ink.opacity(0.4) : PlateColor.ink)
                Text(detail)
                    .font(PlateType.label(8.5))
                    .kerning(0.25)
                    .foregroundStyle(PlateColor.inkFaint)
                    .lineLimit(2)
                if let capacityHint {
                    Text(capacityHint)
                        .font(PlateType.figure(7.5))
                        .foregroundStyle(capacityHintIsWarning ? CanonColor.rust : PlateColor.inkFaint)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(isSelected ? PlateColor.creamDeep : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(isSelected ? PlateColor.ink : PlateColor.hairline, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 3))
    }

    private func stackControls(_ stack: RenderStack) -> some View {
        let providerMode = providerStyleMode(for: stack)
        let debugError = stack.isFAL
            ? FALImageClient.validateDebugParameters(debugParameters(for: stack), stack: stack, styleMode: providerMode)
            : ""
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 6) {
                PlateLabel(text: "Style Mode", size: 7.5, weight: .bold, color: PlateColor.inkFaint)
                Spacer()
                if stack.isFAL {
                    Text(stack.falModelId(styleMode: providerMode))
                        .font(PlateType.figure(7.5))
                        .foregroundStyle(PlateColor.ink.opacity(0.42))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
            styleModeControl(stack)
            if stack.isFAL {
                PlateLabel(text: "Parameters", size: 7.5, weight: .bold, color: PlateColor.inkFaint)
                    .padding(.top, 2)
                TextEditor(text: debugParametersBinding(for: stack))
                    .font(.system(size: 9.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(PlateColor.ink)
                    .scrollContentBackground(.hidden)
                    .frame(height: 104)
                    .padding(5)
                    .background(RoundedRectangle(cornerRadius: 3).fill(PlateColor.creamDeep.opacity(0.65)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(debugError.isEmpty ? PlateColor.hairline : PlateColor.ink.opacity(0.8), lineWidth: 1)
                    )
                if !debugError.isEmpty {
                    Text(debugError)
                        .font(PlateType.label(9.5))
                        .foregroundStyle(PlateColor.ink.opacity(0.85))
                        .italic()
                        .lineLimit(3)
                }
            }
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 3).fill(PlateColor.creamDeep.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(PlateColor.hairlineFaint, lineWidth: 1))
    }

    private func styleModeControl(_ stack: RenderStack) -> some View {
        let selected = effectiveStyleMode(for: stack)
        return HStack(spacing: 4) {
            ForEach(styleModeOptions(for: stack), id: \.self) { mode in
                Button {
                    styleModeByStack[stack.id] = mode
                    if stack.isFAL {
                        debugParametersByStack[stack.id] = stack.falDebugParameterTemplate(
                            mediaPlan: lens.body.resolvedMediaPlan,
                            styleMode: providerStyleMode(for: stack, selectedStyleMode: mode)
                        )
                    }
                } label: {
                    Text(mode.shortLabel)
                        .font(PlateType.label(9.5, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(selected == mode ? PlateColor.cream : PlateColor.ink.opacity(0.72))
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 2)
                                .fill(selected == mode ? PlateColor.ink : PlateColor.cream.opacity(0.6))
                        )
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(PlateColor.hairline, lineWidth: 0.75))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func blockerNotice(_ reason: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "clock")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(PlateColor.ink)
                .padding(.top, 1)
            Text(reason)
                .font(PlateType.label(9.5))
                .foregroundStyle(PlateColor.ink.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(PlateColor.hairline, lineWidth: 1))
    }

    // MARK: - Style state

    private var styleSelectionStatus: String {
        if isStyleDisabled { return "Selected — No style" }
        if let styleOverrideSlot {
            let label = styleOverrideSlot.label.trimmed.isEmpty ? styleOverrideSlot.styleId : styleOverrideSlot.label
            return "Selected — \(label)"
        }
        if let inheritedStyleSlot {
            let label = inheritedStyleSlot.label.trimmed.isEmpty ? inheritedStyleSlot.styleId : inheritedStyleSlot.label
            return "Using seed style — \(label)"
        }
        return "Turn the dial to choose a style, or render without style guidance."
    }

    private var currentStyleSlot: LensStyleTreatmentSlot? {
        if isStyleDisabled { return nil }
        return styleOverrideSlot ?? inheritedStyleSlot
    }

    /// One line naming what this creator run makes — the header's honesty line.
    private var headerContextLabel: String {
        switch context {
        case .blankFrame(let category):
            return "New Frame · \(category.title)"
        case .variation(let image):
            return "Variation of \(image.label.trimmed.isEmpty ? "this frame" : image.label)"
        case .restyle(let image):
            return "Restyle \(image.label.trimmed.isEmpty ? "this frame" : image.label)"
        case .groupTake(let groupName, _):
            return "Take · \(groupName)"
        case .plannedFrame(let image):
            let title = image.label.components(separatedBy: " · ").first?.trimmed ?? ""
            return "Planned Frame · \(title.isEmpty ? "this frame" : title)"
        case .clipMoment(let seed):
            switch seed.intent {
            case .continueFrom:
                return "Continue · \(seed.clipFilename)"
            case .precede:
                return "Before · \(seed.clipFilename)"
            case .transform:
                return "Transform · \(seed.clipFilename)"
            }
        case .stageFrame(_, let appendToCutId):
            return appendToCutId == nil ? "New Frame · Stage" : "New Frame · Cut"
        case .shotFrame(let appendToShotId):
            return appendToShotId == nil ? "New Frame · Source Material" : "New Frame · Shot"
        }
    }

    private var submitButtonTitle: String {
        let count = selectedStacks.count
        if case .plannedFrame = context {
            return count > 1 ? "Render Planned Frame · \(count) Stacks" : "Render Planned Frame"
        }
        return count > 1 ? "Render \(count) Frames" : "Render Frame"
    }

    private var inheritedStyleSlot: LensStyleTreatmentSlot? {
        guard let templateImage else {
            // Blank frames seed from the lens's primary style.
            return lens.body.styleTreatment?.primary?.normalized()
        }
        let preferredId = templateImage.sourceAestheticIds.first ?? ""
        let authority = templateImage.styleAuthorities
            .map { $0.normalized() }
            .first { !$0.referenceId.isEmpty && $0.referenceId == preferredId }
            ?? templateImage.styleAuthorities.first?.normalized()
        if let authority, !authority.referenceId.isEmpty {
            return LensStyleTreatmentSlot(
                styleId: authority.referenceId,
                label: authority.title,
                collection: "",
                hueHex: "",
                url: authority.imageUrl.isEmpty ? authority.imagePath : authority.imageUrl,
                weight: 100
            ).normalized()
        }
        return lens.body.styleTreatment?.primary?.normalized()
    }

    private func selectNoStyle() {
        isStyleDisabled = true
        styleOverrideSlot = nil
        styleOverrideCatalogVersion = ""
        styleModeByStack = [:]
        debugParametersByStack = [:]
    }

    private func resetToSeedStyle() {
        isStyleDisabled = false
        styleOverrideSlot = nil
        styleOverrideCatalogVersion = ""
        styleModeByStack = [:]
        debugParametersByStack = [:]
    }

    // MARK: - Stack helpers (ported from the retired composer)

    private func credentialBlocker(for stack: RenderStack) -> String? {
        switch stack.credentialProvider {
        case .openAI:
            return hasOpenAICredential ? nil : "Add an OpenAI API key in App Settings."
        case .civitai:
            return hasCivitaiCredential ? nil : "Add a CivitAI API key in App Settings."
        case .fal:
            if !hasFALCredential { return "Add a FAL API key in App Settings." }
            // The OpenAI key only serves the prompt rewrite — verbatim mode
            // removes the requirement (the engine gate consults the same flag).
            if isPromptTransformEnabled, !hasOpenAICredential {
                return "Add an OpenAI API key for prompt writing — or turn off Transform prompt."
            }
            return nil
        case .stability:
            if !hasStabilityCredential { return "Add a Stability AI API key in App Settings." }
            if isPromptTransformEnabled, !hasOpenAICredential {
                return "Add an OpenAI API key for prompt writing — or turn off Transform prompt."
            }
            return nil
        default:
            return "\(stack.credentialProvider.label) key gating is not supported for render stacks."
        }
    }

    private func startBlocker(for stack: RenderStack) -> String? {
        if prompt.trimmed.isEmpty { return "A Form prompt is required." }
        if let credentialBlocker = credentialBlocker(for: stack) { return credentialBlocker }
        let styleMode = effectiveStyleMode(for: stack)
        if styleMode == .attachStyleImage, currentStyleSlot == nil {
            return "Choose a style before attaching a style image."
        }
        if stack.isFAL {
            let debugError = FALImageClient.validateDebugParameters(
                debugParameters(for: stack),
                stack: stack,
                styleMode: providerStyleMode(for: stack)
            )
            if !debugError.isEmpty { return debugError }
        }
        return nil
    }

    private func styleModeOptions(for stack: RenderStack) -> [LensRenderStyleMode] {
        if isStyleDisabled { return [.none] }
        guard currentStyleSlot != nil else { return [.none] }
        var modes: [LensRenderStyleMode] = [.none, .describeStyleInPrompt]
        if stack.styleImageAttachSupported {
            modes.append(.attachStyleImage)
        }
        return modes
    }

    private func effectiveStyleMode(for stack: RenderStack) -> LensRenderStyleMode {
        if isStyleDisabled { return .none }
        let fallback: LensRenderStyleMode = currentStyleSlot == nil ? .none : .describeStyleInPrompt
        let selected = styleModeByStack[stack.id] ?? fallback
        return styleModeOptions(for: stack).contains(selected) ? selected : fallback
    }

    private func providerStyleMode(for stack: RenderStack, selectedStyleMode: LensRenderStyleMode? = nil) -> LensRenderStyleMode {
        selectedStyleMode ?? effectiveStyleMode(for: stack)
    }

    private func debugParameters(for stack: RenderStack) -> String {
        debugParametersByStack[stack.id] ?? stack.falDebugParameterTemplate(
            mediaPlan: lens.body.resolvedMediaPlan,
            styleMode: providerStyleMode(for: stack)
        )
    }

    private func debugParametersBinding(for stack: RenderStack) -> Binding<String> {
        Binding(
            get: { debugParameters(for: stack) },
            set: { debugParametersByStack[stack.id] = $0 }
        )
    }

    private func seedDebugParametersIfNeeded(_ stack: RenderStack) {
        guard stack.isFAL, debugParametersByStack[stack.id] == nil else { return }
        debugParametersByStack[stack.id] = stack.falDebugParameterTemplate(
            mediaPlan: lens.body.resolvedMediaPlan,
            styleMode: providerStyleMode(for: stack)
        )
    }

    // MARK: - Submit

    /// Submit is async-shaped: mentioned entries with ≥2 references and no composite
    /// sheet get one built first (so the renders attach one labeled sheet instead of
    /// loose images), then ONE batch goes out — a request per selected stack, in
    /// stack-list order. `isPreparingAttachments` guards double-submit while
    /// builds run.
    private func submitSelected() {
        let stacks = selectedStacks
        guard !stacks.isEmpty, !isPreparingAttachments else { return }
        isPreparingAttachments = true
        Task {
            var sheetOverrides: [String: MediaItemRecord] = [:]
            if let onEnsureMentionSheet, stacks.contains(where: \.reframeCapable) {
                for entry in mentionResolution.mentions {
                    let plan = mentionAttachmentPlan(for: entry)
                    guard !plan.usesSheet, plan.items.count >= 2 else { continue }
                    if let sheet = await onEnsureMentionSheet(entry) {
                        sheetOverrides[entry.id] = sheet
                    }
                }
            }
            onSubmit(stacks.map { buildRenderRequest($0, sheetOverrides: sheetOverrides) })
            isPreparingAttachments = false
        }
    }

    /// One stack's request from the shared plate state — per-stack style mode,
    /// FAL parameters, and attachment capacity all resolve here.
    private func buildRenderRequest(_ stack: RenderStack, sheetOverrides: [String: MediaItemRecord]) -> LensNewTakeRenderRequest {
        let styleMode = effectiveStyleMode(for: stack)
        let debugJSON = stack.isFAL ? debugParameters(for: stack) : ""
        let submittedStyleCatalogVersion = styleOverrideCatalogVersion.trimmed.nilIfEmpty
            ?? stylePickerCatalogVersion.trimmed
        let influences = selectedMoodInfluences
        // @mentions become their plain roster names in the submitted prompt; their
        // effect rides as reference-image attachments with character/object manifest
        // descriptors.
        let resolution = mentionResolution
        // Blank frames have no template to inherit style from at render time, so the
        // effective slot (wheel pick or lens-primary seed) must ride as an explicit
        // override — otherwise the engine would silently drop the style this modal
        // shows. Keep this switch exhaustive over FrameCreationContext.
        let submittedStyleSlot: LensStyleTreatmentSlot?
        switch context {
        case .blankFrame, .clipMoment, .stageFrame, .shotFrame:
            // No template to inherit from at render time — the shown style
            // must ride as an explicit override.
            submittedStyleSlot = isStyleDisabled ? nil : currentStyleSlot
        case .variation, .restyle, .groupTake, .plannedFrame:
            submittedStyleSlot = isStyleDisabled ? nil : styleOverrideSlot
        }
        // Seed leads, direct references follow, mentions last — one merge law
        // shared with the reference well's live preview.
        let combinedAttachments = attachmentMerge(
            for: stack,
            resolution: resolution,
            sheetOverrides: sheetOverrides
        ).plan.attachments
        return LensNewTakeRenderRequest(
            stack: stack,
            styleMode: styleMode,
            prompt: resolution.cleanedPrompt,
            authoredPrompt: prompt,
            label: "",
            debugParametersJSON: debugJSON,
            promptImageAttachment: nil,
            promptImageAttachments: combinedAttachments.isEmpty ? nil : combinedAttachments,
            moodInfluences: influences.isEmpty ? nil : influences,
            medium: selectedMedium?.rawValue,
            styleOverrideSlot: submittedStyleSlot,
            styleOverrideCatalogVersion: submittedStyleSlot == nil ? "" : submittedStyleCatalogVersion,
            promptEnrichmentDisabled: isPromptTransformEnabled ? nil : true,
            stabilityStrength: stack.isStability ? stabilityReferenceStrength : nil
        )
    }

    // MARK: - Shared bits

    private func attachmentPath(for item: MediaItemRecord) -> String {
        if !item.path.trimmed.isEmpty {
            return item.path
        }
        return item.thumbnailPath
    }

    private func displayPath(for item: MediaItemRecord) -> String {
        if !item.thumbnailPath.trimmed.isEmpty {
            return item.thumbnailPath
        }
        return item.path
    }

    private func plateThumbnail(path: String) -> some View {
        ZStack {
            PlateColor.creamDeep
            if let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(PlateColor.inkFaint)
            }
        }
        .clipped()
    }

    /// Like `plateThumbnail` but fitted rather than filled — for surfaces whose
    /// job is to show the whole image, where a crop would hide the subject.
    private func plateFittedImage(path: String) -> some View {
        ZStack {
            if let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(PlateColor.inkFaint)
            }
        }
    }

    /// A style slot's reference image — remote catalog URL or a local seed path.
    @ViewBuilder
    private func styleSlotImage(_ slot: LensStyleTreatmentSlot) -> some View {
        let source = slot.url.trimmed
        if source.hasPrefix("http"), let url = URL(string: source) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    PlateColor.creamDeep
                }
            }
            .clipped()
        } else if !source.isEmpty {
            plateThumbnail(path: source)
        } else {
            PlateColor.creamDeep
        }
    }

    private static func seedPrompt(from image: ProjectLensHeroImage) -> String {
        let sourcePrompt = image.sourcePrompt.trimmed
        if !sourcePrompt.isEmpty { return sourcePrompt }
        return image.prompt.trimmed
    }

    nonisolated static func romanNumeral(_ value: Int) -> String {
        let numerals = ["0", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]
        guard value >= 0, value < numerals.count else { return "\(value)" }
        return numerals[value]
    }
}

// MARK: - Prompt editor

/// A one-shot selection request used after mention completion. The id lets the
/// representable distinguish a new request from ordinary SwiftUI updates.
private struct FramePromptCaretRequest: Equatable {
    let id = UUID()
    var utf16Offset: Int
}

/// AppKit-backed editor for caret geometry and mention-picker keyboard control.
/// The prompt remains a plain String binding; this bridge only exposes editor
/// behavior SwiftUI's TextEditor does not currently surface on macOS.
private struct FrameCreatorPromptTextEditor: NSViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var text: String
    var caretRequest: FramePromptCaretRequest?
    var isMentionPickerPresented: Bool
    var onCaretChange: (Int, CGPoint) -> Void
    var onFocusChange: (Bool) -> Void
    var onPickerMove: (Int) -> Void
    var onPickerSelect: () -> Bool
    var onPickerDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder

        let textView = FrameCreatorPromptNSTextView()
        textView.delegate = context.coordinator
        textView.owner = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        let systemFont = NSFont.systemFont(ofSize: 11.5, weight: .regular)
        let serifDescriptor = systemFont.fontDescriptor.withDesign(.serif) ?? systemFont.fontDescriptor
        textView.font = NSFont(descriptor: serifDescriptor, size: 11.5)
        textView.textColor = NSColor(PlateColor.ink)
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView
        context.coordinator.scrollView = scrollView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.scrollView = scrollView
        guard let textView = scrollView.documentView as? FrameCreatorPromptNSTextView else { return }
        textView.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        textView.textColor = NSColor(PlateColor.ink)

        if textView.string != text {
            textView.string = text
            let end = textView.string.utf16.count
            textView.setSelectedRange(NSRange(location: end, length: 0))
        }

        if let caretRequest,
           caretRequest.id != context.coordinator.lastCaretRequestId {
            context.coordinator.lastCaretRequestId = caretRequest.id
            let offset = min(max(caretRequest.utf16Offset, 0), textView.string.utf16.count)
            textView.setSelectedRange(NSRange(location: offset, length: 0))
            textView.scrollRangeToVisible(NSRange(location: offset, length: 0))
            if textView.window?.firstResponder !== textView {
                textView.window?.makeFirstResponder(textView)
            }
            DispatchQueue.main.async {
                context.coordinator.reportCaret(in: textView)
            }
        }
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: FrameCreatorPromptTextEditor
        weak var scrollView: NSScrollView?
        var lastCaretRequestId: UUID?

        init(_ parent: FrameCreatorPromptTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            reportCaret(in: textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            reportCaret(in: textView)
        }

        func textDidBeginEditing(_ notification: Notification) {
            parent.onFocusChange(true)
            if let textView = notification.object as? NSTextView {
                reportCaret(in: textView)
            }
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.onFocusChange(false)
        }

        func handleKeyDown(_ event: NSEvent) -> Bool {
            guard parent.isMentionPickerPresented else { return false }
            let disallowedModifiers = event.modifierFlags.intersection([.command, .control, .option])
            guard disallowedModifiers.isEmpty else { return false }
            switch event.keyCode {
            case 125:
                parent.onPickerMove(1)
                return true
            case 126:
                parent.onPickerMove(-1)
                return true
            case 36, 48, 76:
                return parent.onPickerSelect()
            case 53:
                parent.onPickerDismiss()
                return true
            default:
                return false
            }
        }

        func reportCaret(in textView: NSTextView) {
            guard let scrollView,
                  let window = textView.window else { return }
            let offset = min(textView.selectedRange().location, textView.string.utf16.count)
            let screenRect = textView.firstRect(
                forCharacterRange: NSRange(location: offset, length: 0),
                actualRange: nil
            )
            let windowPoint = window.convertPoint(fromScreen: screenRect.origin)
            let localPoint = scrollView.convert(windowPoint, from: nil)
            let anchor = CGPoint(
                x: max(0, localPoint.x),
                y: max(0, scrollView.bounds.height - localPoint.y)
            )
            parent.onCaretChange(offset, anchor)
        }
    }
}

private final class FrameCreatorPromptNSTextView: NSTextView {
    weak var owner: FrameCreatorPromptTextEditor.Coordinator?

    override func keyDown(with event: NSEvent) {
        if owner?.handleKeyDown(event) == true { return }
        super.keyDown(with: event)
    }
}

// MARK: - Style wheel

/// The rotating style-catalog dial: one collection at a time on a graduated
/// ring; tapping a style spins the ring (shortest arc) until that style rests
/// under the fixed pointer at 9 o'clock, feeding the Frame square to its left.
private struct FrameCreatorStyleWheel: View {
    let selectedStyleId: String?
    let isStyleDisabled: Bool
    let statusText: String
    let showsSeedReset: Bool
    var onPreviewStyle: (StyleImagePreviewRequest) -> Void
    var onCatalogLoaded: (String) -> Void
    var onSelectStyle: (StyleBrowseStyle, String) -> Void
    var onSelectNoStyle: () -> Void
    var onResetToSeed: () -> Void

    @State private var catalog = StyleBrowseCatalog.empty
    @State private var isLoading = false
    @State private var loadError = ""
    @State private var selectedCollectionKey = ""
    @State private var ringRotationDegrees: Double = 0
    @State private var ringPage = 0

    /// Fixed pointer bearing: 9 o'clock (0° = 12 o'clock, clockwise).
    private let pointerAngleDegrees: Double = 270
    private let stylesPerPage = 15
    /// The selected thumb pops above its neighbors so the pointer position reads instantly.
    private let selectedThumbScale: CGFloat = 1.3

    private func thumbSize(for diameter: CGFloat) -> CGFloat {
        // Big and stable: a generous floor so small windows don't shrink the
        // circles, scaling up on large wheels.
        min(184, max(128, diameter * 0.125))
    }

    private enum RingEntry: Identifiable {
        case noStyle
        case style(StyleBrowseStyle)

        var id: String {
            switch self {
            case .noStyle: return "no_style"
            case .style(let style): return style.id
            }
        }
    }

    var body: some View {
        GeometryReader { geo in
            let diameter = max(420, min(geo.size.width, geo.size.height) - 28)
            let thumb = thumbSize(for: diameter)
            // Both tracks ride near the outer border (thumbs straddle the border ring —
            // no info lost, it's a hairline); the stagger gap is small so the inner track
            // sits just below the outer one rather than sagging toward center.
            let outerRadius = diameter / 2 - thumb * 0.42
            let innerRadius = outerRadius - thumb * 0.42
            // The 9-o'clock station (selected thumb pop + pointer) is the dial's
            // left extremity; keep it inside this region so no interactive wheel
            // geometry floats invisibly over the options column to the left.
            let leftStationExtent = outerRadius + (thumb * selectedThumbScale) / 2 + 14 + 30
            ZStack {
                dialChrome(diameter: diameter)
                if diameter >= 560 {
                    collectionRing(diameter: diameter)
                }
                ringItems(thumb: thumb, outerRadius: outerRadius, innerRadius: innerRadius)
                noStyleKnob(outerRadius: outerRadius, thumb: thumb)
                hub(diameter: diameter)
                pointerStation(outerRadius: outerRadius, thumb: thumb)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .offset(x: max(0, leftStationExtent - geo.size.width / 2))
        }
        .overlay(alignment: .bottom) {
            wheelFooter
                .padding(.bottom, 12)
        }
        .task {
            await loadCatalog()
        }
    }

    // MARK: Dial chrome

    private func dialChrome(diameter: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(PlateColor.ink, lineWidth: 1)
                .frame(width: diameter, height: diameter)
            PlateTickRing(tickCount: 240, majorEvery: 10, minorLength: 4, majorLength: 9)
                .stroke(PlateColor.ink.opacity(0.7), lineWidth: 0.6)
                .frame(width: diameter - 6, height: diameter - 6)
            Circle()
                .stroke(PlateColor.hairline, lineWidth: 0.75)
                .frame(width: diameter - 26, height: diameter - 26)
            PlateTickRing(tickCount: 60, majorEvery: 5, minorLength: 3, majorLength: 6)
                .stroke(PlateColor.hairline, lineWidth: 0.5)
                .frame(width: diameter * 0.56, height: diameter * 0.56)
            Circle()
                .stroke(PlateColor.hairline, lineWidth: 0.75)
                .frame(width: diameter * 0.50, height: diameter * 0.50)
        }
    }

    private func pointerStation(outerRadius: CGFloat, thumb: CGFloat) -> some View {
        PlatePointer()
            .fill(PlateColor.ink)
            .frame(width: 30, height: 18)
            .offset(x: -(outerRadius + (thumb * selectedThumbScale) / 2 + 14))
            // Pure decoration — it overhangs the dial's left edge and must never
            // swallow clicks meant for whatever sits beneath it.
            .allowsHitTesting(false)
    }

    // MARK: Collection ring

    /// Static ring of collection names between the hub and the thumb tracks;
    /// the current collection reads active, and each name jumps straight there.
    private func collectionRing(diameter: CGFloat) -> some View {
        let collections = catalog.displayCollections
        let radius = diameter * 0.25
        let fontSize: CGFloat = collections.count > 10 ? 7.5 : 9
        return ZStack {
            ForEach(Array(collections.enumerated()), id: \.element.key) { index, collection in
                let angle = Double(index) / Double(max(collections.count, 1)) * 2 * .pi
                collectionRingLabel(collection, fontSize: fontSize)
                    .offset(x: sin(angle) * radius, y: -cos(angle) * radius)
            }
        }
    }

    private func collectionRingLabel(_ collection: StyleBrowseCollection, fontSize: CGFloat) -> some View {
        let isActive = collection.key == selectedCollectionKey
        return Button {
            selectCollection(collection.key)
        } label: {
            VStack(spacing: 3) {
                Text(collection.name.uppercased())
                    .font(PlateType.label(fontSize, weight: isActive ? .semibold : .regular))
                    .kerning(fontSize * 0.14)
                    .foregroundStyle(isActive ? PlateColor.ink : PlateColor.inkFaint)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: 80)
                if isActive {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(canonColor(fromHex: collection.dotColorHex.trimmed, fallback: PlateColor.ink))
                            .frame(width: 5, height: 5)
                            .overlay(Circle().stroke(PlateColor.ink, lineWidth: 0.5))
                        Rectangle().fill(PlateColor.ink).frame(width: 22, height: 0.75)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(collection.description.trimmed.isEmpty ? collection.name : collection.description)
    }

    // MARK: Ring

    private var currentStyles: [StyleBrowseStyle] {
        catalog.styles(in: selectedCollectionKey)
    }

    private var pageCount: Int {
        max(1, Int(ceil(Double(currentStyles.count) / Double(stylesPerPage))))
    }

    /// Styles only — the No-style option is pinned at the top and does not rotate.
    private var ringEntries: [RingEntry] {
        let styles = currentStyles
        let start = min(ringPage * stylesPerPage, max(0, styles.count - 1))
        let slice = styles.isEmpty ? [] : Array(styles[start..<min(start + stylesPerPage, styles.count)])
        return slice.map { .style($0) }
    }

    /// Fixed at 12 o'clock, above the rotating ring — the one dial element that
    /// never moves. Opaque fill so any style rotating behind it is occluded.
    private func noStyleKnob(outerRadius: CGFloat, thumb: CGFloat) -> some View {
        Button {
            onSelectNoStyle()
        } label: {
            ZStack {
                Circle().fill(PlateColor.cream)
                Image(systemName: "slash.circle")
                    .font(.system(size: thumb * 0.28, weight: .medium))
                    .foregroundStyle(PlateColor.inkFaint)
            }
            .frame(width: thumb, height: thumb)
            .overlay(Circle().stroke(PlateColor.ink, lineWidth: isStyleDisabled ? 1.6 : 0.8))
            .overlay(
                Circle()
                    .stroke(PlateColor.ink, lineWidth: isStyleDisabled ? 0.75 : 0)
                    .padding(-4)
            )
        }
        .buttonStyle(.plain)
        .help("No style — render prompt-only")
        .offset(y: -outerRadius)
        .zIndex(2)
    }

    private func baseAngle(index: Int, count: Int) -> Double {
        Double(index) / Double(max(count, 1)) * 360
    }

    /// Thumbs alternate between an outer and inner track so neighbors clear
    /// each other at the larger size; angle math is unchanged from one track.
    private func ringItems(thumb: CGFloat, outerRadius: CGFloat, innerRadius: CGFloat) -> some View {
        let entries = ringEntries
        return ZStack {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                let base = baseAngle(index: index, count: entries.count)
                let radius = index.isMultiple(of: 2) ? outerRadius : innerRadius
                ringThumb(entry, thumb: thumb)
                    .rotationEffect(.degrees(-(base + ringRotationDegrees)))
                    .offset(y: -radius)
                    .rotationEffect(.degrees(base))
                    .zIndex(isSelected(entry) ? 1 : 0)
            }
        }
        .rotationEffect(.degrees(ringRotationDegrees))
    }

    private func isSelected(_ entry: RingEntry) -> Bool {
        switch entry {
        case .noStyle:
            return isStyleDisabled
        case .style(let style):
            return !isStyleDisabled && style.id == selectedStyleId
        }
    }

    private func ringThumb(_ entry: RingEntry, thumb: CGFloat) -> some View {
        let isSelected = isSelected(entry)
        return Button {
            select(entry)
        } label: {
            ZStack {
                Circle().fill(PlateColor.creamDeep)
                switch entry {
                case .noStyle:
                    Image(systemName: "slash.circle")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(PlateColor.inkFaint)
                case .style(let style):
                    AsyncImage(url: URL(string: style.url)) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        case .failure:
                            Image(systemName: "photo")
                                .font(.system(size: 14))
                                .foregroundStyle(PlateColor.inkFaint)
                        default:
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
            }
            .frame(width: thumb, height: thumb)
            .clipShape(Circle())
            .overlay(Circle().stroke(PlateColor.ink, lineWidth: isSelected ? 1.6 : 0.8))
            .overlay(
                Circle()
                    .stroke(PlateColor.ink, lineWidth: isSelected ? 0.75 : 0)
                    .padding(-4)
            )
            .overlay(alignment: .bottom) {
                if case .style(let style) = entry, isSelected {
                    Circle()
                        .fill(canonColor(fromHex: style.hueHex.trimmed, fallback: PlateColor.ink))
                        .frame(width: 7, height: 7)
                        .overlay(Circle().stroke(PlateColor.cream, lineWidth: 1))
                        .offset(y: 2)
                }
            }
            .scaleEffect(isSelected ? selectedThumbScale : 1)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isSelected)
        }
        .buttonStyle(.plain)
        .help(ringThumbHelp(entry))
        .contextMenu {
            if case .style(let style) = entry {
                Button("Preview style") {
                    onPreviewStyle(StyleImagePreviewRequest(url: style.url, label: style.displayLabel, detail: style.medium))
                }
            }
        }
    }

    private func ringThumbHelp(_ entry: RingEntry) -> String {
        switch entry {
        case .noStyle:
            return "No style — render prompt-only"
        case .style(let style):
            let caption = style.caption.trimmed
            return caption.isEmpty ? style.displayLabel : "\(style.displayLabel) — \(caption)"
        }
    }

    private func select(_ entry: RingEntry) {
        rotate(toEntryId: entry.id)
        switch entry {
        case .noStyle:
            onSelectNoStyle()
        case .style(let style):
            onSelectStyle(style, catalog.version)
        }
    }

    private func rotate(toEntryId entryId: String, animated: Bool = true) {
        let entries = ringEntries
        guard let index = entries.firstIndex(where: { $0.id == entryId }) else { return }
        let target = pointerAngleDegrees - baseAngle(index: index, count: entries.count)
        var delta = (target - ringRotationDegrees).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        guard delta != 0 else { return }
        if animated {
            withAnimation(.spring(response: 0.65, dampingFraction: 0.85)) {
                ringRotationDegrees += delta
            }
        } else {
            ringRotationDegrees += delta
        }
    }

    // MARK: Hub

    private func hub(diameter: CGFloat) -> some View {
        let hubDiameter = diameter * 0.40
        return ZStack {
            Circle().fill(PlateColor.cream)
            Circle().stroke(PlateColor.ink, lineWidth: 1)
            if isLoading {
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    PlateLabel(text: "Consulting the catalog", size: 8, color: PlateColor.inkFaint)
                }
            } else if !loadError.isEmpty {
                VStack(spacing: 8) {
                    Text(loadError)
                        .font(PlateType.label(9.5))
                        .foregroundStyle(PlateColor.ink.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                    Button("Retry") {
                        Task { await loadCatalog(force: true) }
                    }
                    .buttonStyle(PlateButtonStyle())
                }
                .padding(14)
            } else if let collection = currentCollection {
                VStack(spacing: 6) {
                    HStack(spacing: 14) {
                        hubChevron(systemName: "chevron.left") { cycleCollection(-1) }
                        VStack(spacing: 5) {
                            Circle()
                                .fill(canonColor(fromHex: collection.dotColorHex.trimmed, fallback: PlateColor.inkFaint))
                                .frame(width: 9, height: 9)
                                .overlay(Circle().stroke(PlateColor.ink, lineWidth: 0.5))
                            PlateLabel(text: collection.name, size: 10.5, weight: .semibold)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity)
                        hubChevron(systemName: "chevron.right") { cycleCollection(1) }
                    }
                    if pageCount > 1 {
                        HStack(spacing: 8) {
                            hubChevron(systemName: "chevron.left", small: true) { cyclePage(-1) }
                            Text("PAGE \(FrameCreatorModal.romanNumeral(ringPage + 1)) / \(FrameCreatorModal.romanNumeral(pageCount))")
                                .font(PlateType.figure(8))
                                .kerning(0.8)
                                .foregroundStyle(PlateColor.inkFaint)
                            hubChevron(systemName: "chevron.right", small: true) { cyclePage(1) }
                        }
                    }
                }
                .padding(.horizontal, 12)
            } else {
                PlateLabel(text: "No styles published", size: 9, color: PlateColor.inkFaint)
            }
        }
        .frame(width: hubDiameter, height: hubDiameter)
    }

    private func hubChevron(systemName: String, small: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: small ? 8 : 11, weight: .semibold))
                .foregroundStyle(PlateColor.ink.opacity(0.7))
                .frame(width: small ? 16 : 24, height: small ? 16 : 24)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var currentCollection: StyleBrowseCollection? {
        catalog.displayCollections.first { $0.key == selectedCollectionKey }
            ?? catalog.displayCollections.first
    }

    private func cycleCollection(_ delta: Int) {
        let collections = catalog.displayCollections
        guard !collections.isEmpty else { return }
        let currentIndex = collections.firstIndex { $0.key == selectedCollectionKey } ?? 0
        let nextIndex = (currentIndex + delta + collections.count) % collections.count
        selectCollection(collections[nextIndex].key)
    }

    private func selectCollection(_ key: String) {
        guard key != selectedCollectionKey else { return }
        selectedCollectionKey = key
        ringPage = 0
        alignCommittedSelectionIfVisible()
    }

    private func cyclePage(_ delta: Int) {
        guard pageCount > 1 else { return }
        ringPage = (ringPage + delta + pageCount) % pageCount
        alignCommittedSelectionIfVisible()
    }

    /// Browsing never clears the committed selection; if the selected style is
    /// on the ring we're now showing, swing it back under the pointer.
    private func alignCommittedSelectionIfVisible() {
        guard let selectedStyleId, !isStyleDisabled else { return }
        if ringEntries.contains(where: { $0.id == selectedStyleId }) {
            rotate(toEntryId: selectedStyleId)
        }
    }

    // MARK: Footer

    private var wheelFooter: some View {
        HStack(spacing: 12) {
            Text(statusText)
                .font(PlateType.label(10, weight: .medium))
                .italic()
                .foregroundStyle(PlateColor.ink.opacity(0.72))
                .lineLimit(1)
            if showsSeedReset {
                Button("Seed Style") {
                    onResetToSeed()
                }
                .buttonStyle(PlateButtonStyle())
            }
            Link("Catalog terms", destination: LitScenesReleaseIdentity.catalogTermsURL)
                .font(PlateType.label(9))
                .foregroundStyle(PlateColor.inkFaint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 3).fill(PlateColor.cream.opacity(0.9)))
    }

    // MARK: Catalog

    private func loadCatalog(force: Bool = false) async {
        isLoading = true
        loadError = ""
        do {
            catalog = try await StyleBrowseCatalogRuntime.shared.loadCatalog(force: force)
            isLoading = false
            if selectedCollectionKey.isEmpty || !catalog.collections.contains(where: { $0.key == selectedCollectionKey }) {
                selectedCollectionKey = catalog.displayCollections.first?.key ?? ""
            }
            onCatalogLoaded(catalog.version)
        } catch {
            catalog = .empty
            isLoading = false
            loadError = "Style catalog unavailable: \(error.localizedDescription)"
        }
    }
}

/// Reports the height of the sheet's parent (document) window so the Frame
/// Creator can size to a share of the whole app, not just the pane that
/// presented it. Sheets are attached windows — `window.sheetParent` is the
/// document window we actually want to fill.
private struct FrameCreatorWindowHeightReader: NSViewRepresentable {
    var onChange: (CGFloat) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { report(from: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { report(from: nsView) }
    }

    private func report(from view: NSView) {
        guard let window = view.window else { return }
        let host = window.sheetParent ?? window
        let layoutHeight = host.contentLayoutRect.height
        let height = layoutHeight > 0 ? layoutHeight : host.frame.height
        if height > 0 {
            onChange(height)
        }
    }
}
