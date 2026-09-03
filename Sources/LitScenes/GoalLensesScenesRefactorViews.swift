import AppKit
import AVFoundation
import ImageIO
import SwiftUI

struct GoalV2WorkspaceView: View {
    @ObservedObject var library: LibraryEngine
    var onContinueToFrames: () -> Void
    var onAddMedia: () -> Void
    var onOpenAppSettings: () -> Void
    @Binding var dismissedReadinessBannerKeys: Set<String>

    @State private var draft = ProjectGoalBriefV2.empty()
    @State private var composerText = ""
    @State private var editingField: GoalV2Field?
    @State private var editText = ""
    @State private var editContentType: ProjectIntent?
    @State private var editRequiredEntities: [ProjectGoalRequiredEntity] = []
    @State private var goalCopyStatus = ""
    @State private var selectedMediaIds: [String] = []
    @State private var attachmentStatus = ""
    @State private var viewedVersionId: String?
    /// Which story service the next turn will use. Resolved on appearance and
    /// whenever hosted credentials change, so the Direct-mode note under the
    /// composer disappears the moment Hosted is configured.
    @State private var storyInferenceMode = StoryInferenceMode.resolved()
    @FocusState private var isFieldEditorFocused: Bool

    private static let proInterestDismissKey = "pro-interest"

    private enum GoalV2Field: String, CaseIterable, Identifiable {
        case contentType
        case goal
        case audience
        case desiredResponse
        case viewerExperience
        case successCriteria
        case constraints
        case requiredEntities
        case openQuestions
        case lensSeedSummary
        case lensSeedTerms

        var id: String { rawValue }

        var title: String {
            switch self {
            case .contentType: return "Content type"
            case .goal: return "Goal"
            case .audience: return "Audience"
            case .desiredResponse: return "Desired response"
            case .viewerExperience: return "Viewer experience"
            case .successCriteria: return "Success criteria"
            case .constraints: return "Constraints"
            case .requiredEntities: return "Required entities"
            case .openQuestions: return "Open questions"
            case .lensSeedSummary: return "Scene Plan seed summary"
            case .lensSeedTerms: return "Scene Plan seed terms"
            }
        }

        var placeholder: String {
            switch self {
            case .contentType: return "Unspecified"
            case .goal: return "What should this project accomplish?"
            case .audience: return "Who is this for?"
            case .desiredResponse: return "What should the viewer feel, do, or understand?"
            case .viewerExperience: return "What should watching it feel like?"
            case .successCriteria: return "One criterion per line"
            case .constraints: return "One constraint per line"
            case .requiredEntities: return "Only entities the user says must appear"
            case .openQuestions: return "One question per line"
            case .lensSeedSummary: return "Early visual seeds for FRAMES"
            case .lensSeedTerms: return "One seed term per line"
            }
        }

        var editorHeight: CGFloat {
            switch self {
            case .goal, .audience, .desiredResponse:
                return 52
            case .contentType:
                return 0
            case .requiredEntities:
                return 0
            default:
                return 96
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if library.creativeSchemaState.isIncompatible {
                CreativeResetBanner(library: library)
            } else {
                GoalMediaReadinessBanner(
                    library: library,
                    onAddMedia: onAddMedia,
                    onOpenAppSettings: onOpenAppSettings,
                    dismissedKeys: $dismissedReadinessBannerKeys
                )
            }
            GeometryReader { proxy in
                let railWidth = min(max(proxy.size.width * 0.25, 320), 440)
                let pairedWidth = max(proxy.size.width - railWidth - 2, 0)
                let chatWidth = pairedWidth / 2
                let storyWidth = pairedWidth - chatWidth
                HStack(alignment: .top, spacing: 0) {
                    goalChatPane
                        .frame(width: chatWidth, height: proxy.size.height)
                    Rectangle()
                        .fill(CanonColor.hairlinePaper)
                        .frame(width: 1)
                    goalFieldRail
                        .frame(width: railWidth, height: proxy.size.height)
                    Rectangle()
                        .fill(CanonColor.hairlinePaper)
                        .frame(width: 1)
                    ScenesWorkspaceView(
                        library: library,
                        onOpenAesthetic: onContinueToFrames,
                        isEmbeddedInStoryWorkspace: true
                    )
                    .frame(width: storyWidth, height: proxy.size.height)
                }
            }
        }
        .onAppear(perform: syncDraft)
        .onChange(of: library.projectGoalV2.activeVersionId) { _, _ in
            syncDraft()
        }
        .onChange(of: library.projectGoalV2.versions.count) { _, _ in
            syncDraft()
        }
        .background(CanonColor.paper)
        .tint(CanonColor.focusBlue)
        .environment(\.colorScheme, .light)
    }

    private var goalChatPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            goalChatHeader
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 14)

            Divider()

            ChatTranscriptView(
                turns: library.projectGoalV2.messages.map {
                    ChatTranscriptTurn(id: $0.messageId, isUser: $0.role == .user, text: $0.text, mediaIds: $0.mediaIds)
                },
                isThinking: library.isInterviewingGoal,
                thinkingLabel: "Updating Goal",
                bottomAnchorId: "goal-bottom",
                thinkingRowId: "goal-thinking-row",
                resolveMedia: library.mediaItems(for:)
            ) {
                goalEmptyConversation
            }

            goalComposer
                .padding(24)
                .background(CanonColor.paper)
        }
        .background(CanonColor.paper)
    }

    private var goalChatHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("STORY")
                    .font(CanonType.archive(12, weight: .semibold))
                    .foregroundStyle(CanonColor.muted)
                Text("Project intent conversation")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(CanonColor.ink)
            }
            Spacer()
            HStack(spacing: 8) {
                if !goalCopyStatus.isEmpty {
                    Text(goalCopyStatus)
                        .font(CanonType.interface(11, weight: .semibold))
                        .foregroundStyle(CanonColor.ink.opacity(0.58))
                }
                Button {
                    copyGoalConversation()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(CanonType.interface(12, weight: .semibold))
                        .frame(width: 15, height: 15)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.56), in: RoundedRectangle(cornerRadius: 7))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(CanonColor.hairlinePaper)
                                .allowsHitTesting(false)
                        )
                }
                .buttonStyle(.plain)
                .disabled(library.projectGoalV2.messages.isEmpty)
                .opacity(library.projectGoalV2.messages.isEmpty ? 0.44 : 1)
                .accessibilityLabel("Copy Goal conversation")
                .help(library.projectGoalV2.messages.isEmpty ? "No Goal conversation to copy" : "Copy Goal conversation")
            }
        }
    }

    private var goalEmptyConversation: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Start with what this project should do.")
                .font(CanonType.editorial(20, weight: .semibold))
                .foregroundStyle(CanonColor.ink)
            Text("Describe the viewer outcome, audience, maker intent, or world you want LitScenes to serve. The structured Goal fields update from the conversation and stay editable on the right.")
                .font(CanonType.editorial(14))
                .foregroundStyle(CanonColor.ink.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: 560, alignment: .leading)
        .background(CanonColor.paperInset.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(CanonColor.hairlinePaper)
        )
    }

    private var goalComposer: some View {
        VStack(alignment: .leading, spacing: 9) {
            ChatComposerView(
                text: $composerText,
                attachments: selectedGoalAttachments,
                placeholder: "Tell LitScenes what this project should accomplish. Paste or upload images as evidence. Cmd+Enter sends.",
                statusText: goalComposerStatusText,
                isWaiting: library.isInterviewingGoal,
                canSend: canSendMessage,
                onSend: sendMessage,
                onUpload: attachGoalImagesFromPicker,
                onRemoveAttachment: removeGoalAttachment,
                onPasteImageData: attachPastedGoalImage,
                onPasteFileURLs: attachGoalImageFiles,
                onDropMediaIds: attachExistingGoalMedia
            )

            if hasSavedGoalVersion {
                goalGoodEnoughCTA
            }
            if showsProInterestLine {
                ProComingSoonCard(face: .line, surface: .paper) {
                    dismissedReadinessBannerKeys.insert(Self.proInterestDismissKey)
                }
            }
        }
        .onAppear { storyInferenceMode = StoryInferenceMode.resolved() }
        .onChange(of: library.lensContextCredentialStatuses) { _, _ in
            storyInferenceMode = StoryInferenceMode.resolved()
        }
    }

    /// The Pro note shows only where the gap is real: Direct mode, in builds
    /// that carry the promotion, until dismissed for this launch.
    private var showsProInterestLine: Bool {
        LitScenesReleaseIdentity.current.showsProInterestPromotion
            && storyInferenceMode == .direct
            && !dismissedReadinessBannerKeys.contains(Self.proInterestDismissKey)
    }

    private var goalGoodEnoughCTA: some View {
        VStack(spacing: 4) {
            HStack(alignment: .center, spacing: 10) {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Good enough")
                        .font(CanonType.interface(12, weight: .semibold))
                }
                .foregroundStyle(goalGoodEnoughColor)
                goalPillButton("Continue to FRAMES", isPrimary: true, disabled: !canContinueToLenses) {
                    onContinueToFrames()
                }
                .help(canContinueToLenses ? "Continue to Frames" : goalContinueDisabledReason)
            }
            // The Continue gate only checks the Goal; Scene planning has its
            // own requirements. Say what Scenes will wait on rather than
            // letting the user land on an unexplained setup surface.
            if canContinueToLenses,
               library.projectLenses.lenses.isEmpty,
               let firstBlocker = library.lensGenerationBlockers.first {
                Text("Scenes will wait on: \(firstBlocker)")
                    .font(CanonType.interface(11))
                    .foregroundStyle(CanonColor.ink.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 3)
    }

    private var goalFieldRail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                goalMoodboardArticulationSection
                goalStyleTaxonomySection
                if isViewingActiveGoalVersion {
                    // Cast is not versioned with the brief — hide it while previewing
                    // an older Goal version rather than implying version-scoped cast.
                    GoalCastPanelView(library: library)
                }
                if shouldShowGoalReadinessCard {
                    goalReadinessCard
                }
                goalFieldActions
                ForEach(GoalV2Field.allCases) { field in
                    goalFieldCard(field)
                }
                goalVersionsSection
            }
            .padding(18)
        }
        .background(CanonColor.paperInset)
    }

    @ViewBuilder
    private var goalMoodboardArticulationSection: some View {
        let articulation = displayedBrief.moodboardArticulation.trimmed
        if !articulation.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    Text("Moodboard articulation")
                        .font(CanonType.interface(13, weight: .semibold))
                        .foregroundStyle(CanonColor.ink)
                    Text("read-only")
                        .font(CanonType.archive(9))
                        .foregroundStyle(CanonColor.ink.opacity(0.4))
                }
                Text(articulation)
                    .font(CanonType.editorial(13))
                    .foregroundStyle(CanonColor.ink.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CanonColor.paper.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(CanonColor.hairlinePaper)
            )
        }
    }

    private var displayedStyleTermRefs: [ProjectGoalStyleTermRef] {
        let refs = displayedBrief.styleTermRefs
        if !refs.isEmpty {
            return refs
        }
        if isViewingActiveGoalVersion {
            return library.projectGoalV2.activeVersion?.brief.styleTermRefs ?? []
        }
        return refs
    }

    private var goalStyleTaxonomySection: some View {
        let refs = displayedStyleTermRefs
        let groups: [(title: String, kind: ProjectGoalStyleTermKind)] = [
            ("Collections", .collection),
            ("Moods", .mood),
            ("Hues", .hue),
            ("Medium", .medium),
            ("Search phrases", .phrase)
        ]
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Text("Style taxonomy")
                    .font(CanonType.interface(13, weight: .semibold))
                    .foregroundStyle(CanonColor.ink)
                Text("read-only")
                    .font(CanonType.archive(9))
                    .foregroundStyle(CanonColor.ink.opacity(0.4))
            }
            Text("Mapped from this Goal automatically on save; these terms drive the style catalog search behind Scene Plan generation.")
                .font(CanonType.editorial(11.5))
                .foregroundStyle(CanonColor.ink.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
            if refs.isEmpty {
                Text("Not mapped yet — save the Goal and the taxonomy terms appear here.")
                    .font(CanonType.interface(12))
                    .foregroundStyle(CanonColor.ink.opacity(0.5))
                    .padding(.top, 2)
            } else {
                ForEach(groups, id: \.title) { group in
                    let groupRefs = refs.filter { $0.kind == group.kind }
                    if !groupRefs.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(group.title.uppercased())
                                .font(CanonType.archive(8.5, weight: .semibold))
                                .kerning(1.1)
                                .foregroundStyle(CanonColor.ink.opacity(0.45))
                            StyleStudioFlowLayout(spacing: 5) {
                                ForEach(groupRefs, id: \.term) { ref in
                                    goalStyleTaxonomyChip(ref)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CanonColor.paper.opacity(0.62), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(CanonColor.hairlinePaper)
        )
    }

    private func goalStyleTaxonomyChip(_ ref: ProjectGoalStyleTermRef) -> some View {
        HStack(spacing: 5) {
            Text(ref.term)
                .font(CanonType.interface(11.5))
                .foregroundStyle(CanonColor.ink.opacity(0.86))
            if abs(ref.weight - 1) > 0.01 {
                Text(String(format: "×%.1f", ref.weight))
                    .font(CanonType.archive(9))
                    .foregroundStyle(CanonColor.brass)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(Color.white.opacity(0.55), in: Capsule())
        .overlay(Capsule().stroke(CanonColor.hairlinePaper))
        .help(ref.rationale.isEmpty ? ref.term : ref.rationale)
    }

    private var goalReadinessCard: some View {
        let state = readinessState
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Circle()
                    .fill(state.color)
                    .frame(width: 8, height: 8)
                Text(state.title)
                    .font(CanonType.interface(13, weight: .semibold))
                    .foregroundStyle(CanonColor.ink)
            }
            Text(state.detail)
                .font(CanonType.editorial(12))
                .foregroundStyle(CanonColor.ink.opacity(0.66))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CanonColor.paper.opacity(0.62), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(CanonColor.hairlinePaper)
        )
    }

    private var goalFieldActions: some View {
        HStack(spacing: 8) {
            if isViewingActiveGoalVersion {
                goalPillButton("Save", isPrimary: true, disabled: !hasUnsavedFieldEdits && editingField == nil) {
                    saveDraft()
                }
                .keyboardShortcut("s", modifiers: [.command])

                goalPillButton("Revert", isPrimary: false, disabled: !hasUnsavedFieldEdits && editingField == nil) {
                    cancelFieldEdit()
                    syncDraft()
                }
            } else {
                goalPillButton("Restore", isPrimary: true, disabled: viewedGoalVersion == nil) {
                    restoreViewedVersion()
                }
                goalPillButton("Latest", isPrimary: false, disabled: library.projectGoalV2.activeVersion == nil) {
                    viewedVersionId = library.projectGoalV2.activeVersionId
                    cancelFieldEdit()
                }
            }
        }
    }

    private var goalVersionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Versions")
                .font(CanonType.interface(12, weight: .semibold))
                .foregroundStyle(CanonColor.ink)

            if library.projectGoalV2.versions.isEmpty {
                Text("No saved Goal versions yet.")
                    .font(CanonType.editorial(12))
                    .foregroundStyle(CanonColor.ink.opacity(0.58))
            } else {
                ForEach(library.projectGoalV2.versions.reversed()) { version in
                    let isSelected = viewedGoalVersion?.versionId == version.versionId
                    let isActive = library.projectGoalV2.activeVersionId == version.versionId
                    Button {
                        viewedVersionId = version.versionId
                        cancelFieldEdit()
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 6) {
                                Text(version.changeSummary.isEmpty ? "Goal update" : version.changeSummary)
                                    .font(CanonType.interface(12, weight: .medium))
                                    .foregroundStyle(CanonColor.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                if isActive {
                                    Text("Active")
                                        .font(CanonType.archive(9, weight: .semibold))
                                        .foregroundStyle(CanonColor.brass)
                                }
                            }
                            Text(version.createdAt)
                                .font(CanonType.archive(10))
                                .foregroundStyle(CanonColor.ink.opacity(0.54))
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            isSelected ? CanonColor.softGold.opacity(0.42) : CanonColor.paper.opacity(0.48),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isSelected ? CanonColor.brass.opacity(0.78) : CanonColor.hairlinePaper.opacity(0.78))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 4)
    }

    private var canSendMessage: Bool {
        (!composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !selectedMediaIds.isEmpty) && !library.isInterviewingGoal
    }

    private var selectedGoalAttachments: [ChatComposerAttachment] {
        library.mediaItems(for: selectedMediaIds).map {
            ChatComposerAttachment(
                mediaId: $0.mediaId,
                filename: $0.filename,
                thumbnailPath: $0.thumbnailPath,
                kind: $0.kind
            )
        }
    }

    private var hasSavedGoalVersion: Bool {
        library.projectGoalV2.activeVersion != nil
    }

    private var viewedGoalVersion: ProjectGoalBriefVersionV2? {
        let cleanedViewedVersionId = viewedVersionId?.trimmed ?? ""
        let versionId = cleanedViewedVersionId.isEmpty ? library.projectGoalV2.activeVersionId : cleanedViewedVersionId
        if let version = library.projectGoalV2.versions.first(where: { $0.versionId == versionId }) {
            return version
        }
        return library.projectGoalV2.activeVersion
    }

    private var isViewingActiveGoalVersion: Bool {
        guard let viewedGoalVersion else { return true }
        return viewedGoalVersion.versionId == library.projectGoalV2.activeVersionId
    }

    private var displayedBrief: ProjectGoalBriefV2 {
        isViewingActiveGoalVersion ? draft : viewedGoalVersion?.brief ?? draft
    }

    private var hasUnsavedFieldEdits: Bool {
        draft.normalized() != library.activeGoalBriefV2.normalized()
    }

    private var canContinueToLenses: Bool {
        hasSavedGoalVersion && library.projectGoalV2.isReady && !hasUnsavedFieldEdits && editingField == nil
    }

    private var shouldShowGoalReadinessCard: Bool {
        !canContinueToLenses
    }

    private var goalGoodEnoughColor: Color {
        canContinueToLenses
            ? Color(red: 0.46, green: 0.43, blue: 0.58)
            : CanonColor.muted.opacity(0.46)
    }

    private var goalComposerStatusText: String {
        if !attachmentStatus.trimmed.isEmpty {
            return attachmentStatus.trimmed
        }
        let status = library.goalStatus.trimmed
        if canContinueToLenses && status.caseInsensitiveCompare("Goal ready") == .orderedSame {
            return ""
        }
        return status
    }

    private var goalContinueDisabledReason: String {
        if !hasSavedGoalVersion {
            return "Save a Goal first."
        }
        if editingField != nil || hasUnsavedFieldEdits {
            return "Save or revert edits."
        }
        if !library.projectGoalV2.isReady {
            return "Add content type and goal."
        }
        return "Goal is not ready."
    }

    private var readinessState: (title: String, detail: String, color: Color) {
        guard hasSavedGoalVersion else {
            return (
                "No saved Goal yet",
                "Use the chat or edit fields, then Save to create the first project Goal.",
                CanonColor.muted
            )
        }
        if editingField != nil || hasUnsavedFieldEdits {
            return (
                "Unsaved changes",
                "The saved Goal is unchanged until you press Save.",
                CanonColor.brass
            )
        }
        if library.projectGoalV2.isReady {
            return (
                "Saved Goal Ready",
                "This saved Goal can guide Frames and Storylines.",
                Color.green
            )
        }
        return (
            "Saved Goal Incomplete",
            "A saved Goal needs a content type and a clear goal before Frames.",
            CanonColor.rust
        )
    }

    private func goalFieldCard(_ field: GoalV2Field) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(field.title)
                    .font(CanonType.interface(11, weight: .semibold))
                    .foregroundStyle(CanonColor.ink.opacity(0.66))
                Spacer()
                if editingField == field {
                    Button("Cancel") {
                        cancelFieldEdit()
                    }
                    .buttonStyle(.plain)
                    .font(CanonType.interface(11, weight: .semibold))
                    .foregroundStyle(CanonColor.ink.opacity(0.62))
                } else if isViewingActiveGoalVersion {
                    Button("Edit") {
                        beginEditing(field)
                    }
                    .buttonStyle(.plain)
                    .font(CanonType.interface(11, weight: .semibold))
                    .foregroundStyle(CanonColor.focusBlue)
                } else {
                    Text("Preview")
                        .font(CanonType.interface(11, weight: .semibold))
                        .foregroundStyle(CanonColor.ink.opacity(0.44))
                }
            }

            if editingField == field {
                fieldEditor(field)
                HStack {
                    Spacer()
                    goalSmallButton("Done", isPrimary: true) {
                        applyCurrentFieldEdit()
                    }
                }
            } else {
                Text(displayValue(for: field))
                    .font(CanonType.editorial(13))
                    .foregroundStyle(isEmptyValue(for: field) ? CanonColor.ink.opacity(0.42) : CanonColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CanonColor.paper.opacity(0.66), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(editingField == field ? CanonColor.focusBlue.opacity(0.56) : CanonColor.hairlinePaper)
        )
    }

    @ViewBuilder
    private func fieldEditor(_ field: GoalV2Field) -> some View {
        if field == .contentType {
            contentTypeChoiceGrid
        } else if field == .requiredEntities {
            requiredEntitiesEditor
        } else {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $editText)
                    .font(CanonType.editorial(13))
                    .foregroundColor(CanonColor.ink)
                    .scrollContentBackground(.hidden)
                    .focused($isFieldEditorFocused)
                    .padding(8)
                    .frame(minHeight: field.editorHeight)
                    .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(CanonColor.hairlinePaper)
                    )

                if editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(field.placeholder)
                        .font(CanonType.editorial(12))
                        .foregroundStyle(CanonColor.ink.opacity(0.38))
                        .padding(.horizontal, 15)
                        .padding(.vertical, 15)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private var requiredEntitiesEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            if editRequiredEntities.isEmpty {
                Text("No mandatory entities.")
                    .font(CanonType.editorial(12))
                    .foregroundStyle(CanonColor.ink.opacity(0.48))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }

            ForEach(Array(editRequiredEntities.indices), id: \.self) { index in
                HStack(spacing: 7) {
                    TextField("Name", text: entityNameBinding(at: index))
                        .textFieldStyle(.plain)
                        .font(CanonType.editorial(12))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(CanonColor.hairlinePaper))
                    TextField("Role", text: entityRoleBinding(at: index))
                        .textFieldStyle(.plain)
                        .font(CanonType.editorial(12))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(CanonColor.hairlinePaper))
                    Button("Remove") {
                        removeRequiredEntity(at: index)
                    }
                    .buttonStyle(.plain)
                    .font(CanonType.interface(10, weight: .semibold))
                    .foregroundStyle(CanonColor.rust)
                    .frame(width: 48, alignment: .trailing)
                }
            }

            Button {
                addRequiredEntityRow()
            } label: {
                Text("Add Entity")
                    .font(CanonType.interface(11, weight: .semibold))
                    .foregroundStyle(CanonColor.focusBlue)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .disabled(editRequiredEntities.count >= ProjectGoalRequiredEntity.maximumCount)
            .opacity(editRequiredEntities.count >= ProjectGoalRequiredEntity.maximumCount ? 0.44 : 1)
        }
    }

    private func entityNameBinding(at index: Int) -> Binding<String> {
        Binding(
            get: {
                guard editRequiredEntities.indices.contains(index) else { return "" }
                return editRequiredEntities[index].name
            },
            set: { value in
                guard editRequiredEntities.indices.contains(index) else { return }
                editRequiredEntities[index].name = value
                editRequiredEntities[index].required = true
            }
        )
    }

    private func entityRoleBinding(at index: Int) -> Binding<String> {
        Binding(
            get: {
                guard editRequiredEntities.indices.contains(index) else { return "" }
                return editRequiredEntities[index].role
            },
            set: { value in
                guard editRequiredEntities.indices.contains(index) else { return }
                editRequiredEntities[index].role = value
                editRequiredEntities[index].required = true
            }
        )
    }

    private func addRequiredEntityRow() {
        guard editRequiredEntities.count < ProjectGoalRequiredEntity.maximumCount else { return }
        editRequiredEntities.append(ProjectGoalRequiredEntity(required: true))
    }

    private func removeRequiredEntity(at index: Int) {
        guard editRequiredEntities.indices.contains(index) else { return }
        editRequiredEntities.remove(at: index)
    }

    private var contentTypeChoiceGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 6)], alignment: .leading, spacing: 6) {
            contentTypeChoice("Unspecified", value: nil)
            ForEach(ProjectIntent.allCases) { intent in
                contentTypeChoice(intent.label, value: intent)
            }
        }
    }

    private func contentTypeChoice(_ label: String, value: ProjectIntent?) -> some View {
        Button {
            editContentType = value
        } label: {
            Text(label)
                .font(CanonType.interface(11, weight: .semibold))
                .foregroundStyle(editContentType == value ? CanonColor.ink : CanonColor.ink.opacity(0.70))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    editContentType == value ? CanonColor.softGold.opacity(0.42) : Color.white.opacity(0.42),
                    in: RoundedRectangle(cornerRadius: 7)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(editContentType == value ? CanonColor.brass : CanonColor.hairlinePaper)
                )
        }
        .buttonStyle(.plain)
    }

    private func goalPillButton(
        _ title: String,
        isPrimary: Bool,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(CanonType.interface(12, weight: .semibold))
                .foregroundStyle(CanonColor.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    isPrimary ? CanonColor.softGold.opacity(0.82) : Color.white.opacity(0.46),
                    in: RoundedRectangle(cornerRadius: 7)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(isPrimary ? CanonColor.brass.opacity(0.78) : CanonColor.hairlinePaper)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.44 : 1)
    }

    private func goalSmallButton(
        _ title: String,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(CanonType.interface(11, weight: .semibold))
                .foregroundStyle(CanonColor.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    isPrimary ? CanonColor.softGold.opacity(0.82) : Color.white.opacity(0.46),
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isPrimary ? CanonColor.brass.opacity(0.78) : CanonColor.hairlinePaper)
                )
        }
        .buttonStyle(.plain)
    }

    private func displayValue(for field: GoalV2Field) -> String {
        let brief = displayedBrief
        switch field {
        case .contentType:
            return brief.contentType?.label ?? "Unspecified"
        case .goal:
            return brief.goal.trimmed.isEmpty ? field.placeholder : brief.goal.trimmed
        case .audience:
            return brief.audience.trimmed.isEmpty ? field.placeholder : brief.audience.trimmed
        case .desiredResponse:
            return brief.desiredResponse.trimmed.isEmpty ? field.placeholder : brief.desiredResponse.trimmed
        case .viewerExperience:
            return brief.viewerExperience.trimmed.isEmpty ? field.placeholder : brief.viewerExperience.trimmed
        case .successCriteria:
            return brief.successCriteria.isEmpty ? field.placeholder : brief.successCriteria.joined(separator: "\n")
        case .constraints:
            return brief.constraints.isEmpty ? field.placeholder : brief.constraints.joined(separator: "\n")
        case .requiredEntities:
            return requiredEntityDisplayValue()
        case .openQuestions:
            return brief.openQuestions.isEmpty ? field.placeholder : brief.openQuestions.joined(separator: "\n")
        case .lensSeedSummary:
            return brief.lensSeedSummary.trimmed.isEmpty ? field.placeholder : brief.lensSeedSummary.trimmed
        case .lensSeedTerms:
            return brief.lensSeedTerms.isEmpty ? field.placeholder : brief.lensSeedTerms.joined(separator: "\n")
        }
    }

    private func isEmptyValue(for field: GoalV2Field) -> Bool {
        let brief = displayedBrief
        switch field {
        case .contentType:
            return brief.contentType == nil
        case .goal:
            return brief.goal.trimmed.isEmpty
        case .audience:
            return brief.audience.trimmed.isEmpty
        case .desiredResponse:
            return brief.desiredResponse.trimmed.isEmpty
        case .viewerExperience:
            return brief.viewerExperience.trimmed.isEmpty
        case .successCriteria:
            return brief.successCriteria.isEmpty
        case .constraints:
            return brief.constraints.isEmpty
        case .requiredEntities:
            return brief.requiredEntities.isEmpty
        case .openQuestions:
            return brief.openQuestions.isEmpty
        case .lensSeedSummary:
            return brief.lensSeedSummary.trimmed.isEmpty
        case .lensSeedTerms:
            return brief.lensSeedTerms.isEmpty
        }
    }

    private func beginEditing(_ field: GoalV2Field) {
        guard isViewingActiveGoalVersion else { return }
        editingField = field
        editContentType = draft.contentType
        editRequiredEntities = draft.requiredEntities
        editText = rawEditValue(for: field)
        isFieldEditorFocused = field != .contentType && field != .requiredEntities
    }

    private func cancelFieldEdit() {
        editingField = nil
        editText = ""
        editContentType = nil
        editRequiredEntities = []
        isFieldEditorFocused = false
    }

    private func applyCurrentFieldEdit() {
        guard let field = editingField else { return }
        switch field {
        case .contentType:
            draft.contentType = editContentType
        case .goal:
            draft.goal = editText.trimmed
        case .audience:
            draft.audience = editText.trimmed
        case .desiredResponse:
            draft.desiredResponse = editText.trimmed
        case .viewerExperience:
            draft.viewerExperience = editText.trimmed
        case .successCriteria:
            draft.successCriteria = uniqueNonEmpty(editText.components(separatedBy: .newlines))
        case .constraints:
            draft.constraints = uniqueNonEmpty(editText.components(separatedBy: .newlines))
        case .requiredEntities:
            draft.requiredEntities = uniqueRequiredGoalEntities(editRequiredEntities).entities
        case .openQuestions:
            draft.openQuestions = uniqueNonEmpty(editText.components(separatedBy: .newlines))
        case .lensSeedSummary:
            draft.lensSeedSummary = editText.trimmed
        case .lensSeedTerms:
            draft.lensSeedTerms = uniqueNonEmpty(editText.components(separatedBy: .newlines))
        }
        cancelFieldEdit()
    }

    private func rawEditValue(for field: GoalV2Field) -> String {
        switch field {
        case .contentType:
            return ""
        case .goal:
            return draft.goal
        case .audience:
            return draft.audience
        case .desiredResponse:
            return draft.desiredResponse
        case .viewerExperience:
            return draft.viewerExperience
        case .successCriteria:
            return draft.successCriteria.joined(separator: "\n")
        case .constraints:
            return draft.constraints.joined(separator: "\n")
        case .requiredEntities:
            return ""
        case .openQuestions:
            return draft.openQuestions.joined(separator: "\n")
        case .lensSeedSummary:
            return draft.lensSeedSummary
        case .lensSeedTerms:
            return draft.lensSeedTerms.joined(separator: "\n")
        }
    }

    private func requiredEntityDisplayValue() -> String {
        let entities = uniqueRequiredGoalEntities(displayedBrief.requiredEntities).entities
        guard !entities.isEmpty else { return GoalV2Field.requiredEntities.placeholder }
        return entities.map { entity in
            entity.role.isEmpty ? entity.name : "\(entity.name) - \(entity.role)"
        }
        .joined(separator: "\n")
    }

    private func copyGoalConversation() {
        let transcript = goalConversationTranscript()
        guard !transcript.isEmpty else { return }
        copyTextToPasteboard(transcript)
        goalCopyStatus = "Copied"
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            goalCopyStatus = ""
        }
    }

    private func goalConversationTranscript() -> String {
        let messages = library.projectGoalV2.messages
        guard !messages.isEmpty else { return "" }
        var lines: [String] = []
        lines.append("Goal Conversation")
        if let project = library.currentProject {
            lines.append("Project: \(project.name)")
        }
        lines.append("Copied: \(DateFormats.now())")
        lines.append("")
        for message in messages {
            let speaker = message.role == .user ? "You" : "LitScenes"
            let timestamp = message.createdAt.trimmed
            let prefix = timestamp.isEmpty ? "\(speaker):" : "\(speaker) [\(timestamp)]:"
            lines.append(prefix)
            lines.append(message.text.trimmed)
            if !message.mediaIds.isEmpty {
                lines.append("Media: \(message.mediaIds.joined(separator: ", "))")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n").trimmed
    }

    private func sendMessage() {
        guard canSendMessage else { return }
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        let mediaIds = selectedMediaIds
        composerText = ""
        selectedMediaIds = []
        attachmentStatus = ""
        Task {
            await library.sendGoalV2InterviewMessage(text: text, mediaIds: mediaIds)
        }
    }

    private func attachGoalImagesFromPicker() {
        Task { @MainActor in
            let imported = await library.chooseGoalChatImageAttachments()
            appendGoalAttachments(imported.map(\.mediaId))
        }
    }

    private func attachPastedGoalImage(_ data: Data) {
        Task { @MainActor in
            if let item = await library.importGoalChatImageData(data) {
                appendGoalAttachments([item.mediaId])
            } else {
                attachmentStatus = library.goalStatus
            }
        }
    }

    private func attachGoalImageFiles(_ urls: [URL]) {
        Task { @MainActor in
            let imported = await library.importGoalChatImageFiles(urls)
            appendGoalAttachments(imported.map(\.mediaId))
        }
    }

    private func attachExistingGoalMedia(_ mediaIds: [String]) {
        let imageIds = library.mediaItems(for: mediaIds)
            .filter { $0.kind == .image }
            .map(\.mediaId)
        appendGoalAttachments(imageIds)
    }

    private func appendGoalAttachments(_ mediaIds: [String]) {
        let before = selectedMediaIds.count
        selectedMediaIds = uniqueNonEmpty(selectedMediaIds + mediaIds, limit: 8)
        let added = max(0, selectedMediaIds.count - before)
        if added > 0 {
            attachmentStatus = "Attached \(selectedMediaIds.count)/8"
        } else if selectedMediaIds.count >= 8 {
            attachmentStatus = "Attachment limit reached"
        }
    }

    private func removeGoalAttachment(_ mediaId: String) {
        selectedMediaIds.removeAll { $0 == mediaId }
        attachmentStatus = selectedMediaIds.isEmpty ? "" : "Attached \(selectedMediaIds.count)/8"
    }

    private func syncDraft() {
        draft = library.activeGoalBriefV2
        viewedVersionId = library.projectGoalV2.activeVersionId
        cancelFieldEdit()
    }

    private func saveDraft() {
        applyCurrentFieldEdit()
        _ = library.commitGoalV2Brief(draft, changeSummary: "Updated Goal.")
    }

    private func restoreViewedVersion() {
        guard let version = viewedGoalVersion, !isViewingActiveGoalVersion else { return }
        _ = library.restoreGoalV2Version(version)
        viewedVersionId = version.versionId
        cancelFieldEdit()
    }
}

/// Condensed once the operator has accumulated workbench state — staged or
/// finaled work, or a working set of rendered frames. Never a visit counter:
/// @State dies with every tab switch (the tab content's .id teardown);
/// persisted data does not.
func lensLandingIsCondensed(stageCount: Int, finalsCount: Int, readyFrameCount: Int) -> Bool {
    stageCount > 0 || finalsCount > 0 || readyFrameCount >= 3
}

/// Mirrors renderLensMedia(scope: .all)'s exact target predicate so the
/// "Render all planned" CTA advertises precisely the frames the engine will
/// spend on.
func lensPendingRenderableFrames(_ lens: ProjectLens) -> [ProjectLensHeroImage] {
    lens.sortedHeroImages
        .filter { image in
            LensMediaRenderScope.all.includes(LensConceptCategory.category(for: image))
                && image.status != "ready"
                && image.status != "generating"
        }
        .sorted { $0.imageIndex < $1.imageIndex }
}

struct LensWorkbenchView: View {
    @ObservedObject var library: LibraryEngine
    var onOpenGoal: () -> Void
    var onOpenMedia: () -> Void
    var onOpenMediaItem: (MediaItemRecord) -> Void = { _ in }
    var onOpenAppSettings: () -> Void = {}

    @Environment(\.undoManager) private var undoManager
    /// The stage rail's seam toggle is the one picture edit that fires from
    /// the workbench window itself (the player modal and the Clip Inspector
    /// are sheets with their OWN undo managers), so it registers here.
    @StateObject private var stagePictureUndo = ShotPictureUndoCoordinator()

    private enum WorkbenchSelection: Equatable {
        case initial
        case creating(scratchId: String)
        case editingLens(lensId: String)
    }

    /// The exact CUT placement that opened the Frame detail overlay. Entry id
    /// (not only image id) keeps repeated placements independently browsable.
    private struct CutFramePreviewNavigation: Equatable {
        let cutId: String
        let entryId: String
    }

    @State private var draftBody = LensBody.empty()
    @State private var workbenchSelection: WorkbenchSelection = .initial
    @State private var srefCatalog = SREFReferenceCatalog.empty
    @State private var srefCatalogStatus = ""
    @State private var srefCatalogLoadError = ""
    @State private var srefSelectionStatus = ""
    @State private var downloadingSREFReferenceIds: Set<String> = []
    @State private var didRequestManualScratch = false
    @State private var scopedProjectId = ""
    @State private var magnifiedLensHeroPreview: LensHeroPreviewRequest?
    @State private var cutFramePreviewNavigation: CutFramePreviewNavigation?
    /// Full-screen Excursion mode: click-to-dive punch-in authoring over a
    /// cut frame (nil = closed).
    @State private var excursionRequest: ExcursionLaunchRequest?
    /// Frame Creator launched from the hero preview's Variation action (the
    /// theater launches its own creator; this one lives at the workbench level
    /// because the preview overlay does).
    @State private var workbenchFrameCreatorLaunch: WorkbenchFrameCreatorLaunch?
    /// Refusal/miss feedback for the frame detail overlay — rendered INSIDE
    /// the modal, because the workbench's aestheticStatus chrome is invisible
    /// underneath a full-cover overlay.
    @State private var heroPreviewActionStatus = ""
    /// The place expanded into the wide right-anchored panel (nil = tucked away).
    @State private var expandedPlaceId: String?
    @State private var isTerrainMapPresented = false

    // WorkbenchFrameCreatorLaunch moved to file scope (CutStripActionsFactory.swift)
    // so both workbench surfaces can construct it.
    @State private var lensHeroPreviewZoom: CGFloat = 1
    @State private var isSavingNewLens = false
    @State private var lastCommitMessage = ""
    @State private var lastCommitSucceeded = true
    @State private var copiedLensSwatchHex = ""
    @State private var styleImagePreview: StyleImagePreviewRequest?
    @State private var lensTreatmentWeightDrafts: [String: Double] = [:]
    @State private var selectedLensMediaVersionByLens: [String: String] = [:]
    @State private var compareLensMediaVersionByLens: [String: String] = [:]
    @State private var editorMode: LensEditorMode = .overview
    @State private var studioPrimarySlot: LensStyleTreatmentSlot?
    @State private var studioAccentSlots: [LensStyleTreatmentSlot] = []
    @State private var studioCatalogVersion = ""
    @State private var rosterRequest: RosterDetailRequest?
    @State private var selectedLensRightSidebarTab: ScenesContextSidebarTab = .characters
    @State private var sourceMaterialSearchQuery = ""
    /// The Shot canvas' lower edge in the Scenes scroll viewport. When it is
    /// above the viewport, a pinned return target lets a Source Material drag
    /// bring the Shot rows back without ending the drag.
    @State private var shotsViewportMaxY: CGFloat = .greatestFiniteMagnitude
    @State private var isShotsReturnTargeted = false
    @State private var isRightSidebarCollapsed = false
    /// The reframe versions slice extends ~530pt below its card; while open,
    /// the bounded FRAMES viewport reserves room beneath the grid so slices on
    /// the last rows stay reachable (they'd otherwise clip in the nested scroll).
    @State private var isFramesSliceOpenPrimary = false
    @State private var isFramesSliceOpenCompare = false
    /// The OPEN cut rows on the stage canvas (max 3), most-recently-used
    /// first — [0] is the ACTIVE row (last used), the other two are the two
    /// active before it. Every other row renders a collapsed summary line and
    /// builds none of its heavy content. Seeded once per visit with the first
    /// rows in visible order.
    @State private var openCutIds: [String] = []
    @State private var hasSeededOpenCutRows = false
    @State private var jovilabeRequest: JovilabeRequest?
    @State private var shotVideoRequest: ShotVideoRequest?
    @State private var finalsReelRequest: FinalsReelRequest?
    @State private var narrationFocusRequest: ShotNarrationFocusRequest?
    @State private var renderPlanFocusRequest: ShotRenderPlanFocusRequest?
    @State private var clipInspectorRequest: ShotClipInspectorRequest?
    @State private var workbenchWorkspaceSize: CGSize = .zero
    /// Per-visit cache of the preferred story's full snapshot for the landing
    /// hero's scene-title pips. The snapshot is a disk read — fetched once per
    /// entry/version in .task, never in body. The key guards against rendering
    /// a stale snapshot from a previously preferred entry.
    @State private var landingStorySnapshot: SceneStory?
    @State private var landingStorySnapshotKey = ""

    private enum LensEditorMode: Equatable {
        case overview
        case studio
    }

    private struct InitialLensPlannedTake: Identifiable {
        var id: String { title }
        var title: String
        var role: String
        var detail: String
        var iconName: String
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if library.creativeSchemaState.isIncompatible {
                    CreativeResetBanner(library: library)
                }
                HStack(alignment: .top, spacing: 0) {
                    lensPaper
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .zIndex(0)
                    if shouldShowLensVersionSidebar {
                        Rectangle()
                            .fill(CanonColor.hairlinePaper)
                            .frame(width: 1)
                            .allowsHitTesting(false)
                        if let selectedLens {
                            ScenesContextSidebarView(
                                library: library,
                                lens: selectedLens,
                                versionId: selectedMediaVersionId(for: selectedLens),
                                selectedTab: $selectedLensRightSidebarTab,
                                isCollapsed: $isRightSidebarCollapsed,
                                onOpenFrame: { heroImage in
                                    openSelectedLensHeroPreview(heroImage: heroImage)
                                },
                                onOpenRoster: { rosterRequest = $0 },
                                onPreviewStyle: { styleImagePreview = $0 },
                                onOpenPlace: { placeId in
                                    withAnimation(.easeOut(duration: 0.2)) { expandedPlaceId = placeId }
                                },
                                onOpenWorldMap: {
                                    withAnimation(.easeOut(duration: 0.2)) { isTerrainMapPresented = true }
                                },
                                onContentChanged: syncDraft,
                                onOpenAppSettings: onOpenAppSettings
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if let expandedPlace, let selectedLens {
                placeDetailOverlay(place: expandedPlace, lens: selectedLens)
            }

            if isTerrainMapPresented {
                TerrainMapView(library: library) {
                    withAnimation(.easeOut(duration: 0.18)) { isTerrainMapPresented = false }
                }
                .zIndex(31)
            }

            if let magnifiedLensHeroPreview {
                LensHeroPreviewModal(
                    request: magnifiedLensHeroPreview,
                    promptSettings: library.projectPromptSettings,
                    browseItems: heroPreviewBrowseItems(),
                    currentBrowseId: currentHeroPreviewBrowseId(),
                    onOpenBrowseItem: { item in openHeroPreviewBrowseItem(item) },
                    zoomScale: $lensHeroPreviewZoom,
                    reframeSubmissionBlockReason: library.lensHeroReframeBlockReason,
                    isNarrating: library.isGeneratingLensNarration,
                    hasOpenAICredential: openAICredentialStatus?.isConfigured == true,
                    hasFALCredential: falCredentialStatus?.isConfigured == true,
                    hasStabilityCredential: stabilityCredentialStatus?.isConfigured == true,
                    onMakeActive: { request in
                        // Resolve by IMAGE id across lenses: the request's
                        // lensId can go stale for cut/stage-opened frames,
                        // and a refusal must state itself in the modal.
                        guard let resolved = resolvedHeroImageAcrossLenses(imageId: request.imageId) else {
                            heroPreviewActionStatus = "That frame no longer exists in the Scene Plan"
                            return
                        }
                        if library.setLensHeroImageActiveVersion(lensId: resolved.lens.lensId, imageId: request.imageId) {
                            heroPreviewActionStatus = ""
                            syncDraft()
                            self.magnifiedLensHeroPreview = lensHeroPreviewRequest(lensId: resolved.lens.lensId, imageId: request.imageId)
                                ?? request.activeCopy()
                        } else {
                            heroPreviewActionStatus = library.aestheticStatus.trimmed.nilIfEmpty
                                ?? "Could not make this version active"
                        }
                    },
                    onOpenVersion: { item in
                        if let request = lensHeroPreviewRequest(lensId: magnifiedLensHeroPreview.lensId, imageId: item.imageId) {
                            heroPreviewActionStatus = ""
                            self.magnifiedLensHeroPreview = request
                            lensHeroPreviewZoom = 1
                        }
                    },
                    onReframe: { spec, stack, promptBody in
                        let lensId = magnifiedLensHeroPreview.lensId
                        let parentImageId = magnifiedLensHeroPreview.imageId
                        // Close so the child's generating card is visible in the theater.
                        self.magnifiedLensHeroPreview = nil
                        cutFramePreviewNavigation = nil
                        Task {
                            _ = await library.startLensHeroReframeRender(
                                lensId: lensId,
                                parentImageId: parentImageId,
                                spec: spec,
                                stack: stack,
                                promptBody: promptBody
                            )
                            syncDraft()
                        }
                    },
                    onOpenRelated: { imageId in
                        if let request = lensHeroPreviewRequest(lensId: magnifiedLensHeroPreview.lensId, imageId: imageId) {
                            self.magnifiedLensHeroPreview = request
                            lensHeroPreviewZoom = 1
                        }
                    },
                    onNarrate: { voicePresetId in
                        let lensId = magnifiedLensHeroPreview.lensId
                        let imageId = magnifiedLensHeroPreview.imageId
                        Task {
                            _ = await library.startLensHeroNarration(
                                lensId: lensId,
                                imageId: imageId,
                                voicePresetId: voicePresetId
                            )
                            syncDraft()
                            // The modal stays open through narration; refresh it in
                            // place so the bar reflects the finished artifact.
                            if self.magnifiedLensHeroPreview?.imageId == imageId,
                               let refreshed = lensHeroPreviewRequest(lensId: lensId, imageId: imageId) {
                                self.magnifiedLensHeroPreview = refreshed
                            }
                        }
                    },
                    onOpenSettings: onOpenAppSettings,
                    onVariation: {
                        launchFrameCreatorFromPreview(
                            imageId: magnifiedLensHeroPreview.imageId,
                            restyle: false
                        )
                    },
                    onRestyle: {
                        launchFrameCreatorFromPreview(
                            imageId: magnifiedLensHeroPreview.imageId,
                            restyle: true
                        )
                    },
                    onAnimate: {
                        let imageId = magnifiedLensHeroPreview.imageId
                        guard let resolved = resolvedHeroImageAcrossLenses(imageId: imageId) else {
                            heroPreviewActionStatus = "That Frame no longer exists in the Scene Plan"
                            return
                        }
                        heroPreviewActionStatus = ""
                        let lensId = resolved.lens.lensId
                        Task {
                            let accepted = await library.animateLensHeroImageWithWAN25(
                                lensId: lensId,
                                imageId: imageId
                            )
                            syncDraft()
                            if self.magnifiedLensHeroPreview?.imageId == imageId,
                               let refreshed = lensHeroPreviewRequest(lensId: lensId, imageId: imageId) {
                                self.magnifiedLensHeroPreview = refreshed
                            }
                            if !accepted {
                                heroPreviewActionStatus = library.aestheticStatus.trimmed.nilIfEmpty
                                    ?? "Could not animate this Frame"
                            }
                        }
                    },
                    animationBlockReason: library.lensHeroMotionStartBlockReason(
                        lensId: resolvedHeroImageAcrossLenses(imageId: magnifiedLensHeroPreview.imageId)?.lens.lensId
                            ?? magnifiedLensHeroPreview.lensId,
                        imageId: magnifiedLensHeroPreview.imageId
                    ) ?? "",
                    isAnimating: library.activeLensMotionImageId == magnifiedLensHeroPreview.imageId,
                    onRetry: {
                        let imageId = magnifiedLensHeroPreview.imageId
                        guard let resolved = resolvedHeroImageAcrossLenses(imageId: imageId) else {
                            heroPreviewActionStatus = "That frame no longer exists in the Scene Plan"
                            return
                        }
                        heroPreviewActionStatus = ""
                        let lensId = resolved.lens.lensId
                        Task {
                            _ = await library.retryLensHeroImage(lensId: lensId, imageId: imageId)
                            syncDraft()
                            if self.magnifiedLensHeroPreview?.imageId == imageId,
                               let refreshed = lensHeroPreviewRequest(lensId: lensId, imageId: imageId) {
                                self.magnifiedLensHeroPreview = refreshed
                            }
                        }
                    },
                    actionStatus: heroPreviewActionStatus,
                    onDelete: {
                        // Delete honesty: the modal closes only when the
                        // engine actually deleted; a refusal states itself.
                        let deleted = library.disableLensHeroImage(
                            lensId: resolvedHeroImageAcrossLenses(imageId: magnifiedLensHeroPreview.imageId)?.lens.lensId
                                ?? magnifiedLensHeroPreview.lensId,
                            imageId: magnifiedLensHeroPreview.imageId
                        )
                        if deleted {
                            heroPreviewActionStatus = ""
                            syncDraft()
                            self.magnifiedLensHeroPreview = nil
                            cutFramePreviewNavigation = nil
                        } else {
                            heroPreviewActionStatus = library.aestheticStatus.trimmed.nilIfEmpty
                                ?? "Could not delete this render"
                        }
                    },
                    onNavigate: { direction in navigateHeroPreview(by: direction) },
                    onEnterExcursion: cutFramePreviewNavigation == nil
                        ? nil
                        : {
                            let imageId = magnifiedLensHeroPreview.imageId
                            if let navigation = cutFramePreviewNavigation {
                                self.magnifiedLensHeroPreview = nil
                                cutFramePreviewNavigation = nil
                                excursionRequest = ExcursionLaunchRequest(
                                    cutId: navigation.cutId,
                                    entryId: navigation.entryId,
                                    rootImageId: imageId
                                )
                            }
                        }
                ) {
                    self.magnifiedLensHeroPreview = nil
                    cutFramePreviewNavigation = nil
                }
                .transition(.opacity)
            }

            if let excursionRequest {
                ExcursionModeView(
                    library: library,
                    request: excursionRequest,
                    startPunchIn: { afterEntryId, parentImageId, spec, onPlaced in
                        await startPunchInFromExcursion(
                            cutId: excursionRequest.cutId,
                            afterEntryId: afterEntryId,
                            parentImageId: parentImageId,
                            spec: spec,
                            onPlaced: onPlaced
                        )
                    },
                    onExit: { self.excursionRequest = nil }
                )
                .transition(.opacity)
                .zIndex(30)
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        workbenchWorkspaceSize = proxy.size
                    }
                    .onChange(of: proxy.size) { _, newSize in
                        workbenchWorkspaceSize = newSize
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task {
            await loadSREFCatalog()
        }
        .onAppear {
            syncProjectScope()
            reconcileWorkbenchSelection()
            syncDraft()
            consumeFrameCreatorSeed(library.pendingFrameCreatorSeed)
            consumeWorkbenchFocus(library.pendingWorkbenchFocus)
        }
        .onChange(of: library.currentProject?.projectId) { _, _ in
            syncProjectScope()
            reconcileWorkbenchSelection()
            syncDraft()
        }
        .onChange(of: library.projectLenses.activeVersionId) { _, _ in
            reconcileWorkbenchSelection()
            syncDraft()
        }
        .onChange(of: library.pendingFrameCreatorSeed) { _, seed in
            consumeFrameCreatorSeed(seed)
        }
        .onChange(of: library.pendingWorkbenchFocus) { _, focus in
            consumeWorkbenchFocus(focus)
        }
        .onChange(of: workbenchSelection) { _, _ in
            lensTreatmentWeightDrafts = [:]
            exitStudioMode()
        }
        .foregroundStyle(CanonColor.ink)
        .tint(CanonColor.focusBlue)
        .environment(\.colorScheme, .light)
        .sheet(item: $rosterRequest) { request in
            ProjectRosterView(library: library, initialKind: request.kind, initialSelectedEntryId: request.entryId)
        }
        .sheet(item: $workbenchFrameCreatorLaunch) { launch in
            if let lens = library.projectLenses.lenses.first(where: { $0.lensId == launch.lensId }) {
                workbenchFrameCreatorModal(lens: lens, launch: launch)
            }
        }
        .sheet(item: $styleImagePreview) { request in
            StyleImagePreviewModal(request: request)
        }
        .sheet(item: $jovilabeRequest) { request in
            jovilabeSheet(request)
        }
        .sheet(item: $shotVideoRequest) { request in
            shotVideoSheet(request)
        }
        .sheet(item: $finalsReelRequest) { _ in
            FinalsReelPlayerView(
                library: library,
                onClose: { finalsReelRequest = nil }
            )
        }
        .sheet(item: $clipInspectorRequest) { request in
            ShotClipInspectorView(
                library: library,
                shotId: request.shotId,
                entryId: request.entryId,
                onSpawnFrame: { seed in
                    clipInspectorRequest = nil
                    if let lensId = selectedLens?.lensId {
                        workbenchFrameCreatorLaunch = WorkbenchFrameCreatorLaunch(
                            lensId: lensId,
                            context: .clipMoment(seed)
                        )
                    }
                },
                onReviewExtension: { preparation in
                    clipInspectorRequest = nil
                    touchOpenCut(preparation.shotId)
                    renderPlanFocusRequest = ShotRenderPlanFocusRequest(
                        shotId: preparation.shotId,
                        segmentPlacementKey: preparation.segmentPlacementKey
                    )
                },
                onClose: { clipInspectorRequest = nil }
            )
        }
    }

    /// The shot player sheet — assembly lives in ShotPlayerSheetHost
    /// (shared with SCENES v2); this adapter only wires the tab's
    /// presentation state.
    private func shotVideoSheet(_ request: ShotVideoRequest) -> some View {
        ShotPlayerSheetHost(
            library: library,
            request: request,
            onDismiss: { shotVideoRequest = nil },
            onReopen: { shotVideoRequest = $0 },
            onFocusNarration: { shotId in
                shotVideoRequest = nil
                narrationFocusRequest = ShotNarrationFocusRequest(shotId: shotId)
            }
        )
    }

    /// The Jovilabe sheet — assembly lives in JovilabeSheetHost (shared with
    /// SCENES v2); this adapter only wires the tab's presentation state.
    @ViewBuilder
    private func jovilabeSheet(_ request: JovilabeRequest) -> some View {
        if selectedLens != nil {
            JovilabeSheetHost(
                library: library,
                request: request,
                workspaceSize: workbenchWorkspaceSize,
                onDismiss: { jovilabeRequest = nil },
                onOpenFrame: { heroImage in
                    openSelectedLensHeroPreview(heroImage: heroImage)
                }
            )
        } else {
            Color.clear
                .frame(width: 200, height: 120)
                .onAppear { jovilabeRequest = nil }
        }
    }

    private func enterStudioMode() {
        let treatment = styleStudioTargetTreatment?.normalized()
        studioPrimarySlot = treatment?.primary
        studioAccentSlots = treatment?.accents ?? []
        studioCatalogVersion = treatment?.catalogVersion ?? ""
        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
            editorMode = .studio
        }
    }

    private func exitStudioMode() {
        studioPrimarySlot = nil
        studioAccentSlots = []
        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
            editorMode = .overview
        }
    }

    private var studioDraftTreatment: LensStyleTreatment {
        LensStyleTreatment(
            catalogVersion: studioCatalogVersion,
            primary: studioPrimarySlot,
            accents: studioAccentSlots,
            updatedAt: DateFormats.now()
        ).normalized()
    }

    private var styleStudioTargetTreatment: LensStyleTreatment? {
        switch workbenchSelection {
        case .creating:
            return draftBody.styleTreatment
        case .editingLens(let lensId):
            return library.projectLenses.lenses.first(where: { $0.lensId == lensId })?.body.styleTreatment
        case .initial:
            return nil
        }
    }

    private var styleStudioTargetName: String {
        switch workbenchSelection {
        case .creating:
            let title = draftBody.title.trimmed
            return title.isEmpty ? "New Scene Plan draft" : title
        case .editingLens(let lensId):
            let title = library.projectLenses.lenses.first(where: { $0.lensId == lensId })?.body.title.trimmed ?? ""
            return title.isEmpty ? "Scene Plan" : title
        case .initial:
            return "Scene Plan"
        }
    }

    private var styleStudioTargetAvailable: Bool {
        switch workbenchSelection {
        case .creating(let scratchId):
            return library.projectLenses.scratchDrafts.contains { $0.scratchId == scratchId }
        case .editingLens(let lensId):
            return library.projectLenses.lenses.contains { $0.lensId == lensId }
        case .initial:
            return false
        }
    }

    private func draftedTreatment(from treatment: LensStyleTreatment) -> LensStyleTreatment {
        var updated = treatment
        if var primary = updated.primary {
            primary.weight = draftedWeight(for: primary)
            updated.primary = primary
        }
        updated.accents = updated.accents.map { accent in
            var slot = accent
            slot.weight = draftedWeight(for: accent)
            return slot
        }
        updated.updatedAt = DateFormats.now()
        return updated.normalized()
    }

    private func treatmentDraftIsDirty(_ treatment: LensStyleTreatment) -> Bool {
        treatment.slots.contains { slot in
            draftedWeight(for: slot) != slot.weight
        }
    }

    private func newestVersionIsRendering(_ lens: ProjectLens) -> Bool {
        LensTreatmentState.newestVersionIsRendering(lens)
    }

    private func regenerateLens(_ lens: ProjectLens, treatment: LensStyleTreatment) {
        let lensId = lens.lensId
        let weightsDirty = treatmentDraftIsDirty(treatment)
        let updatedTreatment = weightsDirty ? draftedTreatment(from: treatment) : nil
        Task {
            if await library.regenerateLensMedia(
                lensId: lensId,
                updatedTreatment: updatedTreatment,
                updatedPlan: nil,
                updatedAnchor: nil
            ) {
                lensTreatmentWeightDrafts = [:]
                selectedLensMediaVersionByLens[lensId] = nil
                compareLensMediaVersionByLens[lensId] = nil
                lastCommitMessage = updatedTreatment != nil ? "Regenerated media with the new settings" : "Regenerated media"
                lastCommitSucceeded = true
            } else {
                lastCommitMessage = library.aestheticStatus.trimmed.isEmpty ? "Scene Plan media regeneration failed" : library.aestheticStatus
                lastCommitSucceeded = false
            }
            syncDraft()
        }
    }

    private func draftedWeight(for slot: LensStyleTreatmentSlot) -> Int {
        if let draft = lensTreatmentWeightDrafts[slot.styleId] {
            return Int(draft)
        }
        return slot.weight
    }

    private func applyStyleTreatment(_ treatment: LensStyleTreatment?) {
        let selection = workbenchSelection
        Task { @MainActor in
            let committed: Bool
            switch selection {
            case .creating(let scratchId):
                committed = await library.setStyleTreatmentForLensScratch(treatment, scratchId: scratchId)
            case .editingLens(let lensId):
                committed = await library.setStyleTreatmentForLens(treatment, lensId: lensId)
            case .initial:
                committed = false
            }
            if committed {
                syncDraft()
                lastCommitMessage = treatment?.isEmpty == false ? "Style treatment applied" : "Style treatment cleared"
                lastCommitSucceeded = true
            } else {
                lastCommitMessage = library.aestheticStatus.trimmed.isEmpty ? "Style treatment update failed" : library.aestheticStatus
                lastCommitSucceeded = false
            }
        }
    }

    @ViewBuilder
    private var lensPaper: some View {
        if editorMode == .studio, styleStudioTargetAvailable {
            studioTakeover
        } else if selectedScratch != nil {
            lensScratchCreateSurface
        } else if isInitialLensEmptyMode {
            ScrollView {
                initialDraftLensesCTA
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CanonColor.paper)
        } else if library.projectLenses.lenses.isEmpty {
            // A project with lens chat messages but no lenses yet is still
            // pre-plan: give it the full CTA surface, not a bare label.
            // (isInitialLensEmptyMode itself stays narrow — it also gates the
            // right sidebar via shouldShowLensVersionSidebar.)
            ScrollView {
                initialDraftLensesCTA
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CanonColor.paper)
        } else {
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    if lensEditorActionBarHasContent {
                        lensEditorActionBar
                            .zIndex(5)
                    }
                    ScrollViewReader { scrollProxy in
                        ScrollView {
                            if let selectedLens {
                                lensDetailDisplay(selectedLens, workspaceSize: proxy.size)
                                    .padding(24)
                            } else {
                                // Lenses exist but none is selected — reconcile
                                // instead of stranding the user on a dead label.
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Selecting the Scene Plan…")
                                        .font(CanonType.interface(13, weight: .medium))
                                        .foregroundStyle(CanonColor.ink.opacity(0.6))
                                }
                                .frame(maxWidth: .infinity, minHeight: 360, alignment: .center)
                                .padding(24)
                                .onAppear { reconcileWorkbenchSelection() }
                            }
                        }
                        .coordinateSpace(name: "lens-scenes-scroll")
                        .overlay(alignment: .top) {
                            if selectedLens != nil, shotsViewportMaxY < 8 {
                                shotsReturnTarget(scrollProxy: scrollProxy)
                                    .padding(.top, 8)
                                    .zIndex(50_000)
                            }
                        }
                    }
                    .zIndex(0)
                }
                .background(CanonColor.paper)
            }
        }
    }

    /// Inline studio mode: the style browser takes the paper, with a pinned right column
    /// holding the draft blend and the lens's newest world so treatment edits happen next
    /// to what they change. Escape or Done returns to overview; nothing commits until
    /// Apply.
    private var studioTakeover: some View {
        HStack(alignment: .top, spacing: 0) {
            LensStyleBrowserPanel(
                primarySlot: $studioPrimarySlot,
                accentSlots: $studioAccentSlots,
                catalogVersion: $studioCatalogVersion,
                onPreviewStyle: { styleImagePreview = $0 }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Rectangle().fill(CanonColor.hairlinePaper).frame(width: 1)
            studioTray
                .frame(width: 340)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .background(CanonColor.paper)
        .transition(.opacity)
        .onExitCommand {
            exitStudioMode()
        }
    }

    private var studioTray: some View {
        let draft = studioDraftTreatment
        let saved = styleStudioTargetTreatment?.normalized()
        let dirty = draft != (saved ?? LensStyleTreatment().normalized())
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Treating")
                        .font(CanonType.archive(9, weight: .semibold))
                        .kerning(1.4)
                        .foregroundStyle(CanonColor.muted)
                    Text(styleStudioTargetName)
                        .font(CanonType.editorial(17, weight: .semibold))
                        .foregroundStyle(CanonColor.ink)
                        .lineLimit(2)
                }
                if draft.isEmpty {
                    Text("Choose a primary style, then layer one or two accents to bias the blend.")
                        .font(CanonType.interface(12))
                        .foregroundStyle(CanonColor.muted)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 26)
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(CanonColor.hairlinePaper, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        )
                } else {
                    VStack(spacing: 10) {
                        ForEach(Array(draft.slots.enumerated()), id: \.element.styleId) { index, slot in
                            studioTrayRow(slot: slot, index: index, draft: draft)
                        }
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("TREATMENT RECIPE")
                            .font(CanonType.archive(8.5, weight: .semibold))
                            .kerning(1.2)
                            .foregroundStyle(CanonColor.muted)
                        Text(draft.recipeText)
                            .font(CanonType.editorial(12.5))
                            .foregroundStyle(CanonColor.ink)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.5)))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(CanonColor.hairlinePaper))
                }

                VStack(spacing: 8) {
                    Button {
                        applyStudioTreatment(regenerate: false)
                    } label: {
                        Text(draft.isEmpty && saved?.isEmpty == false ? "Clear treatment" : "Apply")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CanonPrimaryButtonStyle(isFullWidth: true))
                    .disabled(!dirty)
                    if case .editingLens = workbenchSelection {
                        Button {
                            applyStudioTreatment(regenerate: true)
                        } label: {
                            Text("Apply & regenerate media")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(CanonSecondaryButtonStyle(isFullWidth: true))
                        .disabled(draft.isEmpty)
                    }
                    Button("Cancel") { exitStudioMode() }
                        .buttonStyle(.plain)
                        .font(CanonType.interface(11.5, weight: .semibold))
                        .foregroundStyle(CanonColor.muted)
                }

                studioContext
            }
            .padding(16)
        }
        .background(CanonColor.paperInset.opacity(0.5))
    }

    private func studioTrayRow(slot: LensStyleTreatmentSlot, index: Int, draft: LensStyleTreatment) -> some View {
        let tint = CanonColor.roleTint(forSlotIndex: index)
        let shares = draft.blendShares()
        let share = shares.indices.contains(index) ? shares[index] : 0
        // Size carries the weight: the thumbnail scales with the slot's blend share.
        let side: CGFloat = 30 + CGFloat(share) * 0.45
        return VStack(spacing: 8) {
            HStack(spacing: 9) {
                Button {
                    styleImagePreview = StyleImagePreviewRequest(
                        url: slot.url,
                        label: slot.label.isEmpty ? slot.styleId : slot.label,
                        detail: "\(index == 0 ? "Primary" : "Accent \(index)") · \(slot.collection)"
                    )
                } label: {
                    Color.clear
                        .overlay(
                            AsyncImage(url: URL(string: slot.url)) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable().aspectRatio(contentMode: .fill)
                                default:
                                    CanonColor.paperInset
                                }
                            }
                        )
                        .frame(width: side, height: side)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: side)
                        .contentShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("\(slot.label.isEmpty ? slot.styleId : slot.label) — click to view")
                VStack(alignment: .leading, spacing: 2) {
                    Text((index == 0 ? "Primary" : "Accent \(index)").uppercased())
                        .font(CanonType.archive(8, weight: .semibold))
                        .kerning(1.1)
                        .foregroundStyle(tint)
                    Text(slot.label.isEmpty ? slot.styleId : slot.label)
                        .font(CanonType.editorial(12))
                        .foregroundStyle(CanonColor.ink)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text("\(share)%")
                    .font(CanonType.archive(12))
                    .foregroundStyle(CanonColor.ink)
                Button {
                    if index == 0 {
                        studioPrimarySlot = nil
                    } else {
                        studioAccentSlots.removeAll { $0.styleId == slot.styleId }
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(CanonColor.muted)
                }
                .buttonStyle(.plain)
            }
            Slider(
                value: Binding(
                    get: { Double(slot.weight) },
                    set: { newWeight in
                        if index == 0 {
                            studioPrimarySlot?.weight = Int(newWeight)
                        } else if let accentIndex = studioAccentSlots.firstIndex(where: { $0.styleId == slot.styleId }) {
                            studioAccentSlots[accentIndex].weight = Int(newWeight)
                        }
                    }
                ),
                in: 5...90,
                step: 1
            )
            .controlSize(.mini)
            .tint(tint)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.45)))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(CanonColor.hairlinePaper))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1).fill(tint).frame(width: 2).padding(.vertical, 6)
        }
    }

    /// The world this treatment shapes: the newest ready composite and the lens claim,
    /// pinned beside the browser so edits are made in context.
    @ViewBuilder
    private var studioContext: some View {
        if case .editingLens(let lensId) = workbenchSelection,
           let lens = library.projectLenses.lenses.first(where: { $0.lensId == lensId }) {
            let newestReady = lens.sortedHeroImages.last { $0.status == "ready" && !$0.imagePath.isEmpty }
            VStack(alignment: .leading, spacing: 8) {
                Rectangle().fill(CanonColor.hairlinePaper).frame(height: 1)
                Text("THE WORLD THIS SHAPES")
                    .font(CanonType.archive(8.5, weight: .semibold))
                    .kerning(1.3)
                    .foregroundStyle(CanonColor.muted)
                if let newestReady, let nsImage = NSImage(contentsOfFile: newestReady.imagePath) {
                    Color.clear
                        .overlay(
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 170)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(CanonColor.hairlinePaper))
                }
                if !lens.body.claim.trimmed.isEmpty {
                    Text(lens.body.claim)
                        .font(CanonType.editorial(13, weight: .medium))
                        .foregroundStyle(CanonColor.ink.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func applyStudioTreatment(regenerate: Bool) {
        let draft = studioDraftTreatment
        let treatment = draft.isEmpty ? nil : draft
        exitStudioMode()
        if regenerate, let treatment, case .editingLens(let lensId) = workbenchSelection {
            // One gesture, one creative version: treatment commit + media queue together.
            lensTreatmentWeightDrafts = [:]
            Task { @MainActor in
                if await library.regenerateLensMedia(lensId: lensId, updatedTreatment: treatment) {
                    selectedLensMediaVersionByLens[lensId] = nil
                    compareLensMediaVersionByLens[lensId] = nil
                    lastCommitMessage = "Regenerating media with the new blend"
                    lastCommitSucceeded = true
                } else {
                    lastCommitMessage = library.aestheticStatus.trimmed.isEmpty ? "Scene Plan media regeneration failed" : library.aestheticStatus
                    lastCommitSucceeded = false
                }
                syncDraft()
            }
        } else {
            lensTreatmentWeightDrafts = [:]
            applyStyleTreatment(treatment)
        }
    }

    private var lensScratchCreateSurface: some View {
        VStack(spacing: 0) {
            lensEditorActionBar
                .zIndex(5)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    lensCreateMediaAnchorRail
                    lensCreateSREFStyleRail
                    if !draftBody.styleIngredients.isEmpty {
                        styleIngredients
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .zIndex(0)
        }
        .background(CanonColor.paper)
    }

    private var lensCreateMediaAnchorRail: some View {
        let items = library.enabledContentItems
        let selectedIds = Set(draftBody.referenceMediaIds)
        return VStack(alignment: .leading, spacing: 10) {
            lensCreateRailHeader(
                title: "Scene Plan Anchors",
                countText: "\(selectedIds.count) selected",
                statusText: items.isEmpty ? "No enabled media available" : ""
            )
            if items.isEmpty {
                lensCreateEmptyRail("Promote Story Inputs in MEDIA before choosing Scene Plan anchors.")
                    .frame(height: 152)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(items) { item in
                            lensCreateMediaAnchorCard(item, isSelected: selectedIds.contains(item.mediaId))
                        }
                    }
                    .padding(.vertical, 2)
                    .padding(.trailing, 16)
                }
                .frame(height: 162)
            }
        }
        .padding(14)
        .frame(height: 206, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(CanonColor.paperInset.opacity(0.68), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlinePaper.opacity(0.82)))
    }

    private var lensCreateSREFStyleRail: some View {
        let items = srefCatalog.displayItems
        let selectedIds = selectedSREFStyleReferenceIds
        let statusText = srefCatalogLoadError.isEmpty ? srefCatalogStatus : srefCatalogLoadError
        return VStack(alignment: .leading, spacing: 10) {
            lensCreateRailHeader(
                title: "Style Image References",
                countText: "\(selectedIds.count) selected",
                statusText: statusText
            )
            if items.isEmpty {
                lensCreateEmptyRail(srefCatalogLoadError.isEmpty ? "Loading SREF style references..." : srefCatalogLoadError)
                    .frame(height: 174)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(items) { item in
                            lensCreateSREFStyleCard(item)
                        }
                    }
                    .padding(.vertical, 2)
                    .padding(.trailing, 16)
                }
                .frame(height: 184)
            }
            if !srefSelectionStatus.isEmpty {
                Text(srefSelectionStatus)
                    .font(CanonType.interface(11, weight: .medium))
                    .foregroundStyle(CanonColor.ink.opacity(0.60))
                    .lineLimit(2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(CanonColor.paperInset.opacity(0.52), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlinePaper.opacity(0.82)))
    }

    private func lensCreateRailHeader(title: String, countText: String, statusText: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(CanonType.interface(12, weight: .semibold))
                .foregroundStyle(CanonColor.ink.opacity(0.78))
            Text(countText)
                .font(CanonType.archive(10, weight: .semibold))
                .foregroundStyle(CanonColor.brass.opacity(0.82))
            if !statusText.trimmed.isEmpty {
                Text(statusText)
                    .font(CanonType.interface(11))
                    .foregroundStyle(srefCatalogLoadError.isEmpty ? CanonColor.ink.opacity(0.50) : CanonColor.rust)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private func lensCreateEmptyRail(_ text: String) -> some View {
        Text(text)
            .font(CanonType.editorial(13))
            .foregroundStyle(CanonColor.ink.opacity(0.54))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(Color.white.opacity(0.32), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlinePaper.opacity(0.72)))
    }

    private func lensCreateMediaAnchorCard(_ item: MediaItemRecord, isSelected: Bool) -> some View {
        let width = lensCreateMediaAnchorCardWidth(item)
        return Button {
            toggleLensMediaAnchor(item)
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                ZStack(alignment: .topTrailing) {
                    LensCreateMediaThumbnail(item: item)
                        .frame(width: width, height: 118)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    lensSelectionBadge(isSelected: isSelected)
                        .padding(7)
                }
                Text(item.filename)
                    .font(CanonType.interface(10, weight: .semibold))
                    .foregroundStyle(CanonColor.ink.opacity(0.82))
                    .lineLimit(2)
                    .frame(width: width, alignment: .leading)
            }
            .padding(8)
            .frame(width: width + 16, height: 154, alignment: .topLeading)
            .background(isSelected ? CanonColor.softGold.opacity(0.24) : Color.white.opacity(0.44), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? CanonColor.brass.opacity(0.86) : CanonColor.hairlinePaper.opacity(0.78), lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(isSelected ? "Remove Scene Plan anchor" : "Use as Scene Plan anchor")
    }

    private func lensCreateSREFStyleCard(_ item: SREFReferenceCatalogItem) -> some View {
        let reference = item.styleImageReference(in: srefCatalog)
        let referenceId = reference?.id ?? item.id
        let isSelected = reference.map { selectedSREFStyleReferenceIds.contains($0.id) } ?? false
        let isDownloading = downloadingSREFReferenceIds.contains(referenceId)
        return Button {
            toggleSREFStyleReference(item)
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                ZStack(alignment: .topTrailing) {
                    SREFStyleReferenceThumbnail(urlString: reference?.url ?? "")
                        .frame(width: 148, height: 148)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    if isDownloading {
                        ProgressView()
                            .controlSize(.small)
                            .padding(8)
                            .background(Color.white.opacity(0.72), in: Circle())
                            .padding(7)
                    } else {
                        lensSelectionBadge(isSelected: isSelected)
                            .padding(7)
                    }
                }
                Text(item.displayTitle)
                    .font(CanonType.interface(10, weight: .semibold))
                    .foregroundStyle(CanonColor.ink.opacity(0.82))
                    .lineLimit(2)
                    .frame(width: 148, alignment: .leading)
                if !item.srefCode.trimmed.isEmpty {
                    Text("SREF \(item.srefCode)")
                        .font(CanonType.archive(9, weight: .medium))
                        .foregroundStyle(CanonColor.ink.opacity(0.46))
                        .lineLimit(1)
                        .frame(width: 148, alignment: .leading)
                }
            }
            .padding(8)
            .frame(width: 164, height: 184, alignment: .topLeading)
            .background(isSelected ? CanonColor.softGold.opacity(0.24) : Color.white.opacity(0.44), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? CanonColor.brass.opacity(0.86) : CanonColor.hairlinePaper.opacity(0.78), lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(reference == nil || isDownloading)
        .opacity(reference == nil ? 0.5 : 1)
        .help(isSelected ? "Remove style reference" : "Use as style reference")
    }

    private func lensSelectionBadge(isSelected: Bool) -> some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(isSelected ? CanonColor.brass : CanonColor.ink.opacity(0.36))
            .shadow(color: Color.white.opacity(0.82), radius: 3, x: 0, y: 1)
    }

    private func lensCreateMediaAnchorCardWidth(_ item: MediaItemRecord) -> CGFloat {
        let width = max(item.width, 1)
        let height = max(item.height, 1)
        let ratio = min(max(CGFloat(width) / CGFloat(height), 0.62), 1.92)
        return min(max(118 * ratio, 108), 226)
    }

    private func selectedMediaVersionId(for lens: ProjectLens) -> String {
        let versions = lens.mediaVersionIds
        if let selected = selectedLensMediaVersionByLens[lens.lensId], versions.contains(selected) {
            return selected
        }
        return versions.last ?? ""
    }

    /// Categories the main scene board renders; characters and objects live in the
    /// right sidebar now.
    static let sceneBoardCategories: Set<LensConceptCategory> = [.areas, .scenery, .legacy]

    /// One configured generation board, filtered to `categories`. Shared by the main
    /// scene board and the sidebar's Characters / Objects tabs so their frame browsing,
    /// "+" take button, and render controls behave identically.
    /// The SHOTS band: sits between the version timeline and the frames board.
    // MARK: - Stage canvas (the STAGE / CUT column that replaced the shots band)

    /// The FINALS shelf appears once there is anything to pick (a cut exists)
    /// or anything already picked.
    @ViewBuilder
    private func finalsShelfSection(for lens: ProjectLens) -> some View {
        if !library.shotTimeline.shots.isEmpty || !library.stageSet.finals.isEmpty {
            FinalsShelfView(
                entries: library.stageSet.finals.compactMap { entry in
                    library.shotTimeline.shots
                        .first { $0.shotId == entry.cutId }
                        .map { FinalsShelfEntry(entry: entry, cut: $0) }
                },
                frameLookup: library.projectWideFrameLookup,
                mediaLookup: Dictionary(
                    library.items.map { ($0.mediaId, $0) },
                    uniquingKeysWith: { first, _ in first }
                ),
                stageNameForCut: { cutId in
                    library.stageSet.stage(containingCut: cutId)?.name ?? ""
                },
                onOpenCut: { cutId in
                    shotVideoRequest = ShotVideoRequest(shotId: cutId, openRerenderPanel: true)
                },
                onRemoveEntry: { entryId in
                    library.removeFinalsEntry(entryId: entryId)
                },
                onDropCut: { cutId, index in
                    if let existing = library.stageSet.finals.first(where: { $0.cutId == cutId }) {
                        library.moveFinalsEntry(entryId: existing.entryId, toIndex: index ?? library.stageSet.finals.count)
                    } else {
                        library.addCutToFinals(cutId: cutId)
                        if let index,
                           let added = library.stageSet.finals.first(where: { $0.cutId == cutId }) {
                            library.moveFinalsEntry(entryId: added.entryId, toIndex: index)
                        }
                    }
                },
                onPlayReel: {
                    finalsReelRequest = FinalsReelRequest()
                }
            )
        }
    }

    /// The soft-delete archive, shown only when it holds something.
    @ViewBuilder
    private var deletedCutsSection: some View {
        if !library.stageSet.trashedCuts.isEmpty {
            DeletedCutsShelfView(
                rows: library.stageSet.trashedCuts.map { trashed in
                    DeletedCutRow(
                        trashed: trashed,
                        cut: library.shotTimeline.shots.first { $0.shotId == trashed.cutId }
                    )
                },
                frameLookup: library.projectWideFrameLookup,
                mediaLookup: Dictionary(
                    library.items.map { ($0.mediaId, $0) },
                    uniquingKeysWith: { first, _ in first }
                ),
                onRestore: { trashEntryId in
                    library.restoreCut(trashEntryId: trashEntryId)
                }
            )
        }
    }

    /// One complete, deterministic Source Material order for every Shot `+`
    /// picker. It begins with exactly what the inline inventory shows for the
    /// selected Scene/version, then retains project-wide Frames and Footage.
    /// A photo adopted in some other Scene must remain present as the original
    /// media item here — first use in this Scene owns its lazy adoption.
    private func sourceMaterialInputs(for lens: ProjectLens, versionId: String) -> [StageInput] {
        // The law itself lives in projectPoolInputs (ScenesV2Models.swift),
        // shared with the SCENES v2 pool so the two inventories cannot drift.
        projectPoolInputs(
            displayedFrames: lens.heroImages(mediaVersion: versionId),
            projectWideFrames: Array(library.projectWideFrameLookup.values),
            items: library.items
        )
    }

    private func flatShotsCanvasSection(for lens: ProjectLens) -> some View {
        let versionId = selectedMediaVersionId(for: lens)
        let frameLookup = library.projectWideFrameLookup
        let mediaLookup = Dictionary(
            library.items.map { ($0.mediaId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var actions = FlatShotsCanvasActions()
        actions.sourceInputs = sourceMaterialInputs(for: lens, versionId: versionId)
        actions.cutActions = cutStripActions(
            for: lens,
            frameLookup: frameLookup,
            mediaLookup: mediaLookup
        )
        actions.onCreateShot = {
            _ = library.createShot(lensId: lens.lensId)
        }
        actions.onCreateShotWith = { transfer in
            if transfer.isClipDrag {
                _ = library.createShot(lensId: lens.lensId, withMediaId: transfer.clipMediaId)
            } else if !transfer.frameImageId.trimmed.isEmpty {
                _ = library.createShot(lensId: lens.lensId, withFrameImageId: transfer.frameImageId)
            }
        }
        actions.onMoveShot = { shotId, index in
            library.moveShot(shotId: shotId, toVisibleIndex: index)
        }
        actions.onPreflightCombine = { ids in
            library.combinedShotPreflight(sourceShotIds: ids)
        }
        actions.onCombine = { ids in
            library.combineShots(sourceShotIds: ids)
        }
        actions.onOpenCombined = { shotId in
            shotVideoRequest = ShotVideoRequest(shotId: shotId, openRerenderPanel: true)
        }
        return FlatShotsCanvasView(
            shots: library.shotTimeline.visibleShots,
            actions: actions
        )
        .id("lens-scenes-shots")
        .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.frame(in: .named("lens-scenes-scroll")).maxY
        } action: { maxY in
            shotsViewportMaxY = maxY
            if maxY >= 8 {
                isShotsReturnTargeted = false
            }
        }
        .onAppear(perform: seedOpenShotRows)
    }

    private func shotsReturnTarget(scrollProxy: ScrollViewProxy) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) {
                scrollProxy.scrollTo("lens-scenes-shots", anchor: .top)
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 9, weight: .bold))
                Text(isShotsReturnTargeted ? "RETURNING TO SHOTS…" : "SHOTS")
                    .font(CanonType.archive(8.5, weight: .bold))
                    .kerning(1.1)
            }
            .foregroundStyle(isShotsReturnTargeted ? CanonColor.paper : CanonColor.brass)
            .padding(.horizontal, 13)
            .frame(height: 30)
            .background(
                Capsule().fill(isShotsReturnTargeted ? CanonColor.brass : CanonColor.paper.opacity(0.96))
            )
            .overlay(Capsule().stroke(CanonColor.brass.opacity(0.72), lineWidth: 1))
            .shadow(color: CanonColor.ink.opacity(0.12), radius: 8, y: 3)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Click to return to the Shot rows, or drag Source Material here and keep holding to choose a Shot")
        .dropDestination(for: ShotFrameTransfer.self) { _, _ in
            // This is a navigation bridge, never a placement target. Once it
            // brings the rows onscreen, the operator drops on the exact Shot.
            false
        } isTargeted: { targeted in
            isShotsReturnTargeted = targeted
            guard targeted else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                scrollProxy.scrollTo("lens-scenes-shots", anchor: .top)
            }
        }
    }

    private func seedOpenShotRows() {
        guard !hasSeededOpenCutRows else { return }
        hasSeededOpenCutRows = true
        guard openCutIds.isEmpty else { return }
        openCutIds = Array(library.shotTimeline.visibleShots.map(\.shotId).prefix(3))
    }

    @ViewBuilder
    private var deletedShotsSection: some View {
        if !library.shotTimeline.trashedShots.isEmpty {
            DeletedShotsShelfView(
                rows: library.shotTimeline.trashedShots.map { trashed in
                    DeletedShotRow(
                        trashed: trashed,
                        shot: library.shotTimeline.shots.first { $0.shotId == trashed.shotId }
                    )
                },
                frameLookup: library.projectWideFrameLookup,
                mediaLookup: Dictionary(
                    library.items.map { ($0.mediaId, $0) },
                    uniquingKeysWith: { first, _ in first }
                ),
                onRestore: { library.restoreShot(trashEntryId: $0) }
            )
        }
    }

    private func sourceMaterialSection(
        for lens: ProjectLens,
        versionId: String,
        isSequence: Bool,
        workspaceSize: CGSize
    ) -> some View {
        // Merge a photo only with the Frame this surface actually renders;
        // an adoption on another Scene/version must never make the upload
        // disappear from the current Scene's inventory.
        let displayedFrames = lens.heroImages(mediaVersion: versionId)
        let adopted = Set(displayedFrames.flatMap { frame in
            frame.sourceDependencies.compactMap { dependency in
                let normalized = dependency.normalized()
                return normalized.role == "source_photo" ? normalized.sourceId : nil
            }
        })
        let mediaFrameCount = library.items.filter { $0.kind == .image && !adopted.contains($0.mediaId) }.count
        let footageCount = library.items.filter { $0.kind == .video }.count
        let generatedFrameCount = displayedFrames.count
        return VStack(alignment: .leading, spacing: 14) {
            SourceMaterialHeaderView(filterQuery: $sourceMaterialSearchQuery)
            SourceMaterialSectionHeader(title: "Frames", count: mediaFrameCount + generatedFrameCount)
            SourceMediaGrid(
                library: library,
                kind: .image,
                filterQuery: sourceMaterialSearchQuery,
                excludedMediaIds: adopted,
                onOpenMedia: onOpenMediaItem,
                onAddFrame: {
                    workbenchFrameCreatorLaunch = WorkbenchFrameCreatorLaunch(
                        lensId: lens.lensId,
                        context: .shotFrame(appendToShotId: nil)
                    )
                }
            )
            lensTheater(
                for: lens,
                versionId: versionId,
                isSequence: isSequence,
                workspaceSize: workspaceSize,
                categories: Self.sceneBoardCategories,
                showPauseControl: true,
                flattenPlaceGroups: true,
                filterQuery: sourceMaterialSearchQuery,
                showsSectionHeaders: false,
                showsBlankFrameCreationCard: false,
                onVersionsSliceVisibilityChanged: { isFramesSliceOpenPrimary = $0 }
            )
            .zIndex(10_000)
            SourceMaterialSectionHeader(title: "Footage", count: footageCount)
            SourceMediaGrid(
                library: library,
                kind: .video,
                filterQuery: sourceMaterialSearchQuery,
                onOpenMedia: onOpenMediaItem
            )
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.28)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(CanonColor.hairlinePaper.opacity(0.9)))
        .padding(.bottom, isFramesSliceOpenPrimary ? 560 : 0)
        .zIndex(10_000)
    }

    private func stageCanvasSection(for lens: ProjectLens) -> some View {
        let plateActions = stagePlateActions(for: lens)
        return VStack(alignment: .leading, spacing: 22) {
            ForEach(library.stageSet.stages) { stage in
                StagePlateView(
                    stage: stage,
                    cuts: library.stageSet.visibleCutIds(in: stage).compactMap { cutId in
                        library.shotTimeline.shots.first { $0.shotId == cutId }
                    },
                    actions: plateActions
                )
            }
            NewStageStrip(
                isFirstStage: library.stageSet.stages.isEmpty,
                onCreate: { _ = library.createStage() },
                onCreateWith: { transfer in
                    let stageId = library.createStage()
                    gatherTransfer(transfer, intoStage: stageId, lensId: lens.lensId)
                }
            )
        }
        .onAppear(perform: seedOpenCutRows)
    }

    /// First visit opens the leading rows so the canvas never lands fully
    /// collapsed; after that the MRU is purely gesture-driven.
    private func seedOpenCutRows() {
        guard !hasSeededOpenCutRows else { return }
        hasSeededOpenCutRows = true
        guard openCutIds.isEmpty else { return }
        openCutIds = Array(
            library.stageSet.stages
                .flatMap { library.stageSet.visibleCutIds(in: $0) }
                .prefix(3)
        )
    }

    /// The one mutation of the open-row MRU: `cutId` becomes the ACTIVE row,
    /// stale ids (trashed/combined-away cuts) are swept, and the list holds 3.
    private func touchOpenCut(_ cutId: String) {
        let visibleIds = Set(library.shotTimeline.visibleShots.map(\.shotId))
        var ids = openCutIds.filter { id in
            id != cutId && visibleIds.contains(id)
        }
        ids.insert(cutId, at: 0)
        openCutIds = Array(ids.prefix(3))
    }

    /// Routes any frame/footage/media drag into a stage's palette:
    /// palette-to-palette drags MOVE the reference, everything else adds one.
    /// A clip drag is really a MEDIA drag (the alias decode), so it routes
    /// through the kind-branching gather — an image gathers as its
    /// adopted-or-minted Frame, never a bogus clip reference.
    private func gatherTransfer(_ transfer: ShotFrameTransfer, intoStage stageId: String, lensId: String) {
        if !transfer.sourceStageId.isEmpty, !transfer.sourceInputId.isEmpty {
            guard transfer.sourceStageId != stageId else { return }
            library.moveStageInput(inputId: transfer.sourceInputId, toStage: stageId)
        } else if transfer.isClipDrag {
            library.addStageMediaInput(stageId: stageId, mediaId: transfer.clipMediaId, lensId: lensId)
        } else if !transfer.frameImageId.trimmed.isEmpty {
            library.addStageFrameInput(stageId: stageId, frameImageId: transfer.frameImageId)
        }
    }

    /// Cut placements pull their material onto the owning stage's palette —
    /// what a cut uses, the stage holds.
    private func gatherIntoStage(containingCut cutId: String, transfer: ShotFrameTransfer, lensId: String) {
        guard let stage = library.stageSet.stage(containingCut: cutId) else { return }
        if transfer.isClipDrag {
            library.addStageMediaInput(stageId: stage.stageId, mediaId: transfer.clipMediaId, lensId: lensId)
        } else if !transfer.frameImageId.trimmed.isEmpty {
            library.addStageFrameInput(stageId: stage.stageId, frameImageId: transfer.frameImageId)
        }
    }

    private func stagePlateActions(for lens: ProjectLens) -> StagePlateActions {
        var actions = StagePlateActions()
        actions.frameLookup = library.projectWideFrameLookup
        actions.mediaLookup = Dictionary(
            library.items.map { ($0.mediaId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        actions.onRenameStage = { stageId, name in
            library.renameStage(stageId: stageId, name: name)
        }
        actions.onDeleteStage = { stageId in
            library.deleteStage(stageId: stageId)
        }
        actions.onGather = { stageId, transfer in
            gatherTransfer(transfer, intoStage: stageId, lensId: lens.lensId)
        }
        actions.onRemoveInput = { stageId, input in
            library.removeStageInput(stageId: stageId, inputId: input.inputId)
        }
        actions.onCreateFrame = { stageId in
            workbenchFrameCreatorLaunch = WorkbenchFrameCreatorLaunch(
                lensId: lens.lensId,
                context: .stageFrame(stageId: stageId, appendToCutId: nil)
            )
        }
        actions.onCreateCut = { stageId in
            _ = library.createCut(inStage: stageId)
        }
        actions.onCreateCutWith = { stageId, transfer in
            if transfer.isClipDrag {
                _ = library.createCut(inStage: stageId, withClipMediaId: transfer.clipMediaId)
                library.addStageClipInput(stageId: stageId, mediaId: transfer.clipMediaId)
            } else if !transfer.frameImageId.trimmed.isEmpty {
                _ = library.createCut(inStage: stageId, withFrameImageId: transfer.frameImageId)
                library.addStageFrameInput(stageId: stageId, frameImageId: transfer.frameImageId)
            }
        }
        actions.onPreflightCombine = { stageId, sourceCutIds in
            library.combinedCutPreflight(stageId: stageId, sourceCutIds: sourceCutIds)
        }
        actions.onCombine = { stageId, sourceCutIds in
            library.combineCuts(stageId: stageId, sourceCutIds: sourceCutIds)
        }
        actions.onOpenCombined = { cutId in
            shotVideoRequest = ShotVideoRequest(shotId: cutId, openRerenderPanel: true)
        }
        actions.onMoveCut = { cutId, stageId, index in
            library.moveCut(cutId: cutId, toStage: stageId, toVisibleIndex: index)
        }
        actions.stageDirectory = library.stageSet.stages.map {
            StageDirectoryRow(stageId: $0.stageId, name: $0.name)
        }
        actions.onOpenFrame = { heroImage in
            openSelectedLensHeroPreview(heroImage: heroImage)
        }
        actions.onToggleKept = { heroImage in
            library.setLensHeroImageKept(lensId: lens.lensId, imageId: heroImage.imageId, kept: heroImage.kept != true)
        }
        actions.onRetryFrame = { heroImage in
            Task {
                _ = await library.retryLensHeroImage(lensId: lens.lensId, imageId: heroImage.imageId)
            }
        }
        actions.onDuplicateFrame = { heroImage in
            library.duplicateLensHeroImage(lensId: lens.lensId, imageId: heroImage.imageId)
        }
        actions.cutActions = cutStripActions(
            for: lens,
            frameLookup: actions.frameLookup,
            mediaLookup: actions.mediaLookup
        )
        return actions
    }

    private func cutStripActions(
        for lens: ProjectLens,
        frameLookup: [String: ProjectLensHeroImage],
        mediaLookup: [String: MediaItemRecord]
    ) -> CutStripActions {
        // The assembly itself lives in makeCutStripActions (shared with the
        // SCENES v2 boxes); this adapter only wires the tab's presentation
        // state into the surface.
        var surface = CutStripWorkbenchSurface(pictureUndo: stagePictureUndo)
        surface.openCutIds = openCutIds
        surface.narrationFocusRequest = narrationFocusRequest
        surface.renderPlanFocusRequest = renderPlanFocusRequest
        surface.undoManager = undoManager
        surface.onTouchCut = { cutId in touchOpenCut(cutId) }
        surface.onOpenPlayer = { request in shotVideoRequest = request }
        surface.onFocusNarration = { cutId in
            shotVideoRequest = nil
            narrationFocusRequest = ShotNarrationFocusRequest(shotId: cutId)
        }
        surface.onOpenJovilabe = { cutId in
            jovilabeRequest = JovilabeRequest(shotId: cutId)
        }
        surface.onOpenClipInspector = { request in
            clipInspectorRequest = request
        }
        surface.onOpenFrameDetail = { cutId, entryId, heroImage in
            openSelectedLensHeroPreview(
                heroImage: heroImage,
                cutNavigation: CutFramePreviewNavigation(cutId: cutId, entryId: entryId)
            )
        }
        surface.onEnterExcursion = { request in
            excursionRequest = request
        }
        surface.onLaunchFrameCreator = { launch in
            workbenchFrameCreatorLaunch = launch
        }
        return makeCutStripActions(
            library: library,
            lensId: lens.lensId,
            frameLookup: frameLookup,
            mediaLookup: mediaLookup,
            surface: surface
        )
    }

    private func lensTheater(
        for lens: ProjectLens,
        versionId: String,
        isSequence: Bool,
        workspaceSize: CGSize,
        categories: Set<LensConceptCategory>,
        showPauseControl: Bool,
        identityGroups: [LensIdentityTakeGroup] = [],
        excludedImageIds: Set<String> = [],
        flattenPlaceGroups: Bool = false,
        offersStageGather: Bool = false,
        filterQuery: String = "",
        showsSectionHeaders: Bool = true,
        showsBlankFrameCreationCard: Bool = true,
        onVersionsSliceVisibilityChanged: ((Bool) -> Void)? = nil
    ) -> some View {
        LensGenerationTheaterView(
            lens: lens,
            versionId: versionId,
            isSequence: isSequence,
            workspaceSize: workspaceSize,
            displayCategories: categories,
            filterQuery: filterQuery,
            showsSectionHeaders: showsSectionHeaders,
            identityGroups: identityGroups,
            identityReferenceCandidates: identityGroups.isEmpty ? [] : library.items.filter { $0.kind == .image },
            placeCaptionsByAreaId: flattenPlaceGroups ? [:] : library.lensPlaceCaptionsByAreaId(lens: lens),
            excludedImageIds: excludedImageIds,
            stageGatherTargets: offersStageGather
                ? library.stageSet.stages.map {
                    StageGatherTarget(id: $0.stageId, title: $0.name.trimmed.isEmpty ? "unnamed stage" : $0.name)
                }
                : [],
            onGatherFrame: offersStageGather
                ? { heroImage, stageId in
                    library.addStageFrameInput(stageId: stageId, frameImageId: heroImage.imageId)
                }
                : nil,
            onGatherFrameToNewStage: offersStageGather
                ? { heroImage in
                    let stageId = library.createStage()
                    library.addStageFrameInput(stageId: stageId, frameImageId: heroImage.imageId)
                }
                : nil,
            onDuplicateFrame: offersStageGather
                ? { heroImage in
                    library.duplicateLensHeroImage(lensId: lens.lensId, imageId: heroImage.imageId)
                }
                : nil,
            moodboardItems: library.enabledContentItems.filter { $0.kind == .image },
            moodObservationsById: library.mediaObservationsById,
            mentionEntries: library.frameCreatorMentionEntries(for: lens),
            mentionReferenceItems: library.items.filter { $0.kind == .image },
            onEnsureMentionSheet: { entry in
                switch entry.kind {
                case .character:
                    return await library.buildCharacterCompositeSheet(characterId: entry.id)
                case .object:
                    return await library.buildObjectCompositeSheet(objectId: entry.id)
                case .place:
                    return await library.buildPlaceCompositeSheet(placeId: entry.id)
                }
            },
            referenceLibraryItems: library.items.filter { $0.kind == .image },
            generatedFrameCandidates: generatedFrameReferenceCandidates(lenses: library.projectLenses.lenses, items: library.items),
            onAdoptGeneratedFrame: { hero in
                await library.archiveHeroFrameAsReference(hero)
            },
            onUploadReferences: {
                await library.chooseFrameReferenceImages()
            },
            isAnalyzingMoods: library.isAnalyzingMedia,
            onAutoAnalyzeMoods: {
                Task {
                    await library.analyzeUnanalyzedEnabledMedia()
                }
            },
            onVersionsSliceVisibilityChanged: onVersionsSliceVisibilityChanged,
            formGenerations: library.frameForms.generations.map(\.options).filter { !$0.isEmpty },
            onExpandFormOption: { option, styleFitLine in
                await library.expandFrameForms(from: option, styleFitLine: styleFitLine)
            },
            onTransformFormPrompt: { prompt, directive, priorDirectives in
                await library.transformFormPrompt(
                    prompt: prompt,
                    directive: directive,
                    priorDirectives: priorDirectives
                )
            },
            onOpenImage: { heroImage in
                openSelectedLensHeroPreview(heroImage: heroImage)
            },
            onToggleKept: { heroImage in
                library.setLensHeroImageKept(lensId: lens.lensId, imageId: heroImage.imageId, kept: heroImage.kept != true)
            },
            onRenderScope: { scope in
                Task {
                    _ = await library.renderLensMedia(lensId: lens.lensId, scope: scope)
                    syncDraft()
                }
            },
            onRenderImage: { heroImage, request in
                Task {
                    _ = await library.startLensHeroImageSiblingRender(lensId: lens.lensId, imageId: heroImage.imageId, request: request)
                    syncDraft()
                }
            },
            onRenderNewTake: { heroImage, request in
                Task {
                    _ = await library.startLensHeroNewTakeRender(lensId: lens.lensId, templateImageId: heroImage.imageId, request: request)
                    syncDraft()
                }
            },
            onFulfillPlannedFrame: { heroImage, request in
                Task {
                    _ = await library.startLensHeroPlanFulfillmentRender(
                        lensId: lens.lensId,
                        plannedImageId: heroImage.imageId,
                        request: request
                    )
                    syncDraft()
                }
            },
            onRenderBlankFrame: { category, request in
                Task {
                    _ = await library.startLensHeroNewTakeRender(
                        lensId: lens.lensId,
                        templateImageId: nil,
                        blankCategory: category,
                        versionId: versionId,
                        request: request
                    )
                    syncDraft()
                }
            },
            showsBlankFrameCreationCard: showsBlankFrameCreationCard,
            onOpenIdentity: { group in
                rosterRequest = RosterDetailRequest(
                    kind: group.characterId.isEmpty ? .objects : .characters,
                    entryId: group.characterId.nilIfEmpty
                )
            },
            onRemovePlannedTake: { heroImage in
                _ = library.removePlannedLensCharacterTake(lensId: lens.lensId, imageId: heroImage.imageId)
                syncDraft()
            },
            onAnimateImage: { heroImage in
                Task {
                    _ = await library.animateLensHeroImageWithWAN25(lensId: lens.lensId, imageId: heroImage.imageId)
                    syncDraft()
                }
            },
            onApplyTakeStyle: { heroImage, slot, catalogVersion in
                Task {
                    _ = await library.setLensHeroImageStyle(lensId: lens.lensId, imageId: heroImage.imageId, slot: slot, catalogVersion: catalogVersion)
                    syncDraft()
                }
            },
            onPreviewStyle: { styleImagePreview = $0 },
            onOpenAppSettings: onOpenAppSettings,
            hasOpenAICredential: openAICredentialStatus?.isConfigured == true,
            hasCivitaiCredential: civitaiCredentialStatus?.isConfigured == true,
            hasFALCredential: falCredentialStatus?.isConfigured == true,
            hasStabilityCredential: stabilityCredentialStatus?.isConfigured == true,
            stillRenderBlockReason: library.lensHeroTakeStartBlockReason,
            takeLaneFreeSlots: library.lensHeroTakeLaneFreeSlots,
            isAnimatingLensArtifact: library.isAnimatingLensArtifact,
            isPaused: library.isGenerationPaused,
            onTogglePause: showPauseControl ? { library.setGenerationPaused(!library.isGenerationPaused) } : nil
        )
    }

    /// Media's "Use in Frame Creator" hand-off: land on the lens and open the
    /// creator with the chosen images pre-attached in the reference well. A
    /// stale lens id clears the request quietly.
    private func consumeFrameCreatorSeed(_ seed: FrameCreatorSeedRequest?) {
        guard let seed else { return }
        guard library.projectLenses.lenses.contains(where: { $0.lensId == seed.lensId }) else {
            library.clearFrameCreatorSeed()
            return
        }
        workbenchSelection = .editingLens(lensId: seed.lensId)
        workbenchFrameCreatorLaunch = WorkbenchFrameCreatorLaunch(
            lensId: seed.lensId,
            context: .blankFrame(category: .scenery),
            referenceMediaIds: seed.mediaIds
        )
        library.clearFrameCreatorSeed()
    }

    /// Creations' "Reveal in Scenes" hand-off: select the lens and (when a
    /// take is named) open its magnified preview. Stale ids clear quietly.
    private func consumeWorkbenchFocus(_ focus: WorkbenchFocusRequest?) {
        guard let focus else { return }
        guard library.projectLenses.lenses.contains(where: { $0.lensId == focus.lensId }) else {
            library.clearWorkbenchFocus()
            return
        }
        workbenchSelection = .editingLens(lensId: focus.lensId)
        if !focus.imageId.isEmpty {
            magnifiedLensHeroPreview = lensHeroPreviewRequest(lensId: focus.lensId, imageId: focus.imageId)
        }
        library.clearWorkbenchFocus()
    }

    /// Frame Creator presented from the hero preview's Variation action — same
    /// library wiring as the theater's own creator sheet.
    private func workbenchFrameCreatorModal(lens: ProjectLens, launch: WorkbenchFrameCreatorLaunch) -> some View {
        FrameCreatorModal(
            lens: lens,
            context: launch.context,
            workspaceSize: workbenchWorkspaceSize,
            moodboardItems: library.enabledContentItems.filter { $0.kind == .image },
            moodObservationsById: library.mediaObservationsById,
            hasOpenAICredential: openAICredentialStatus?.isConfigured == true,
            hasCivitaiCredential: civitaiCredentialStatus?.isConfigured == true,
            hasFALCredential: falCredentialStatus?.isConfigured == true,
            hasStabilityCredential: stabilityCredentialStatus?.isConfigured == true,
            isRenderBlocked: library.lensHeroTakeStartBlockReason != nil,
            renderBlockerHelp: library.lensHeroTakeStartBlockReason,
            takeLaneFreeSlots: library.lensHeroTakeLaneFreeSlots,
            formGenerations: library.frameForms.generations.map(\.options).filter { !$0.isEmpty },
            isAnalyzingMoods: library.isAnalyzingMedia,
            onAutoAnalyzeMoods: {
                Task {
                    await library.analyzeUnanalyzedEnabledMedia()
                }
            },
            onOpenAppSettings: onOpenAppSettings,
            onPreviewStyle: { styleImagePreview = $0 },
            onExpandFormOption: { option, styleFitLine in
                await library.expandFrameForms(from: option, styleFitLine: styleFitLine)
            },
            onTransformFormPrompt: { prompt, directive, priorDirectives in
                await library.transformFormPrompt(
                    prompt: prompt,
                    directive: directive,
                    priorDirectives: priorDirectives
                )
            },
            onSubmit: { requests in
                workbenchFrameCreatorLaunch = nil
                // One Task per request: each start AWAITS its render, so the
                // batch must fan out for the take lane to hold them at once.
                for (index, request) in requests.enumerated() {
                    Task {
                        switch launch.context {
                        case .blankFrame(let category):
                            _ = await library.startLensHeroNewTakeRender(
                                lensId: launch.lensId,
                                templateImageId: nil,
                                blankCategory: category,
                                versionId: selectedMediaVersionId(for: lens),
                                request: request
                            )
                        case .plannedFrame(let planned):
                            // The FIRST stack fulfills the planned card in
                            // place; the rest land as ordinary takes from the
                            // same planned template (one card, no twins).
                            if index == 0 {
                                _ = await library.startLensHeroPlanFulfillmentRender(
                                    lensId: launch.lensId,
                                    plannedImageId: planned.imageId,
                                    request: request
                                )
                            } else {
                                _ = await library.startLensHeroNewTakeRender(
                                    lensId: launch.lensId,
                                    templateImageId: planned.imageId,
                                    versionId: selectedMediaVersionId(for: lens),
                                    request: request
                                )
                            }
                        case .variation(let template), .restyle(let template), .groupTake(_, let template):
                            // The VIEWED board rides along so the new take lands
                            // where the operator is looking, not on the
                            // template's own board (which can be invisible when
                            // the frame was opened from a cut or stage).
                            _ = await library.startLensHeroNewTakeRender(
                                lensId: launch.lensId,
                                templateImageId: template.imageId,
                                versionId: selectedMediaVersionId(for: lens),
                                request: request
                            )
                        case .clipMoment(let seed):
                            _ = await library.startClipMomentRender(
                                seed: seed,
                                lensId: launch.lensId,
                                versionId: selectedMediaVersionId(for: lens),
                                request: request
                            )
                        case .stageFrame(let stageId, let appendToCutId):
                            _ = await library.startStageFrameRender(
                                stageId: stageId,
                                appendToCutId: appendToCutId,
                                lensId: launch.lensId,
                                versionId: selectedMediaVersionId(for: lens),
                                request: request
                            )
                        case .shotFrame(let appendToShotId):
                            _ = await library.startShotFrameRender(
                                appendToShotId: appendToShotId,
                                lensId: launch.lensId,
                                versionId: selectedMediaVersionId(for: lens),
                                request: request
                            )
                        }
                        syncDraft()
                    }
                }
            },
            onCancel: {
                workbenchFrameCreatorLaunch = nil
            },
            mentionEntries: library.frameCreatorMentionEntries(for: lens),
            mentionReferenceItems: library.items.filter { $0.kind == .image },
            onEnsureMentionSheet: { entry in
                switch entry.kind {
                case .character:
                    return await library.buildCharacterCompositeSheet(characterId: entry.id)
                case .object:
                    return await library.buildObjectCompositeSheet(objectId: entry.id)
                case .place:
                    return await library.buildPlaceCompositeSheet(placeId: entry.id)
                }
            },
            referenceLibraryItems: library.items.filter { $0.kind == .image },
            initialReferenceItems: launch.referenceMediaIds.compactMap { mediaId in
                library.items.first { $0.mediaId == mediaId && $0.kind == .image }
            },
            generatedFrameCandidates: generatedFrameReferenceCandidates(lenses: library.projectLenses.lenses, items: library.items),
            onAdoptGeneratedFrame: { hero in
                await library.archiveHeroFrameAsReference(hero)
            },
            onUploadReferences: {
                await library.chooseFrameReferenceImages()
            }
        )
    }

    private func lensDetailDisplay(_ lens: ProjectLens, workspaceSize: CGSize = .zero) -> some View {
        let body = lens.body.normalized()
        let resolved = body.resolvedVisualLanguageForSceneStory
        let selectedVersion = selectedMediaVersionId(for: lens)
        let isSequence = body.resolvedMediaPlan.isSequence
        let modalWorkspaceSize = workbenchWorkspaceSize.width > 0 ? workbenchWorkspaceSize : workspaceSize
        // The detail column's true width = the paper's width minus its 24pt inset each
        // side. Constraining to it keeps the stage plates and frames grid wrapping to
        // the visible area (never behind the right sidebar).
        let contentWidth = workspaceSize.width > 0 ? max(320, workspaceSize.width - 48) : 0
        let condensedLanding = lensLandingIsCondensed(
            stageCount: library.shotTimeline.visibleShots.count,
            finalsCount: 0,
            readyFrameCount: lens.readyHeroImages.count
        )
        return VStack(alignment: .leading, spacing: 18) {
            // Landing reads payoff-first: the Scene's claim, look, story thread,
            // and next step before any workbench chrome. Once staged/finaled
            // work exists the hero condenses to one row and the workbench leads.
            lensHeroBand(lens, body: body, condensed: condensedLanding)
            LensVersionTimelineView(
                lens: lens,
                selectedVersionId: Binding(
                    get: { selectedLensMediaVersionByLens[lens.lensId] },
                    set: { selectedLensMediaVersionByLens[lens.lensId] = $0 }
                ),
                compareVersionId: Binding(
                    get: { compareLensMediaVersionByLens[lens.lensId] },
                    set: { compareLensMediaVersionByLens[lens.lensId] = $0 }
                ),
                onRestoreBlend: { versionId in
                    restoreBlend(from: versionId, lens: lens)
                }
            )
            // One ordered workspace followed by one complete inventory. Output
            // selection owns its own sequence; Scenes no longer exposes
            // Stages, Finals, or a hidden Backlot.
            flatShotsCanvasSection(for: lens)
            deletedShotsSection
            sourceMaterialSection(
                for: lens,
                versionId: selectedVersion,
                isSequence: isSequence,
                workspaceSize: modalWorkspaceSize
            )

            lensPlanReferenceSection(body, resolved: resolved)

            LensReadinessChecklistView(
                report: body.readinessReport,
                hasTreatment: body.styleTreatment?.isEmpty == false,
                hasMedia: !lens.sortedHeroImages.isEmpty,
                onJump: { target in
                    switch target {
                    case .editBlend:
                        enterStudioMode()
                    case .regenerateMedia:
                        if let treatment = body.styleTreatment, !treatment.isEmpty {
                            regenerateLens(lens, treatment: treatment)
                        }
                    case .editNotes:
                        break
                    }
                }
            )

            lensEnablementFooter(lens)
        }
        .frame(maxWidth: contentWidth > 0 ? contentWidth : .infinity, alignment: .leading)
    }

    // MARK: - Landing hero

    @ViewBuilder
    private func lensHeroBand(_ lens: ProjectLens, body: LensBody, condensed: Bool) -> some View {
        if condensed {
            condensedLensHeroBand(lens, body: body)
        } else {
            fullLensHeroBand(lens, body: body)
        }
    }

    private func fullLensHeroBand(_ lens: ProjectLens, body: LensBody) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            lensGoalSlicePill(body)
            Text(lensHeroHeadline(body))
                .font(CanonType.editorial(24, weight: .semibold))
                .foregroundStyle(CanonColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            if !body.visualSummary.trimmed.isEmpty {
                Text(body.visualSummary)
                    .font(CanonType.editorial(15))
                    .foregroundStyle(CanonColor.ink.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
            lensStoryThreadCard
            lensPaletteStrip(body.colorPalette)
            lensHeroNextStepRow(lens)
            lensProjectSheetsRow
        }
    }

    /// Quiet affordance for the project's defining sheet set: first build is
    /// explicit here (then saveLensSet keeps it current), share rides the
    /// system share picker. Local drawing only — no provider calls.
    private var lensProjectSheetsRow: some View {
        HStack(spacing: 8) {
            lensPillButton(
                library.hasProjectSheets ? "Refresh Project Sheets" : "Build Project Sheets",
                isPrimary: false
            ) {
                Task {
                    let sheets = await library.buildProjectSheets()
                    if let first = sheets.first {
                        library.revealInFinder(first)
                    }
                }
            }
            .help("Compose the sheets that define this project — Cover, Style, Cast, Frames — plus a re-composition manifest beside them. Drawn locally; no paid renders.")
            if library.hasProjectSheets {
                lensPillButton("Share Sheets", isPrimary: false) {
                    ShareServices.presentPicker(
                        for: library.projectSheetItems().map { URL(fileURLWithPath: $0.path) }
                    )
                }
                .help("Share the sheet set with the macOS share menu")
            }
        }
    }

    private func condensedLensHeroBand(_ lens: ProjectLens, body: LensBody) -> some View {
        HStack(spacing: 10) {
            if let sliceTitle = body.goalSliceTitle, !sliceTitle.isEmpty {
                Text(sliceTitle.uppercased())
                    .font(CanonType.archive(8, weight: .semibold))
                    .kerning(1.2)
                    .foregroundStyle(CanonColor.paper)
                    .padding(.horizontal, 7)
                    .frame(height: 17)
                    .background(Capsule().fill(CanonColor.brass))
            }
            Text(lensHeroHeadline(body))
                .font(CanonType.editorial(15, weight: .semibold))
                .foregroundStyle(CanonColor.ink)
                .lineLimit(1)
            Spacer(minLength: 12)
            if let entry = library.storyLibrary.preferredEntry {
                let signature = storySignature(for: entry)
                let sceneCount = storyThreadSceneCount(entry, signature: signature)
                Button {
                    onOpenGoal()
                } label: {
                    Text(sceneCount > 0
                        ? "⟶ \(storyThreadTitle(entry, signature: signature)) · \(sceneCount) scenes"
                        : "⟶ \(storyThreadTitle(entry, signature: signature))")
                        .font(CanonType.interface(11, weight: .medium))
                        .foregroundStyle(CanonColor.ink.opacity(0.62))
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .help("Open this Story on the Story tab")
            }
            let miniSwatches = Array(uniqueLensColorSwatches(body.colorPalette).prefix(5))
            if !miniSwatches.isEmpty {
                HStack(spacing: 4) {
                    ForEach(miniSwatches) { swatch in
                        Circle()
                            .fill(lensColor(swatch.hex))
                            .frame(width: 8, height: 8)
                            .overlay(Circle().stroke(CanonColor.ink.opacity(0.16), lineWidth: 0.5))
                    }
                }
            }
            if !lensPendingRenderableFrames(lens).isEmpty {
                lensHeroRenderAllPill(lens, compact: true)
            }
        }
    }

    @ViewBuilder
    private func lensGoalSlicePill(_ body: LensBody) -> some View {
        if let sliceTitle = body.goalSliceTitle, !sliceTitle.isEmpty {
            HStack(spacing: 8) {
                Text(sliceTitle.uppercased())
                    .font(CanonType.archive(9, weight: .semibold))
                    .kerning(1.4)
                    .foregroundStyle(CanonColor.paper)
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .background(Capsule().fill(CanonColor.brass))
                if let sliceIntent = body.goalSliceIntent, !sliceIntent.isEmpty {
                    Text(sliceIntent)
                        .font(CanonType.editorial(12.5))
                        .foregroundStyle(CanonColor.ink.opacity(0.62))
                        .lineLimit(2)
                }
            }
        }
    }

    private func lensHeroHeadline(_ body: LensBody) -> String {
        if !body.claim.trimmed.isEmpty { return body.claim }
        if !body.title.trimmed.isEmpty { return body.title }
        return "Scene Plan"
    }

    @ViewBuilder
    private var lensStoryThreadCard: some View {
        if let entry = library.storyLibrary.preferredEntry {
            let signature = storySignature(for: entry)
            let snapshotKey = "\(entry.libraryEntryId):\(entry.currentVersionId)"
            Button {
                onOpenGoal()
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    lensSectionLabel("Story")
                    Text(storyThreadTitle(entry, signature: signature))
                        .font(CanonType.editorial(16, weight: .semibold))
                        .foregroundStyle(CanonColor.ink)
                        .lineLimit(1)
                    if let premise = signature?.premise.trimmed, !premise.isEmpty {
                        Text(premise)
                            .font(CanonType.editorial(13))
                            .foregroundStyle(CanonColor.ink.opacity(0.66))
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    let sceneTitles = landingStorySceneTitles(signature: signature, snapshotKey: snapshotKey)
                    if !sceneTitles.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(Array(sceneTitles.prefix(4).enumerated()), id: \.offset) { index, title in
                                Text("\(index + 1) · \(title)")
                                    .font(CanonType.archive(9, weight: .medium))
                                    .kerning(0.6)
                                    .foregroundStyle(CanonColor.ink.opacity(0.56))
                                    .lineLimit(1)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(Color.white.opacity(0.4), in: Capsule())
                                    .overlay(Capsule().stroke(CanonColor.hairlinePaper.opacity(0.8)))
                            }
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CanonColor.paperInset.opacity(0.58), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlinePaper.opacity(0.72)))
            }
            .buttonStyle(.plain)
            .help("Open this Story on the Story tab")
            .task(id: snapshotKey) {
                landingStorySnapshot = library.sceneStorySnapshot(for: entry)
                landingStorySnapshotKey = snapshotKey
            }
        } else if library.isGeneratingSceneStories {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Stories are being written — the first drafts land on the Story tab automatically.")
                    .font(CanonType.interface(12))
                    .foregroundStyle(CanonColor.ink.opacity(0.6))
            }
        }
    }

    private func storySignature(for entry: ProjectStoryLibraryEntry) -> StorySignatureDocument? {
        if !entry.storySignatureId.trimmed.isEmpty,
           let match = library.storySignatures.first(where: { $0.storySignatureId == entry.storySignatureId }) {
            return match
        }
        guard !entry.projectStoryId.trimmed.isEmpty else { return nil }
        return library.storySignatures.first(where: { $0.projectStoryId == entry.projectStoryId })
    }

    private func storyThreadTitle(_ entry: ProjectStoryLibraryEntry, signature: StorySignatureDocument?) -> String {
        if !entry.title.trimmed.isEmpty { return entry.title }
        if let title = signature?.title.trimmed, !title.isEmpty { return title }
        return "Untitled Story"
    }

    private func storyThreadSceneCount(_ entry: ProjectStoryLibraryEntry, signature: StorySignatureDocument?) -> Int {
        let snapshotKey = "\(entry.libraryEntryId):\(entry.currentVersionId)"
        if landingStorySnapshotKey == snapshotKey, let snapshot = landingStorySnapshot, !snapshot.scenes.isEmpty {
            return snapshot.scenes.count
        }
        return signature?.sceneFunctionSequence.count ?? 0
    }

    private func landingStorySceneTitles(signature: StorySignatureDocument?, snapshotKey: String) -> [String] {
        if landingStorySnapshotKey == snapshotKey, let snapshot = landingStorySnapshot {
            let titles = snapshot.scenes
                .sorted { $0.order < $1.order }
                .map { $0.title.trimmed }
                .filter { !$0.isEmpty }
            if !titles.isEmpty { return titles }
        }
        return signature?.sceneFunctionSequence ?? []
    }

    private func lensHeroRenderAllPill(_ lens: ProjectLens, compact: Bool = false) -> some View {
        let pending = lensPendingRenderableFrames(lens)
        let blockReason = library.lensHeroTakeStartBlockReason
        return lensPillButton(
            compact
                ? "Render \(pending.count) planned"
                : "Render all planned · \(pending.count) frame\(pending.count == 1 ? "" : "s")",
            isPrimary: true,
            disabled: blockReason != nil
        ) {
            Task { _ = await library.renderLensMedia(lensId: lens.lensId, scope: .all) }
        }
        .help(blockReason ?? "Renders each planned frame with its saved prompt and style — \(pending.count) paid provider renders, one at a time. Pause in Activity stops the batch.")
    }

    @ViewBuilder
    private func lensHeroNextStepRow(_ lens: ProjectLens) -> some View {
        if !lensPendingRenderableFrames(lens).isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                lensHeroRenderAllPill(lens)
                Text("Each frame is a paid render. Open any planned card to art-direct it in the Frame Creator instead.")
                    .font(CanonType.interface(11))
                    .foregroundStyle(CanonColor.ink.opacity(0.5))
            }
        }
    }

    // MARK: - Plan reference

    @ViewBuilder
    private func lensPlanReferenceSection(_ body: LensBody, resolved: LensResolvedVisualLanguage) -> some View {
        if body.hasDraftContent {
            let chipSections: [(title: String, values: [String])] = [
                ("Motifs", uniqueNonEmpty(resolved.motifs + body.motifTerms)),
                ("Texture / Material", uniqueNonEmpty(resolved.materials + body.textureMaterialTerms)),
                ("Composition / Framing", uniqueNonEmpty(resolved.composition + body.compositionTerms)),
                ("Pacing / Energy", uniqueNonEmpty(resolved.pacingEnergy + body.pacingEnergyTerms)),
            ].filter { !$0.values.isEmpty }
            if !chipSections.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18)], alignment: .leading, spacing: 20) {
                    ForEach(chipSections, id: \.title) { section in
                        lensChipSection(section.title, values: section.values)
                    }
                }
            }
            if !body.styleIngredients.isEmpty {
                lensIngredientSummary(body.styleIngredients)
            }
            if !(body.mustPreserve.isEmpty && body.mustAvoid.isEmpty) {
                Divider()
                    .background(CanonColor.hairlinePaper)
                VStack(alignment: .leading, spacing: 10) {
                    lensSectionLabel("Guardrails")
                    HStack(alignment: .top, spacing: 18) {
                        lensGuardrailPanel(
                            title: "Must Preserve",
                            values: body.mustPreserve,
                            tint: CanonColor.olive
                        )
                        lensGuardrailPanel(
                            title: "Must Avoid",
                            values: body.mustAvoid,
                            tint: CanonColor.rust
                        )
                    }
                }
            }
        } else {
            lensPlanningStatusBand
        }
    }

    private var lensPlanningStatusBand: some View {
        HStack(spacing: 8) {
            if library.isGeneratingInitialDraftLenses {
                ProgressView()
                    .controlSize(.small)
                Text("Scene Plan details are being composed…")
                    .font(CanonType.interface(12, weight: .medium))
                    .foregroundStyle(CanonColor.ink.opacity(0.62))
            } else {
                Text("This Scene Plan has no saved details yet.")
                    .font(CanonType.interface(12, weight: .medium))
                    .foregroundStyle(CanonColor.ink.opacity(0.62))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CanonColor.paperInset.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlinePaper.opacity(0.7)))
    }

    /// Copies an old media version's exact treatment (stored as a lossless snapshot on its
    /// images) back into the saved treatment via the normal apply path.
    private func restoreBlend(from versionId: String, lens: ProjectLens) {
        let snapshot = lens.heroImages(mediaVersion: versionId)
            .compactMap { LensStyleTreatment.fromSnapshotIdentifier($0.sourceRecipeId) }
            .first
        guard let snapshot else {
            lastCommitMessage = "This version predates blend snapshots — nothing to restore"
            lastCommitSucceeded = false
            return
        }
        lensTreatmentWeightDrafts = [:]
        applyStyleTreatment(snapshot)
        lastCommitMessage = "Restored blend \(snapshot.weightSummary) — regenerate to render it"
        lastCommitSucceeded = true
    }

    private func lensEnablementFooter(_ lens: ProjectLens) -> some View {
        HStack {
            Spacer()
            Button {
                toggleSelectedLensEnabled()
            } label: {
                Text(lens.enabled ? "Disable Scene Plan" : "Enable Scene Plan")
                    .font(CanonType.interface(12, weight: .medium))
                    .foregroundStyle(lens.enabled ? CanonColor.ink.opacity(0.48) : CanonColor.olive.opacity(0.72))
                    .padding(.horizontal, 2)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .disabled(library.isGeneratingLensHero)
            .opacity(library.isGeneratingLensHero ? 0.36 : 1)
            .help(lens.enabled ? "Stop this Scene Plan from guiding Scenes" : "Let this Scene Plan guide Scenes")
        }
        .padding(.top, 2)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    @ViewBuilder
    private func lensPaletteStrip(_ swatches: [LensColorSwatch]) -> some View {
        let normalized = uniqueLensColorSwatches(swatches)
        if !normalized.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if !copiedLensSwatchHex.isEmpty {
                    Text("Copied \(copiedLensSwatchHex)")
                        .font(CanonType.interface(11, weight: .semibold))
                        .foregroundStyle(CanonColor.olive)
                        .transition(.opacity)
                }
                HStack(alignment: .top, spacing: 12) {
                    ForEach(normalized) { swatch in
                        let hex = normalizedLensSwatchHex(swatch.hex)
                        Button {
                            copyLensSwatchHex(hex)
                        } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(lensColor(hex))
                                    .frame(height: 62)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(CanonColor.ink.opacity(0.16), lineWidth: 1)
                                            .allowsHitTesting(false)
                                    )
                                Text(swatch.name.trimmed.isEmpty ? "Swatch" : swatch.name)
                                    .font(CanonType.interface(12, weight: .semibold))
                                    .foregroundStyle(CanonColor.ink.opacity(0.80))
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(hex)
                                    .font(CanonType.archive(10, weight: .medium))
                                    .foregroundStyle(CanonColor.ink.opacity(0.48))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        .buttonStyle(.plain)
                        .frame(minWidth: 112, maxWidth: .infinity, alignment: .topLeading)
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                        .help("Copy \(lensPaletteHelp(swatch))")
                    }
                }
            }
        }
    }

    private func copyLensSwatchHex(_ hex: String) {
        guard !hex.trimmed.isEmpty else { return }
        copyTextToPasteboard(hex)
        withAnimation(.easeOut(duration: 0.16)) {
            copiedLensSwatchHex = hex
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            if copiedLensSwatchHex == hex {
                withAnimation(.easeOut(duration: 0.16)) {
                    copiedLensSwatchHex = ""
                }
            }
        }
    }

    private func lensChipSection(_ title: String, values: [String], tint: Color = CanonColor.brass.opacity(0.72)) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            lensSectionLabel(title)
            if values.isEmpty {
                Text("No saved values.")
                    .font(CanonType.editorial(13))
                    .foregroundStyle(CanonColor.ink.opacity(0.44))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 8) {
                    ForEach(values.prefix(12), id: \.self) { value in
                        Text(value)
                            .font(CanonType.interface(12, weight: .medium))
                            .foregroundStyle(CanonColor.ink.opacity(0.82))
                            .lineLimit(2)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .stroke(tint.opacity(0.35), lineWidth: 1)
                            )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func lensIngredientSummary(_ ingredients: [LensStyleIngredient]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            lensSectionLabel("Source Ingredients")
            VStack(alignment: .leading, spacing: 8) {
                ForEach(ingredients.filter(\.enabled).prefix(6)) { ingredient in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ingredient.title)
                            .font(CanonType.interface(13, weight: .semibold))
                            .foregroundStyle(CanonColor.ink)
                            .lineLimit(1)
                        Text(uniqueNonEmpty([ingredient.role, ingredient.presentationUse, ingredient.narrativeUse]).joined(separator: " · "))
                            .font(CanonType.editorial(12))
                            .foregroundStyle(CanonColor.ink.opacity(0.58))
                            .lineLimit(2)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CanonColor.paperInset.opacity(0.58), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlinePaper.opacity(0.72)))
                }
            }
        }
    }

    private func lensGuardrailPanel(title: String, values: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(CanonType.archive(10, weight: .semibold))
                .foregroundStyle(tint)
            if values.isEmpty {
                Text("No saved values.")
                    .font(CanonType.editorial(13))
                    .foregroundStyle(CanonColor.ink.opacity(0.44))
            } else {
                Text(values.prefix(8).joined(separator: " · "))
                    .font(CanonType.editorial(15))
                    .foregroundStyle(CanonColor.ink.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(tint.opacity(0.22)))
    }

    private func lensSectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(CanonType.archive(10, weight: .semibold))
            .foregroundStyle(CanonColor.ink.opacity(0.52))
    }

    private func lensPaletteHelp(_ swatch: LensColorSwatch) -> String {
        uniqueNonEmpty([swatch.name, normalizedLensSwatchHex(swatch.hex), swatch.role, swatch.note]).joined(separator: " · ")
    }

    private func lensColor(_ hex: String) -> Color {
        let cleaned = hex.trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let intValue = Int(cleaned, radix: 16) else {
            return CanonColor.paperInset
        }
        return Color(
            .sRGB,
            red: Double((intValue >> 16) & 0xFF) / 255,
            green: Double((intValue >> 8) & 0xFF) / 255,
            blue: Double(intValue & 0xFF) / 255,
            opacity: 1
        )
    }

    private func normalizedLensSwatchHex(_ hex: String) -> String {
        let cleaned = hex.trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()
        guard cleaned.count == 6, Int(cleaned, radix: 16) != nil else {
            return hex.trimmed
        }
        return "#\(cleaned)"
    }

    /// The header bar only exists for transient edit feedback and the two setup
    /// actions (generate the first heroes, save a new frame). With no title or
    /// status line left, it stays collapsed until one of those applies.
    private var lensEditorActionBarHasContent: Bool {
        if selectedScratch != nil { return true }
        if let selectedLens, selectedLens.sortedHeroImages.isEmpty { return true }
        return !commitFeedbackLine.isEmpty
    }

    private var lensEditorActionBar: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                if !commitFeedbackLine.isEmpty {
                    Text(commitFeedbackLine)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(commitFeedbackColor)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let selectedLens, selectedLens.sortedHeroImages.isEmpty {
                lensActionButton("Generate Heroes", isPrimary: false, disabled: library.isGeneratingLensHero) {
                    Task {
                        _ = await library.generateLensHero(lensId: selectedLens.lensId)
                        syncDraft()
                    }
                }
                .zIndex(6)
            }

            if selectedScratch != nil {
                lensActionButton("Save Scene Plan", isPrimary: true, disabled: !canSaveLensEdits) {
                    saveActiveLensEdits()
                }
                .zIndex(6)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(CanonColor.paper)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(CanonColor.hairlinePaper)
                .frame(height: 1)
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
    }

    private func lensActionButton(
        _ title: String,
        isPrimary: Bool,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(CanonType.interface(12, weight: .semibold))
                .foregroundStyle(CanonColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(minWidth: 92, minHeight: 36)
                .padding(.horizontal, 8)
                .background(
                    isPrimary ? CanonColor.softGold.opacity(0.88) : Color.white.opacity(0.64),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isPrimary ? CanonColor.brass.opacity(0.82) : CanonColor.hairlinePaper)
                        .allowsHitTesting(false)
                )
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.44 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .zIndex(7)
    }

    private var initialDraftLensButtonTitle: String {
        if library.isGeneratingInitialDraftLenses {
            return "Planning..."
        }
        if library.initialDraftLensGenerationProgress.isFailed {
            return "Retry Plan"
        }
        return "Plan Frames"
    }

    private var initialDraftLensesCTA: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("Frames")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(CanonColor.ink)
                        Text(initialLensReadyLabel)
                            .font(CanonType.archive(9, weight: .semibold))
                            .kerning(0.8)
                            .foregroundStyle(initialDraftLensGenerateBlockers.isEmpty ? CanonColor.olive : CanonColor.brass)
                            .padding(.horizontal, 7)
                            .frame(height: 20)
                            .background(
                                Capsule().fill((initialDraftLensGenerateBlockers.isEmpty ? CanonColor.olive : CanonColor.brass).opacity(0.12))
                            )
                    }
                    Text("Plan four scenery frames, two character studies, and one object study from the saved Goal.")
                        .font(.system(size: 13))
                        .foregroundStyle(CanonColor.ink.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                    initialLensSetupBadges
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 8) {
                    lensPillButton(
                        initialDraftLensButtonTitle,
                        isPrimary: true,
                        disabled: !initialDraftLensGenerateBlockers.isEmpty
                    ) {
                        Task {
                            if await library.planLens() {
                                reconcileWorkbenchSelection()
                            }
                            syncDraft()
                        }
                    }
                    if library.canRetryLensContextRetrieval || library.isRetrievingLensContext {
                        lensPillButton(
                            library.isRetrievingLensContext ? "Retrieving Context..." : "Retry Frame Context",
                            isPrimary: false,
                            disabled: library.isRetrievingLensContext
                        ) {
                            library.retryLensContextRetrieval()
                        }
                    }
                }
            }

            // While a planning run is live, the real per-frame progress rows
            // below are the sole truth — the hardcoded preview cards would
            // render right above them and read as stuck "Planned" frames.
            if !library.isGeneratingInitialDraftLenses && !library.initialDraftLensGenerationProgress.isActive {
                initialLensPlanningTheater
            }

            initialLensSetupStatusPanel

            if !initialDraftLensGenerateBlockers.isEmpty {
                Text("Planning starts automatically once these are ready — or press Plan Frames.")
                    .font(CanonType.interface(11))
                    .foregroundStyle(CanonColor.ink.opacity(0.52))
            }

            if library.initialDraftLensGenerationProgress.isActive {
                initialDraftLensProgress
            }

            if library.isGeneratingInitialDraftLenses || library.isRetrievingLensContext {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(library.isRetrievingLensContext ? library.lensContextStatus : library.aestheticStatus)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CanonColor.ink.opacity(0.66))
                }
            }
        }
    }

    private var initialLensReadyLabel: String {
        if library.isGeneratingInitialDraftLenses {
            return "PLANNING"
        }
        return initialDraftLensGenerateBlockers.isEmpty ? "READY" : "SETUP"
    }

    private var initialLensPlannedTakes: [InitialLensPlannedTake] {
        [
            InitialLensPlannedTake(
                title: "Scenery Frame 1",
                role: "Place candidate",
                detail: "A render-ready environment view grounded in the Goal graph.",
                iconName: "photo"
            ),
            InitialLensPlannedTake(
                title: "Scenery Frame 2",
                role: "Place candidate",
                detail: "A second environment view for visual continuity.",
                iconName: "photo"
            ),
            InitialLensPlannedTake(
                title: "Scenery Frame 3",
                role: "Place candidate",
                detail: "A third environment view with concrete world detail.",
                iconName: "photo"
            ),
            InitialLensPlannedTake(
                title: "Scenery Frame 4",
                role: "Place candidate",
                detail: "A fourth environment view ready for rendering.",
                iconName: "photo"
            ),
            InitialLensPlannedTake(
                title: "Character Study 1",
                role: "Actor candidate",
                detail: "A recurring figure study grounded in the frame world.",
                iconName: "person.crop.rectangle"
            ),
            InitialLensPlannedTake(
                title: "Character Study 2",
                role: "Actor candidate",
                detail: "A second recurring figure study for the same Scene Plan.",
                iconName: "person.crop.rectangle"
            ),
            InitialLensPlannedTake(
                title: "Object Study",
                role: "Prop candidate",
                detail: "One meaningful object that carries the world's story.",
                iconName: "cube.box"
            )
        ]
    }

    private var initialLensSetupBadges: some View {
        HStack(spacing: 6) {
            initialLensTinyBadge("Frame Stack · OpenAI Base")
            initialLensTinyBadge(openAICredentialStatus?.isConfigured == true ? "Available" : "Needs OpenAI key")
            initialLensTinyBadge(civitaiCredentialStatus?.isConfigured == true ? "WAN 2.7 available" : "WAN 2.7 needs key")
            initialLensTinyBadge("Style · Goal graph cast")
        }
    }

    private var initialLensPlanningTheater: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Preview — what planning creates")
                .font(CanonType.archive(9, weight: .semibold))
                .kerning(1.2)
                .foregroundStyle(CanonColor.ink.opacity(0.44))
            initialLensPlanningSection(
                title: "SCENERY",
                scopeLabel: "4 planned frames",
                takes: Array(initialLensPlannedTakes[0..<4])
            )
            initialLensPlanningSection(
                title: "CHARACTERS",
                scopeLabel: "2 planned studies",
                takes: Array(initialLensPlannedTakes[4..<6])
            )
            initialLensPlanningSection(
                title: "OBJECTS",
                scopeLabel: "1 planned study",
                takes: [initialLensPlannedTakes[6]]
            )
        }
        .padding(14)
        .background(CanonColor.paperInset.opacity(0.46), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlinePaper.opacity(0.78)))
    }

    private func initialLensPlanningSection(
        title: String,
        scopeLabel: String,
        takes: [InitialLensPlannedTake]
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 8) {
                Text(title)
                    .font(CanonType.archive(8.5, weight: .semibold))
                    .kerning(1.4)
                    .foregroundStyle(CanonColor.muted)
                Spacer(minLength: 0)
                Text(scopeLabel)
                    .font(CanonType.interface(10.5, weight: .semibold))
                    .foregroundStyle(CanonColor.ink.opacity(0.40))
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(Capsule().fill(CanonColor.paperInset.opacity(0.70)))
                    .overlay(Capsule().stroke(CanonColor.hairlinePaper.opacity(0.70)))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(takes) { take in
                        initialLensPlannedTakeCard(take)
                            .frame(width: 196)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func initialLensPlannedTakeCard(_ take: InitialLensPlannedTake) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: take.iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CanonColor.brass)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(CanonColor.brass.opacity(0.12)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(take.title)
                        .font(CanonType.interface(12, weight: .semibold))
                        .foregroundStyle(CanonColor.ink)
                        .lineLimit(1)
                    Text(take.role)
                        .font(CanonType.archive(8.5, weight: .semibold))
                        .kerning(0.6)
                        .foregroundStyle(CanonColor.ink.opacity(0.48))
                        .lineLimit(1)
                }
            }

            Text(take.detail)
                .font(CanonType.interface(11))
                .foregroundStyle(CanonColor.ink.opacity(0.62))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 5) {
                initialLensTinyBadge("Base Take")
                initialLensTinyBadge("gpt-image-2")
                initialLensTinyBadge("Companion locked")
            }
        }
        .padding(11)
        .frame(minHeight: 132, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.36), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(CanonColor.hairlinePaper.opacity(0.95), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
        )
    }

    private func initialLensTinyBadge(_ text: String) -> some View {
        Text(text)
            .font(CanonType.archive(8, weight: .semibold))
            .foregroundStyle(CanonColor.ink.opacity(0.56))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background(Capsule().fill(CanonColor.paperInset.opacity(0.78)))
            .overlay(Capsule().stroke(CanonColor.hairlinePaper.opacity(0.74)))
    }

    private var initialLensSetupStatusPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: initialDraftLensGenerateBlockers.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(initialDraftLensGenerateBlockers.isEmpty ? CanonColor.olive : CanonColor.brass)
                Text(initialDraftLensGenerateBlockers.isEmpty ? "Ready to render planned takes." : "Setup can continue; rendering waits on these requirements.")
                    .font(CanonType.interface(12, weight: .semibold))
                    .foregroundStyle(CanonColor.ink.opacity(0.70))
                    .lineLimit(2)
            }
            if !initialDraftLensGenerateBlockers.isEmpty {
                ForEach(initialDraftLensGenerateBlockers, id: \.self) { blocker in
                    Text(blocker)
                        .font(CanonType.interface(11.5, weight: .medium))
                        .foregroundStyle(CanonColor.ink.opacity(0.58))
                        .lineLimit(2)
                }
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.30), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlinePaper.opacity(0.70)))
    }

    private var initialDraftLensProgress: some View {
        let progress = library.initialDraftLensGenerationProgress
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(progress.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CanonColor.ink)
                if !progress.detail.trimmed.isEmpty {
                    Text(progress.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(CanonColor.ink.opacity(0.62))
                }
            }
            ProgressView(value: progress.fractionCompleted)
                .tint(CanonColor.brass)
            if !progress.heroRows.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(progress.heroRows.enumerated()), id: \.element.imageId) { _, row in
                        HStack(spacing: 8) {
                            generationStatusIcon(row.status)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.lensTitle.trimmed.isEmpty ? "Scene Plan" : row.lensTitle)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(CanonColor.ink)
                                    .lineLimit(1)
                                Text(row.providerLabel.trimmed.isEmpty ? "Provider" : row.providerLabel)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(CanonColor.ink.opacity(0.54))
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(generationStatusLabel(row.status))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(CanonColor.ink.opacity(0.58))
                        }
                        .padding(8)
                        .background(Color.white.opacity(0.42), in: RoundedRectangle(cornerRadius: 7))
                    }
                }
            } else if !progress.lensTitles.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(progress.lensTitles.enumerated()), id: \.offset) { index, title in
                        HStack(spacing: 8) {
                            generationStatusIcon(generationStatus(progress, index: index))
                            Text(title.trimmed.isEmpty ? "Scene Plan \(index + 1)" : title)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(CanonColor.ink)
                                .lineLimit(1)
                            Spacer()
                            Text(generationStatusLabel(generationStatus(progress, index: index)))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(CanonColor.ink.opacity(0.58))
                        }
                        .padding(8)
                        .background(Color.white.opacity(0.42), in: RoundedRectangle(cornerRadius: 7))
                    }
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.38), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlinePaper))
    }

    private var styleIngredients: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Source style ingredients")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CanonColor.ink.opacity(0.64))
            if draftBody.styleIngredients.isEmpty {
                Text("Add an aesthetic from the library or describe a custom ingredient.")
                    .font(.system(size: 12))
                    .foregroundStyle(CanonColor.ink.opacity(0.58))
            }
            ForEach(draftBody.styleIngredients) { ingredient in
                VStack(alignment: .leading, spacing: 6) {
                    Text(ingredient.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CanonColor.ink)
                    Text(ingredient.narrativeUse)
                        .font(.system(size: 12))
                        .foregroundStyle(CanonColor.ink.opacity(0.62))
                        .lineLimit(2)
                    if !ingredient.paletteTerms.isEmpty || !ingredient.motifTerms.isEmpty {
                        Text((ingredient.paletteTerms + ingredient.motifTerms).prefix(8).joined(separator: " · "))
                            .font(.system(size: 11))
                            .foregroundStyle(CanonColor.ink.opacity(0.58))
                            .lineLimit(1)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CanonColor.paper.opacity(0.62), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func generationStatus(_ progress: InitialDraftLensGenerationProgress, index: Int) -> String {
        guard progress.heroStatuses.indices.contains(index) else { return "queued" }
        return progress.heroStatuses[index]
    }

    @ViewBuilder
    private func generationStatusIcon(_ status: String) -> some View {
        let normalized = status.trimmed.lowercased()
        if normalized == "ready" {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(CanonColor.olive)
        } else if normalized == "failed" {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(CanonColor.rust)
        } else if normalized == "generating" {
            ProgressView()
                .controlSize(.small)
        } else {
            Image(systemName: "circle")
                .foregroundStyle(CanonColor.ink.opacity(0.38))
        }
    }

    private func generationStatusLabel(_ status: String) -> String {
        switch status.trimmed.lowercased() {
        case "ready":
            return "Ready"
        case "failed":
            return "Failed"
        case "generating":
            return "Generating"
        default:
            return "Queued"
        }
    }

    private var isInitialLensEmptyMode: Bool {
        library.projectLenses.lenses.isEmpty
            && library.projectLenses.messages.isEmpty
    }

    private var hasMeaningfulScratchDrafts: Bool {
        library.projectLenses.scratchDrafts.contains { scratch in
            lensBodyHasContent(scratch.body)
        }
    }

    private func syncProjectScope() {
        let projectId = library.currentProject?.projectId ?? ""
        guard scopedProjectId != projectId else { return }
        scopedProjectId = projectId
        workbenchSelection = .initial
        openCutIds = []
        hasSeededOpenCutRows = false
        sourceMaterialSearchQuery = ""
        didRequestManualScratch = false
        lastCommitMessage = ""
        srefSelectionStatus = ""
        downloadingSREFReferenceIds = []
    }

    private func reconcileWorkbenchSelection() {
        switch workbenchSelection {
        case .creating(let scratchId):
            if library.projectLenses.scratchDrafts.contains(where: { $0.scratchId == scratchId }) {
                return
            }
        case .editingLens(let lensId):
            if library.projectLenses.lenses.contains(where: { $0.lensId == lensId }) {
                return
            }
        case .initial:
            break
        }

        if let firstLens = library.projectLenses.lenses.first {
            workbenchSelection = .editingLens(lensId: firstLens.lensId)
        } else {
            workbenchSelection = .initial
        }
    }

    private func lensBodyHasContent(_ body: LensBody) -> Bool {
        body.hasDraftContent
    }

    private var shouldShowLensVersionSidebar: Bool {
        selectedLens != nil && !isInitialLensEmptyMode
    }

    private var expandedPlace: ProjectPlace? {
        expandedPlaceId.flatMap { library.projectPlaces.place(withId: $0) }
    }

    private func placeDetailOverlay(place: ProjectPlace, lens: ProjectLens) -> some View {
        HStack(spacing: 0) {
            Color.black.opacity(0.16)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.18)) { expandedPlaceId = nil }
                }
            ScenesPlaceDetailView(
                library: library,
                lens: lens,
                versionId: selectedMediaVersionId(for: lens),
                place: place,
                onClose: {
                    withAnimation(.easeOut(duration: 0.18)) { expandedPlaceId = nil }
                },
                onLaunchFrameCreator: { context in
                    expandedPlaceId = nil
                    workbenchFrameCreatorLaunch = WorkbenchFrameCreatorLaunch(
                        lensId: lens.lensId,
                        context: context
                    )
                },
                onOpenFrame: { frame in
                    expandedPlaceId = nil
                    openSelectedLensHeroPreview(heroImage: frame)
                }
            )
            .frame(width: 620)
            .frame(maxHeight: .infinity)
            .overlay(alignment: .leading) {
                Rectangle().fill(CanonColor.hairlinePaper).frame(width: 1)
            }
        }
        .transition(.opacity)
        .zIndex(30)
    }

    private func lensPillButton(
        _ title: String,
        isPrimary: Bool,
        disabled: Bool = false,
        textOpacity: Double = 1,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(CanonType.interface(12, weight: .semibold))
                .foregroundStyle(CanonColor.ink.opacity(textOpacity))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    isPrimary ? CanonColor.softGold.opacity(0.82) : Color.white.opacity(0.46),
                    in: RoundedRectangle(cornerRadius: 7)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(isPrimary ? CanonColor.brass.opacity(0.78) : CanonColor.hairlinePaper)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.44 : 1)
    }

    private var selectedLens: ProjectLens? {
        guard case .editingLens(let lensId) = workbenchSelection else { return nil }
        return library.projectLenses.lenses.first { $0.lensId == lensId }
    }

    private var selectedScratch: LensScratchDraft? {
        guard case .creating(let scratchId) = workbenchSelection else { return nil }
        return library.projectLenses.scratchDrafts.first { $0.scratchId == scratchId }
    }

    private var hasEditableLensSelection: Bool {
        selectedScratch != nil || selectedLens != nil
    }

    private var canSaveLensEdits: Bool {
        hasEditableLensSelection && !isSavingNewLens && !library.isGeneratingLensHero
    }

    private var canMarkSelectedLensReady: Bool {
        false
    }

    private var persistedDraftBody: LensBody? {
        if let selectedScratch {
            return selectedScratch.body
        }
        if let selectedLens {
            return selectedLens.body
        }
        return nil
    }

    private var hasUnsavedLensEdits: Bool {
        guard let persistedDraftBody else { return false }
        return draftBody.normalized() != persistedDraftBody.normalized()
    }

    private var commitFeedbackLine: String {
        if hasUnsavedLensEdits {
            return "Unsaved edits"
        }
        return lastCommitMessage
    }

    private var commitFeedbackColor: Color {
        if hasUnsavedLensEdits {
            return CanonColor.brass.opacity(0.82)
        }
        return lastCommitSucceeded ? CanonColor.olive : CanonColor.rust
    }

    private var selectedLensNeedsHeroGeneration: Bool {
        guard let selectedLens else { return false }
        let heroImages = selectedLens.sortedHeroImages
        guard heroImages.count >= 2 else { return true }
        if heroImages.contains(where: { $0.status == "generating" || $0.status == "queued" }) {
            return false
        }
        return selectedLens.readyHeroImages.count < 2
    }

    private func saveActiveLensEdits() {
        if selectedScratch != nil {
            saveScratchAsLens()
            return
        }
        guard let selectedLens else {
            lastCommitMessage = "Select the project Scene Plan first"
            lastCommitSucceeded = false
            return
        }
        guard commitActiveDraft() else { return }
        if selectedLensNeedsHeroGeneration {
            Task {
                let succeeded = await library.generateLensHero(lensId: selectedLens.lensId)
                if !succeeded {
                    lastCommitMessage = library.aestheticStatus.trimmed.isEmpty
                        ? "Frame generation could not start"
                        : library.aestheticStatus
                    lastCommitSucceeded = false
                }
                syncDraft()
            }
        }
    }

    private func saveScratchAsLens() {
        guard let scratchId = selectedScratch?.scratchId else {
            lastCommitMessage = "Create a draft first"
            lastCommitSucceeded = false
            return
        }
        isSavingNewLens = true
        let didCommit = commitActiveDraft(showFeedback: false)
        Task {
            defer {
                isSavingNewLens = false
            }
            if didCommit, let lensId = library.saveLensScratchAsNewLens(scratchId: scratchId) {
                workbenchSelection = .editingLens(lensId: lensId)
                syncDraft()
                lastCommitMessage = "Scene Plan saved"
                lastCommitSucceeded = true
                let succeeded = await library.generateLensHero(lensId: lensId)
                if !succeeded {
                    lastCommitMessage = library.aestheticStatus.trimmed.isEmpty
                        ? "Frame generation could not start"
                        : library.aestheticStatus
                    lastCommitSucceeded = false
                }
                syncDraft()
            } else {
                lastCommitMessage = library.aestheticStatus.trimmed.isEmpty ? "Scene Plan save failed" : library.aestheticStatus
                lastCommitSucceeded = false
            }
        }
    }

    private func markSelectedLensReady() {
        guard let selectedLens else {
            lastCommitMessage = "Select the project Scene Plan first"
            lastCommitSucceeded = false
            return
        }
        guard commitActiveDraft() else { return }
        let report = draftBody.readinessReport
        if library.markLensReady(selectedLens.lensId) {
            syncDraft()
            let issueCount = report.blockingIssues.count + report.warnings.count
            lastCommitMessage = issueCount > 0 ? "Scene Plan marked Ready with \(issueCount) warning\(issueCount == 1 ? "" : "s")" : "Scene Plan marked Ready"
            lastCommitSucceeded = true
        } else {
            lastCommitMessage = library.aestheticStatus.trimmed.isEmpty ? "Scene Plan Ready failed" : library.aestheticStatus
            lastCommitSucceeded = false
        }
    }

    private func toggleSelectedLensEnabled() {
        guard let selectedLens else {
            lastCommitMessage = "Select the project Scene Plan first"
            lastCommitSucceeded = false
            return
        }
        let nextValue = !selectedLens.enabled
        if library.setLensEnabled(lensId: selectedLens.lensId, enabled: nextValue) {
            syncDraft()
            lastCommitMessage = nextValue ? "Scene Plan enabled" : "Scene Plan disabled"
            lastCommitSucceeded = true
        } else {
            lastCommitMessage = library.aestheticStatus.trimmed.isEmpty ? "Scene Plan update failed" : library.aestheticStatus
            lastCommitSucceeded = false
        }
    }

    private func openSelectedLensHeroPreview(
        heroImage selectedHeroImage: ProjectLensHeroImage? = nil,
        cutNavigation: CutFramePreviewNavigation? = nil
    ) {
        guard let selectedLens,
              let heroImage = selectedHeroImage ?? selectedLens.primaryHeroImage,
              !heroImage.imagePath.trimmed.isEmpty
        else {
            return
        }
        heroPreviewActionStatus = ""
        magnifiedLensHeroPreview = lensHeroPreviewRequest(lens: selectedLens, heroImage: heroImage)
        cutFramePreviewNavigation = cutNavigation
        lensHeroPreviewZoom = 1
    }

    /// Resolves a frame by IMAGE id across every lens: the preview request's
    /// `lensId` can go stale for frames opened from cuts and stages, and a
    /// miss must STATE itself in the modal rather than silently no-op (the
    /// old guard returned before even dismissing).
    private func resolvedHeroImageAcrossLenses(
        imageId: String
    ) -> (lens: ProjectLens, heroImage: ProjectLensHeroImage)? {
        for lens in library.projectLenses.lenses {
            if let heroImage = lens.sortedHeroImages.first(where: { $0.imageId == imageId }) {
                return (lens, heroImage)
            }
        }
        return nil
    }

    /// The frame detail's create actions: Variation, or the style-forward
    /// Restyle. Closes the preview so the new take's generating card is
    /// visible in the theater once the creator submits.
    private func launchFrameCreatorFromPreview(imageId: String, restyle: Bool) {
        guard let resolved = resolvedHeroImageAcrossLenses(imageId: imageId) else {
            heroPreviewActionStatus = "That frame no longer exists in the Scene Plan"
            return
        }
        heroPreviewActionStatus = ""
        magnifiedLensHeroPreview = nil
        cutFramePreviewNavigation = nil
        workbenchFrameCreatorLaunch = WorkbenchFrameCreatorLaunch(
            lensId: resolved.lens.lensId,
            context: restyle ? .restyle(of: resolved.heroImage) : .variation(of: resolved.heroImage)
        )
    }

    /// One Excursion dive: resolves the parent's lens by image id (cut-opened
    /// frames go stale by lensId), composes the modal's exact default reframe
    /// prompt, fires the punch-in kernel, and registers the placement as a
    /// single "Punch-In" Undo (which removes the two entries only — the
    /// child render keeps running and lands on the lens board regardless).
    private func startPunchInFromExcursion(
        cutId: String,
        afterEntryId: String,
        parentImageId: String,
        spec: LensReframeSpec,
        onPlaced: @escaping @MainActor (ShotPunchInPlacement) -> Void
    ) async -> Bool {
        guard let resolved = resolvedHeroImageAcrossLenses(imageId: parentImageId) else {
            return false
        }
        let stack = RenderStackRegistry.shared.fallback
        let promptBody = LensReframeComposer.renderDefaultPromptBody(
            spec: spec,
            parent: resolved.heroImage,
            model: stack.reframePromptModel,
            promptSettings: library.projectPromptSettings
        )
        stagePictureUndo.applyState = { shotId, snapshot in
            library.restoreShotPictureState(shotId: shotId, snapshot: snapshot)
        }
        return await library.startPunchInExcursion(
            cutId: cutId,
            afterEntryId: afterEntryId,
            lensId: resolved.lens.lensId,
            parentImageId: parentImageId,
            spec: spec,
            stack: stack,
            promptBody: promptBody,
            onPlaced: { placement in
                stagePictureUndo.registerEdit(
                    shotId: cutId,
                    old: placement.edit.before,
                    new: placement.edit.after,
                    actionName: "Punch-In",
                    undoManager: undoManager
                )
                onPlaced(placement)
            }
        )
    }

    /// The Frame detail's browse sequence. Cut-opened frames step through the
    /// originating CUT's ready Frame entries (clips and unresolved
    /// placeholders remain in the CUT but are not valid destinations);
    /// board-opened frames step through the frame's lens board — every ready
    /// render, collapsed to one stop per version group (the open image
    /// represents its own group, else the group's active version).
    private func heroPreviewBrowseItems() -> [LensHeroPreviewBrowseItem] {
        if let navigation = cutFramePreviewNavigation,
           let cut = library.shotTimeline.shots.first(where: { $0.shotId == navigation.cutId }) {
            let frameLookup = library.projectWideFrameLookup
            return cut.entries.compactMap { entry in
                guard !entry.isClip,
                      let frame = frameLookup[entry.frameImageId],
                      frame.status == "ready",
                      !frame.imagePath.trimmed.isEmpty else {
                    return nil
                }
                return LensHeroPreviewBrowseItem(
                    id: entry.entryId,
                    imageId: frame.imageId,
                    imagePath: frame.imagePath
                )
            }
        }
        guard let magnifiedLensHeroPreview,
              let resolved = resolvedHeroImageAcrossLenses(imageId: magnifiedLensHeroPreview.imageId) else {
            return []
        }
        let currentImageId = magnifiedLensHeroPreview.imageId
        var representativeByGroup: [String: ProjectLensHeroImage] = [:]
        var groupOrder: [String] = []
        for image in resolved.lens.readyHeroImages {
            let key = image.renderVersion?.renderVersionGroupId.trimmed.nilIfEmpty ?? image.imageId
            if representativeByGroup[key] == nil { groupOrder.append(key) }
            let incumbent = representativeByGroup[key]
            let replaces: Bool
            if image.imageId == currentImageId {
                replaces = true
            } else if incumbent == nil {
                replaces = true
            } else if incumbent?.imageId == currentImageId {
                replaces = false
            } else {
                replaces = image.renderVersion?.isActive == true && incumbent?.renderVersion?.isActive != true
            }
            if replaces { representativeByGroup[key] = image }
        }
        return groupOrder.compactMap { key in
            representativeByGroup[key].map {
                LensHeroPreviewBrowseItem(id: $0.imageId, imageId: $0.imageId, imagePath: $0.imagePath)
            }
        }
    }

    private func currentHeroPreviewBrowseId() -> String {
        cutFramePreviewNavigation?.entryId ?? magnifiedLensHeroPreview?.imageId ?? ""
    }

    /// ←/→ stepping through `heroPreviewBrowseItems()`, wrapping in both
    /// directions.
    private func navigateHeroPreview(by direction: Int) {
        let items = heroPreviewBrowseItems()
        guard direction != 0, items.count > 1,
              let currentIndex = items.firstIndex(where: { $0.id == currentHeroPreviewBrowseId() }) else {
            return
        }
        let nextIndex = ((currentIndex + direction) % items.count + items.count) % items.count
        openHeroPreviewBrowseItem(items[nextIndex])
    }

    /// Jump straight to a browse stop (the strip's thumbnail tap and the
    /// arrow keys both land here). The lens is re-resolved by image id — the
    /// stale-lensId law — so cut browsing works across frames from different
    /// lenses, and a cut context keeps its cut with the destination entry.
    private func openHeroPreviewBrowseItem(_ item: LensHeroPreviewBrowseItem) {
        guard let resolved = resolvedHeroImageAcrossLenses(imageId: item.imageId) else {
            heroPreviewActionStatus = "That frame no longer exists in the Scene Plan"
            return
        }
        heroPreviewActionStatus = ""
        magnifiedLensHeroPreview = lensHeroPreviewRequest(lens: resolved.lens, heroImage: resolved.heroImage)
        if let navigation = cutFramePreviewNavigation {
            cutFramePreviewNavigation = CutFramePreviewNavigation(cutId: navigation.cutId, entryId: item.id)
        }
        lensHeroPreviewZoom = 1
    }

    private func lensHeroPreviewRequest(lensId: String, imageId: String) -> LensHeroPreviewRequest? {
        guard let lens = library.projectLenses.lenses.first(where: { $0.lensId == lensId }),
              let image = lens.sortedHeroImages.first(where: { $0.imageId == imageId }),
              !image.imagePath.trimmed.isEmpty else {
            return nil
        }
        return lensHeroPreviewRequest(lens: lens, heroImage: image)
    }

    private func lensHeroPreviewRequest(lens: ProjectLens, heroImage: ProjectLensHeroImage) -> LensHeroPreviewRequest {
        LensHeroPreviewRequest(
            lensId: lens.lensId,
            title: lens.body.title.trimmed.isEmpty ? "Frame" : lens.body.title.trimmed,
            imagePath: heroImage.imagePath,
            prompt: heroImage.prompt,
            sourcePrompt: heroImage.sourcePrompt,
            status: heroImage.status,
            imageId: heroImage.imageId,
            providerLabel: heroImage.label.trimmed.isEmpty ? heroImage.provider.capitalized : heroImage.label,
            model: heroImage.model,
            requestId: heroImage.requestId,
            traceId: heroImage.traceId,
            errorMessage: heroImage.errorMessage,
            isActiveVersion: heroImage.renderVersion?.isActive == true,
            versionItems: lensHeroPreviewVersionItems(lens: lens, heroImage: heroImage),
            reframeCast: library.lensReframeCastCandidates(for: lens),
            reframeSummary: heroImage.reframe?.modeLabel ?? "",
            reframeParentImageId: heroImage.reframe?.parentImageId ?? "",
            motionArtifact: heroImage.motionArtifact,
            narration: heroImage.narrationArtifact,
            promptEnrichmentSummary: heroImage.promptEnrichmentSummary,
            promptEnrichmentDisabled: heroImage.promptEnrichmentDisabled
        )
    }

    private func lensHeroPreviewVersionItems(lens: ProjectLens, heroImage: ProjectLensHeroImage) -> [LensHeroPreviewVersionItem] {
        guard let groupId = heroImage.renderVersion?.renderVersionGroupId.trimmed.nilIfEmpty else { return [] }
        let versions = lens.sortedHeroImages
            .filter { image in
                image.renderVersion?.renderVersionGroupId.trimmed == groupId
                    && image.status.trimmed.lowercased() == "ready"
                    && !image.imagePath.trimmed.isEmpty
                    && !image.disabled
                    && FileManager.default.fileExists(atPath: image.imagePath)
            }
            .sorted { lhs, rhs in
                let lhsVersion = lhs.renderVersion?.versionNumber ?? 0
                let rhsVersion = rhs.renderVersion?.versionNumber ?? 0
                if lhsVersion == rhsVersion {
                    return lhs.imageId < rhs.imageId
                }
                return lhsVersion < rhsVersion
            }
        guard versions.count > 1 else { return [] }
        return versions.map { image in
            LensHeroPreviewVersionItem(
                imageId: image.imageId,
                imagePath: image.imagePath,
                prompt: image.prompt,
                status: image.status,
                providerLabel: image.label.trimmed.isEmpty ? image.provider.capitalized : image.label,
                model: image.model,
                requestId: image.requestId,
                traceId: image.traceId,
                errorMessage: image.errorMessage,
                isActiveVersion: image.renderVersion?.isActive == true,
                versionNumber: max(1, image.renderVersion?.versionNumber ?? 1)
            )
        }
    }

    private func retrySelectedLensHeroImage(_ heroImage: ProjectLensHeroImage) {
        guard let selectedLens else { return }
        Task {
            _ = await library.retryLensHeroImage(
                lensId: selectedLens.lensId,
                imageId: heroImage.imageId
            )
            syncDraft()
        }
    }

    private var filteredMessages: [ProjectLensMessage] {
        let scratchId = selectedScratch?.scratchId
        let lensId = selectedLens?.lensId
        return library.projectLenses.messages.filter { message in
            message.targetScratchId == scratchId || message.targetLensId == lensId
        }
    }

    private var lensEditMessagesForSelectedLens: [ProjectLensEditMessage] {
        guard let lensId = selectedLens?.lensId else { return [] }
        return library.projectLenses.lensEditMessages.filter { $0.lensId == lensId }
    }

    private var selectedSREFStyleReferences: [SREFStyleImageReference] {
        draftBody.styleIngredients
            .flatMap(\.sourceReferenceIds)
            .compactMap { SREFStyleImageReference.decodeSourceReferenceId($0) }
    }

    private var selectedSREFStyleReferenceIds: Set<String> {
        Set(selectedSREFStyleReferences.map(\.id))
    }

    private var initialDraftLensBlockers: [String] {
        library.lensGenerationBlockers
    }

    private var initialDraftLensGenerateBlockers: [String] {
        uniqueNonEmpty(initialDraftLensBlockers + initialLensStackBlockers)
    }

    private var initialLensStackBlockers: [String] {
        openAICredentialStatus?.isConfigured == true
            ? []
            : ["OpenAI Base requires an OpenAI credential in App Settings."]
    }

    private var openAICredentialStatus: CredentialStatus? {
        library.videoProviderCredentialStatuses.first { $0.provider == .openAI }
    }

    private var civitaiCredentialStatus: CredentialStatus? {
        library.videoProviderCredentialStatuses.first { $0.provider == .civitai }
    }

    private var falCredentialStatus: CredentialStatus? {
        library.videoProviderCredentialStatuses.first { $0.provider == .fal }
    }

    private var stabilityCredentialStatus: CredentialStatus? {
        library.videoProviderCredentialStatuses.first { $0.provider == .stability }
    }

    private func lensField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CanonColor.ink.opacity(0.64))
            TextField(label, text: text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .foregroundColor(CanonColor.ink)
                .onSubmit {
                    _ = commitActiveDraft()
                }
        }
    }

    private func lensEditor(_ label: String, text: Binding<String>, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CanonColor.ink.opacity(0.64))
            TextEditor(text: text)
                .font(.system(size: 13))
                .foregroundColor(CanonColor.ink)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: height)
                .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlinePaper))
        }
    }

    private func lensArray(_ label: String, values: Binding<[String]>) -> some View {
        lensEditor(label, text: Binding(
            get: { values.wrappedValue.joined(separator: "\n") },
            set: { values.wrappedValue = uniqueNonEmpty($0.components(separatedBy: .newlines)) }
        ), height: 68)
    }

    private func resolvedLanguageStringBinding(_ keyPath: WritableKeyPath<LensResolvedVisualLanguage, String>) -> Binding<String> {
        Binding(
            get: {
                resolvedLanguageDraft()[keyPath: keyPath]
            },
            set: { newValue in
                var language = resolvedLanguageDraft()
                language[keyPath: keyPath] = newValue
                draftBody.resolvedVisualLanguage = language.normalized()
            }
        )
    }

    private func resolvedLanguageArrayBinding(_ keyPath: WritableKeyPath<LensResolvedVisualLanguage, [String]>) -> Binding<[String]> {
        Binding(
            get: {
                resolvedLanguageDraft()[keyPath: keyPath]
            },
            set: { newValue in
                var language = resolvedLanguageDraft()
                language[keyPath: keyPath] = uniqueNonEmpty(newValue)
                draftBody.resolvedVisualLanguage = language.normalized()
            }
        )
    }

    private func resolvedLanguageDraft() -> LensResolvedVisualLanguage {
        if let resolved = draftBody.resolvedVisualLanguage?.normalized(), !resolved.isEmpty {
            return resolved
        }
        return LensResolvedVisualLanguage(look: draftBody.visualSummary.trimmed).normalized()
    }

    private func syncDraft() {
        if let scratch = selectedScratch {
            draftBody = scratch.body
        } else if let selectedLens {
            draftBody = selectedLens.body
        } else {
            draftBody = .empty()
        }
    }

    @discardableResult
    private func commitActiveDraft(showFeedback: Bool = true) -> Bool {
        guard hasEditableLensSelection else {
            if showFeedback {
                lastCommitMessage = "Select the project Scene Plan first"
                lastCommitSucceeded = false
            }
            return false
        }

        guard hasUnsavedLensEdits else {
            if showFeedback {
                lastCommitMessage = "No unsaved edits"
                lastCommitSucceeded = true
            }
            return true
        }

        let didSave: Bool
        let savedMessage: String
        if let scratch = selectedScratch {
            didSave = library.commitLensScratch(scratchId: scratch.scratchId, body: draftBody)
            savedMessage = "Scratch saved"
        } else if let selectedLens {
            didSave = library.commitLensBody(lensId: selectedLens.lensId, body: draftBody)
            savedMessage = "Scene Plan saved"
        } else {
            didSave = false
            savedMessage = ""
        }

        if didSave {
            syncDraft()
            if showFeedback {
                lastCommitMessage = savedMessage
                lastCommitSucceeded = true
            }
        } else if showFeedback {
            lastCommitMessage = library.aestheticStatus.trimmed.isEmpty ? "Scene Plan save failed" : library.aestheticStatus
            lastCommitSucceeded = false
        }
        return didSave
    }

    private func loadSREFCatalog() async {
        srefCatalogStatus = "Loading SREF style references"
        srefCatalogLoadError = ""
        do {
            let catalog = try await SREFReferenceCatalogRuntime.shared.loadCatalog()
            srefCatalog = catalog
            srefCatalogStatus = "\(catalog.displayItems.count) style reference\(catalog.displayItems.count == 1 ? "" : "s")"
        } catch {
            srefCatalog = .empty
            srefCatalogStatus = ""
            srefCatalogLoadError = "SREF catalog unavailable: \(error.localizedDescription)"
        }
    }

    private func toggleLensMediaAnchor(_ item: MediaItemRecord) {
        guard let scratchId = selectedScratch?.scratchId else { return }
        let shouldEnable = !draftBody.referenceMediaIds.contains(item.mediaId)
        if library.setReferenceMediaForLensScratch(mediaId: item.mediaId, scratchId: scratchId, enabled: shouldEnable) {
            syncDraft()
            lastCommitMessage = shouldEnable ? "Scene Plan anchor selected" : "Scene Plan anchor removed"
            lastCommitSucceeded = true
        } else {
            lastCommitMessage = library.aestheticStatus.trimmed.isEmpty ? "Scene Plan anchor update failed" : library.aestheticStatus
            lastCommitSucceeded = false
        }
    }

    private func toggleSREFStyleReference(_ item: SREFReferenceCatalogItem) {
        guard let scratchId = selectedScratch?.scratchId,
              let reference = item.styleImageReference(in: srefCatalog) else {
            return
        }
        let normalized = reference.normalized()
        if selectedSREFStyleReferenceIds.contains(normalized.id) {
            if library.setSREFStyleReferenceForLensScratch(normalized, scratchId: scratchId, enabled: false) {
                syncDraft()
                srefSelectionStatus = "Removed \(normalized.title)"
                lastCommitMessage = "Style reference removed"
                lastCommitSucceeded = true
            } else {
                srefSelectionStatus = library.aestheticStatus.trimmed.isEmpty ? "Style reference update failed" : library.aestheticStatus
                lastCommitMessage = "Style reference update failed"
                lastCommitSucceeded = false
            }
            return
        }

        guard !downloadingSREFReferenceIds.contains(normalized.id) else { return }
        downloadingSREFReferenceIds.insert(normalized.id)
        srefSelectionStatus = "Downloading \(normalized.title)"
        Task {
            do {
                _ = try await SREFReferenceImageCache.shared.cachedFileURL(for: normalized)
                await MainActor.run {
                    downloadingSREFReferenceIds.remove(normalized.id)
                    if library.setSREFStyleReferenceForLensScratch(normalized, scratchId: scratchId, enabled: true) {
                        syncDraft()
                        srefSelectionStatus = "Selected \(normalized.title)"
                        lastCommitMessage = "Style reference selected"
                        lastCommitSucceeded = true
                    } else {
                        srefSelectionStatus = library.aestheticStatus.trimmed.isEmpty ? "Style reference update failed" : library.aestheticStatus
                        lastCommitMessage = "Style reference update failed"
                        lastCommitSucceeded = false
                    }
                }
            } catch {
                await MainActor.run {
                    downloadingSREFReferenceIds.remove(normalized.id)
                    srefSelectionStatus = "Could not verify \(normalized.title): \(error.localizedDescription)"
                    lastCommitMessage = "Style reference failed"
                    lastCommitSucceeded = false
                }
            }
        }
    }
}

private struct LensCreateMediaThumbnail: View {
    let item: MediaItemRecord

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                CanonColor.mediaCardHover
                if let image = NSImage(contentsOfFile: item.thumbnailPath) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: size.width, height: size.height)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: item.kind == .video ? "film" : "photo")
                            .font(.system(size: 22, weight: .semibold))
                        Text(item.kind == .video ? "Video" : "Image")
                            .font(CanonType.archive(9, weight: .semibold))
                    }
                    .foregroundStyle(CanonColor.bone.opacity(0.68))
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        }
    }
}

private struct SREFStyleReferenceThumbnail: View {
    let urlString: String

    var body: some View {
        ZStack {
            CanonColor.mediaCardHover
            if let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .controlSize(.small)
                            .tint(CanonColor.brass)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .clipped()
    }

    private var placeholder: some View {
        VStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 21, weight: .semibold))
            Text("SREF")
                .font(CanonType.archive(9, weight: .semibold))
        }
        .foregroundStyle(CanonColor.bone.opacity(0.68))
    }
}

/// One stop on the Frame detail's browse strip — the sequence ←/→ steps
/// through. Cut-opened frames browse the CUT's ready frame entries (`id` =
/// entryId, since a frame can be placed twice); board-opened frames browse
/// the lens board's ready frames, one per version group (`id` = imageId).
struct LensHeroPreviewBrowseItem: Identifiable, Hashable {
    let id: String
    let imageId: String
    let imagePath: String
}

struct LensHeroPreviewVersionItem: Identifiable, Hashable {
    let imageId: String
    let imagePath: String
    let prompt: String
    let status: String
    let providerLabel: String
    let model: String
    let requestId: String
    let traceId: String
    let errorMessage: String
    let isActiveVersion: Bool
    let versionNumber: Int

    var id: String { imageId }
}

struct LensHeroPreviewRequest: Identifiable, Hashable {
    let lensId: String
    let title: String
    let imagePath: String
    let prompt: String
    let sourcePrompt: String
    let status: String
    let imageId: String
    let providerLabel: String
    let model: String
    let requestId: String
    let traceId: String
    let errorMessage: String
    let isActiveVersion: Bool
    let versionItems: [LensHeroPreviewVersionItem]
    var reframeCast: [LensReframeCastCandidate] = []
    var reframeSummary: String = ""
    var reframeParentImageId: String = ""
    var motionArtifact: LensMotionArtifact?
    var narration: LensNarrationArtifact?
    /// Prompt-transform observability for the Generation-prompt panel.
    var promptEnrichmentSummary: String = ""
    var promptEnrichmentDisabled: Bool = false

    var id: String {
        "\(lensId):\(imageId)"
    }

    func activeCopy() -> LensHeroPreviewRequest {
        LensHeroPreviewRequest(
            lensId: lensId,
            title: title,
            imagePath: imagePath,
            prompt: prompt,
            sourcePrompt: sourcePrompt,
            status: status,
            imageId: imageId,
            providerLabel: providerLabel,
            model: model,
            requestId: requestId,
            traceId: traceId,
            errorMessage: errorMessage,
            isActiveVersion: true,
            versionItems: versionItems.map { item in
                LensHeroPreviewVersionItem(
                    imageId: item.imageId,
                    imagePath: item.imagePath,
                    prompt: item.prompt,
                    status: item.status,
                    providerLabel: item.providerLabel,
                    model: item.model,
                    requestId: item.requestId,
                    traceId: item.traceId,
                    errorMessage: item.errorMessage,
                    isActiveVersion: item.imageId == imageId ? true : item.isActiveVersion,
                    versionNumber: item.versionNumber
                )
            },
            reframeCast: reframeCast,
            reframeSummary: reframeSummary,
            reframeParentImageId: reframeParentImageId,
            motionArtifact: motionArtifact,
            narration: narration,
            promptEnrichmentSummary: promptEnrichmentSummary,
            promptEnrichmentDisabled: promptEnrichmentDisabled
        )
    }
}

private struct LensHeroPreviewVersionToolbar: View {
    let isActiveVersion: Bool
    let canMakeActive: Bool
    let currentImageId: String
    let versionItems: [LensHeroPreviewVersionItem]
    let onMakeActive: () -> Void
    let onOpenVersion: (LensHeroPreviewVersionItem) -> Void
    /// The create actions, promoted from the header where they read as
    /// chrome: nil hides (non-ready frames pass nil here and `onRetry`
    /// instead).
    var onVariation: (() -> Void)? = nil
    var onRestyle: (() -> Void)? = nil
    /// Attached Frame motion. A non-nil callback keeps the action visible;
    /// `animationBlockReason` disables paid submission while stating why.
    var onAnimate: (() -> Void)? = nil
    var animationTitle: String = "Animate"
    var animationBlockReason: String = ""
    var isAnimating: Bool = false
    /// Starts a new Scene with this Frame as its first shot. nil hides.
    var onStartScene: (() -> Void)? = nil
    /// Enters full-screen Excursion mode — nil off cut-opened frames.
    var onEnterExcursion: (() -> Void)? = nil
    var onRetry: (() -> Void)? = nil
    /// Non-ready status line ("This take is FAILED — …"); empty when ready.
    var takeStatus: String = ""
    /// Refusal/miss feedback rendered in rust; empty = quiet.
    var actionStatus: String = ""
    var onDelete: (() -> Void)? = nil
    /// The ←/→ browse sequence rendered as a thumbnail strip; the current
    /// frame is highlighted and any other stop is one click away.
    var browseItems: [LensHeroPreviewBrowseItem] = []
    var currentBrowseId: String = ""
    var onOpenBrowseItem: ((LensHeroPreviewBrowseItem) -> Void)? = nil
    var onNavigate: ((Int) -> Void)? = nil
    var footer: AnyView = AnyView(EmptyView())
    @State private var deleteArmed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            browseSection
            if onAnimate != nil || onStartScene != nil || onVariation != nil || onRestyle != nil || onRetry != nil || !takeStatus.isEmpty {
                Text("Create")
                    .font(CanonType.archive(8.5, weight: .semibold))
                    .kerning(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(CanonColor.muted)
                if let onAnimate {
                    Button {
                        onAnimate()
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: isAnimating ? "hourglass" : "film")
                                .font(.system(size: 13, weight: .semibold))
                            Text(animationTitle)
                                .font(CanonType.interface(11, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(CanonPrimaryButtonStyle(isFullWidth: true))
                    .disabled(isAnimating || !animationBlockReason.isEmpty)
                    .help(animationBlockReason.isEmpty
                        ? "Animate this Frame with WAN 2.5 — the motion stays attached to the Frame"
                        : animationBlockReason)
                    if !animationBlockReason.isEmpty {
                        Text(animationBlockReason)
                            .font(CanonType.interface(9.5, weight: .medium))
                            .foregroundStyle(CanonColor.rust)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let onStartScene {
                    Button {
                        onStartScene()
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "rectangle.stack.badge.plus")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Start New Scene")
                                .font(CanonType.interface(11, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(CanonPrimaryButtonStyle(isFullWidth: true))
                    .help("Start a new Scene with this Frame as its first shot — it opens on the stage")
                }
                if let onVariation {
                    Button {
                        onVariation()
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "square.on.square")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Variation")
                                .font(CanonType.interface(11, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(CanonSecondaryButtonStyle(isFullWidth: true))
                    .help("New variation of this frame — opens the Frame Creator seeded from it")
                }
                if let onRestyle {
                    Button {
                        onRestyle()
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "paintpalette")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Restyle")
                                .font(CanonType.interface(11, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(CanonSecondaryButtonStyle(isFullWidth: true))
                    .help("Change this frame's look — opens the Frame Creator seeded from it, style wheel first")
                }
                if let onEnterExcursion {
                    Button {
                        onEnterExcursion()
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "plus.magnifyingglass")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Excursion")
                                .font(CanonType.interface(11, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(CanonSecondaryButtonStyle(isFullWidth: true))
                    .help("Full-screen dive: click a detail to punch in — each dive lands a there-and-back excursion in the cut")
                }
                if !takeStatus.isEmpty {
                    Text(takeStatus)
                        .font(CanonType.interface(9.5, weight: .medium))
                        .foregroundStyle(CanonColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let onRetry {
                    Button {
                        onRetry()
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Retry render")
                                .font(CanonType.interface(11, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(CanonSecondaryButtonStyle(isFullWidth: true))
                    .help("Re-fire this take's render with its saved request")
                }
                Rectangle()
                    .fill(CanonColor.hairlineDark.opacity(0.72))
                    .frame(height: 1)
                    .padding(.vertical, 2)
            }
            Text("Version")
                .font(CanonType.archive(8.5, weight: .semibold))
                .kerning(1.2)
                .textCase(.uppercase)
                .foregroundStyle(CanonColor.muted)
            Button {
                onMakeActive()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: isActiveVersion ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(.system(size: 13, weight: .semibold))
                    Text(isActiveVersion ? "Active version" : "Make active version")
                        .font(CanonType.interface(11, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(CanonSecondaryButtonStyle(isFullWidth: true))
            .disabled(isActiveVersion || !canMakeActive)
            .help(isActiveVersion ? "This is the active version" : "Make this version active")
            // Only a frame that ACTUALLY has multiple versions gets the
            // browser — with versions unused, user testing read it as pure
            // noise: disruptive and, until versions exist, useless.
            if versionItems.count > 1 {
                Rectangle()
                    .fill(CanonColor.hairlineDark.opacity(0.72))
                    .frame(height: 1)
                    .padding(.vertical, 2)
                ScrollView(.vertical, showsIndicators: versionItems.count > 3) {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(versionItems) { item in
                            versionBrowserItem(item)
                        }
                    }
                    .padding(.trailing, versionItems.count > 3 ? 4 : 0)
                }
            }
            if !actionStatus.isEmpty {
                Text(actionStatus)
                    .font(CanonType.interface(9.5, weight: .medium))
                    .foregroundStyle(CanonColor.rust)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            footer
            if let onDelete {
                Rectangle()
                    .fill(CanonColor.hairlineDark.opacity(0.72))
                    .frame(height: 1)
                    .padding(.vertical, 2)
                // Destructive, so it takes two clicks: the first arms (turns red), the
                // second within the window confirms — a fast double-click does both.
                HStack(spacing: 6) {
                    if deleteArmed {
                        Text("Click again to delete")
                            .font(CanonType.interface(9.5, weight: .medium))
                            .foregroundStyle(CanonColor.rust)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: deleteArmed ? "trash.fill" : "trash")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(deleteArmed ? CanonColor.rust : CanonColor.muted)
                        .frame(width: 30, height: 30)
                        .background(RoundedRectangle(cornerRadius: 7).fill(deleteArmed ? CanonColor.rust.opacity(0.14) : Color.clear))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(deleteArmed ? CanonColor.rust.opacity(0.55) : CanonColor.hairlineDark.opacity(0.6), lineWidth: 1))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if deleteArmed {
                                deleteArmed = false
                                onDelete()
                            } else {
                                deleteArmed = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                                    deleteArmed = false
                                }
                            }
                        }
                        .help(deleteArmed ? "Click again to delete this render" : "Delete this render — double-click (it's hidden, not erased)")
                }
                .animation(.easeOut(duration: 0.14), value: deleteArmed)
            }
        }
        .padding(14)
        .frame(width: 218, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 8).fill(CanonColor.sidebar.opacity(0.94)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.brass.opacity(0.42), lineWidth: 1))
        .padding(.vertical, 18)
        .padding(.trailing, 18)
    }

    /// The browse strip: little thumbnails of every stop the arrow keys step
    /// through (the CUT's frames, or the lens board), current highlighted.
    /// Absent with fewer than two stops — a strip of one is pure noise.
    @ViewBuilder
    private var browseSection: some View {
        if browseItems.count > 1, let onOpenBrowseItem {
            let currentIndex = browseItems.firstIndex { $0.id == currentBrowseId }
            HStack(spacing: 6) {
                Text("Browse")
                    .font(CanonType.archive(8.5, weight: .semibold))
                    .kerning(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(CanonColor.muted)
                Spacer(minLength: 0)
                if let currentIndex {
                    Text("\(currentIndex + 1) of \(browseItems.count)")
                        .font(CanonType.archive(8, weight: .medium))
                        .foregroundStyle(CanonColor.muted)
                }
                if let onNavigate {
                    Button { onNavigate(-1) } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9, weight: .semibold))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(CanonUtilityButtonStyle())
                    .help("Previous frame — ← also steps")
                    Button { onNavigate(1) } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(CanonUtilityButtonStyle())
                    .help("Next frame — → also steps")
                }
            }
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: browseItems.count > 9) {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 56, maximum: 70), spacing: 4)],
                        spacing: 4
                    ) {
                        ForEach(browseItems) { item in
                            browseThumb(item, onOpen: onOpenBrowseItem)
                                .id(item.id)
                        }
                    }
                }
                .frame(maxHeight: 118)
                .onAppear { proxy.scrollTo(currentBrowseId) }
                .onChange(of: currentBrowseId) { _, newId in
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(newId) }
                }
            }
            Rectangle()
                .fill(CanonColor.hairlineDark.opacity(0.72))
                .frame(height: 1)
                .padding(.vertical, 2)
        }
    }

    private func browseThumb(
        _ item: LensHeroPreviewBrowseItem,
        onOpen: @escaping (LensHeroPreviewBrowseItem) -> Void
    ) -> some View {
        let isCurrent = item.id == currentBrowseId
        return Button {
            onOpen(item)
        } label: {
            Color.clear
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay {
                    if let image = StripThumbnailCache.shared.image(path: item.imagePath, maxPixel: 160) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        CanonColor.paperInset
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(
                        isCurrent ? CanonColor.softGold.opacity(0.95) : CanonColor.hairlineDark.opacity(0.6),
                        lineWidth: isCurrent ? 1.6 : 1
                    )
            )
            .opacity(isCurrent ? 1 : 0.82)
        }
        .buttonStyle(.plain)
        .disabled(isCurrent)
        .help(isCurrent ? "This frame" : "Open this frame")
    }

    private func versionBrowserItem(_ item: LensHeroPreviewVersionItem) -> some View {
        let isCurrent = item.imageId == currentImageId
        return Button {
            onOpenVersion(item)
        } label: {
            ZStack(alignment: .topLeading) {
                if let image = StripThumbnailCache.shared.image(path: item.imagePath) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    CanonColor.paperInset
                }
                Text("V\(max(1, item.versionNumber))")
                    .font(CanonType.archive(8, weight: .bold))
                    .kerning(0.5)
                    .foregroundStyle(CanonColor.paper)
                    .padding(.horizontal, 5)
                    .frame(height: 18)
                    .background(Capsule().fill(CanonColor.brass.opacity(0.95)))
                    .padding(5)
                if item.isActiveVersion {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(CanonColor.olive)
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(CanonColor.paper.opacity(0.88)))
                                .padding(5)
                        }
                        Spacer()
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 108)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isCurrent ? CanonColor.softGold.opacity(0.9) : CanonColor.brass.opacity(item.isActiveVersion ? 0.55 : 0.26), lineWidth: isCurrent ? 1.4 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isCurrent)
        .help(isCurrent ? "Current preview" : "Open V\(max(1, item.versionNumber))")
    }
}

struct LensHeroPreviewModal: View {
    let request: LensHeroPreviewRequest
    let promptSettings: ProjectPromptSettingsDocument
    /// The ←/→ browse sequence (cut entries or the lens board) and where the
    /// open frame sits in it; the toolbar renders it as a thumbnail strip.
    var browseItems: [LensHeroPreviewBrowseItem] = []
    var currentBrowseId: String = ""
    var onOpenBrowseItem: ((LensHeroPreviewBrowseItem) -> Void)? = nil
    @Binding var zoomScale: CGFloat
    let reframeSubmissionBlockReason: String
    let isNarrating: Bool
    let hasOpenAICredential: Bool
    let hasFALCredential: Bool
    let hasStabilityCredential: Bool
    let onMakeActive: (LensHeroPreviewRequest) -> Void
    let onOpenVersion: (LensHeroPreviewVersionItem) -> Void
    let onReframe: (LensReframeSpec, RenderStack, String) -> Void
    let onOpenRelated: (String) -> Void
    let onNarrate: (String) -> Void
    let onOpenSettings: () -> Void
    /// Opens the Frame Creator seeded from this frame (ready frames only).
    var onVariation: (() -> Void)? = nil
    /// Style-forward Frame Creator launch — the operator came to change this
    /// frame's LOOK (ready frames only).
    var onRestyle: (() -> Void)? = nil
    /// Runs the existing attached WAN 2.5 motion workflow. The action stays in
    /// this shared modal so Media, SCENES, and SCENES v2 cannot drift.
    var onAnimate: (() -> Void)? = nil
    var animationBlockReason: String = ""
    var isAnimating: Bool = false
    /// Starts a new Scene with this Frame as its first shot. nil hides.
    var onStartScene: (() -> Void)? = nil
    /// Re-fires this take's render (non-ready frames — the failed/stuck case
    /// that used to open a detail view with zero actions).
    var onRetry: (() -> Void)? = nil
    /// Refusal/miss feedback from the workbench, rendered inside the modal —
    /// the workbench's aestheticStatus chrome is invisible under this
    /// full-cover overlay.
    var actionStatus: String = ""
    let onDelete: () -> Void
    /// -1 steps left and +1 steps right through an originating CUT, when any.
    var onNavigate: ((Int) -> Void)? = nil
    /// Enters full-screen Excursion mode on this frame's cut placement —
    /// non-nil only when the frame was opened FROM a cut.
    var onEnterExcursion: (() -> Void)? = nil
    let onClose: () -> Void
    @State private var reframeFocusCenter: CGPoint?
    /// Reticle edge in source pixels; grows when the corner grip is dragged, floored at the base size.
    @State private var reframeReticleEdge: CGFloat = LensReframeMetrics.reticleEdgePixels
    /// Reticle tilt in degrees, clockwise-positive on screen; the generation is
    /// straightened so the tilted selection's top edge becomes the output's top.
    @State private var reframeRotationDegrees: Double = 0
    @State private var reframeMode: String = LensReframeSpec.zoomMode
    @State private var reframeViewDirection: String = LensReframeViewDirection.north.rawValue
    @State private var reframeCastId: String = ""
    /// Viewpoint only: ride the drawn top-down camera map (default on).
    @State private var reframeIncludeCameraMap = true
    @State private var reframeStandardStack: RenderStack = RenderStackRegistry.shared.fallback
    /// Zoom-out defaults to OpenAI like the other reframe modes: FAL outpaint
    /// succeeds at the transport layer but returns bad continuations (seen
    /// in user testing), so it stays PICKABLE, never default.
    @State private var reframeZoomOutStack: RenderStack = RenderStackRegistry.shared.fallback
    @State private var reframeZoomOutSourceScale = LensReframeMetrics.zoomOutDefaultSourceScale
    @State private var reframeZoomOutCenter = CGPoint(x: 0.5, y: 0.5)
    @State private var reframeFidelity: LensReframeFidelity = .fallback
    @State private var reframePromptBody: String = ""
    @State private var reframePromptBaseline: String = ""
    @State private var reframePromptDrafts: [String: String] = [:]
    @State private var reframePromptBaselines: [String: String] = [:]
    @StateObject private var narrationPlayer = LensNarrationPlayer()
    /// Claims key focus for ←/→ browsing (the ShotPlayerTransportKeys focus
    /// law: claim first responder before any text field can).
    @FocusState private var browseKeysFocused: Bool

    var body: some View {
        ImagePreviewModalShell(
            title: request.title,
            subtitle: "\(request.providerLabel.trimmed.isEmpty ? "Scene Plan" : request.providerLabel) frame",
            metadataText: metadataText,
            imagePath: request.imagePath,
            displayedImageSize: displayedImageSize,
            zoomScale: $zoomScale,
            detailPlacement: .below,
            missingImageTitle: "Frame could not be loaded",
            missingImageSubtitle: request.imagePath,
            imageActionHeight: narrationBarHeight,
            imageOverlay: AnyView(
                LensHeroPreviewVersionToolbar(
                    isActiveVersion: request.isActiveVersion,
                    canMakeActive: canReframe,
                    currentImageId: request.imageId,
                    versionItems: request.versionItems,
                    onMakeActive: {
                        onMakeActive(request)
                    },
                    onOpenVersion: { item in
                        onOpenVersion(item)
                    },
                    onVariation: canReframe ? onVariation : nil,
                    onRestyle: canReframe ? onRestyle : nil,
                    onAnimate: canReframe ? onAnimate : nil,
                    animationTitle: animationTitle,
                    animationBlockReason: animationBlockReason,
                    isAnimating: isAnimating,
                    onStartScene: canReframe ? onStartScene : nil,
                    onEnterExcursion: canReframe ? onEnterExcursion : nil,
                    onRetry: canReframe ? nil : onRetry,
                    takeStatus: canReframe
                        ? ""
                        : "This take is \(request.status.trimmed.isEmpty ? "not ready" : request.status.trimmed.uppercased()) — not renderable yet.",
                    actionStatus: actionStatus,
                    onDelete: { onDelete() },
                    browseItems: browseItems,
                    currentBrowseId: currentBrowseId,
                    onOpenBrowseItem: onOpenBrowseItem,
                    onNavigate: onNavigate,
                    footer: AnyView(
                        LensReframePanel(
                            hasFocus: reframeFocusCenter != nil,
                            focusSummary: reframeFocusSummary,
                            cropPreview: reframeCropPreview,
                            canReframe: canReframe,
                            submissionBlockReason: reframeSubmissionBlockReason,
                            cast: request.reframeCast,
                            reframedFromSummary: request.reframeSummary,
                            rotationDegrees: reframeRotationDegrees,
                            mode: $reframeMode,
                            viewDirection: $reframeViewDirection,
                            includeCameraMap: $reframeIncludeCameraMap,
                            selectedCastId: $reframeCastId,
                            stack: activeReframeStackBinding,
                            fidelity: $reframeFidelity,
                            zoomOutSourceScale: zoomOutSourceScaleBinding,
                            promptBody: $reframePromptBody,
                            isStackConfigured: isReframeStackConfigured,
                            onGenerate: submitReframe,
                            onResetPrompt: resetReframePromptBody,
                            onPromptContextChanged: refreshReframePromptIfClean,
                            onClearFocus: {
                                reframeFocusCenter = nil
                                reframeReticleEdge = LensReframeMetrics.reticleEdgePixels
                                reframeRotationDegrees = 0
                                reframePromptBody = ""
                                reframePromptBaseline = ""
                            },
                            onResetRotation: {
                                reframeRotationDegrees = 0
                                refreshReframePromptIfClean()
                            },
                            onRecenterZoomOut: {
                                reframeZoomOutCenter = CGPoint(x: 0.5, y: 0.5)
                                refreshReframePromptIfClean()
                            },
                            onOpenSettings: onOpenSettings,
                            onOpenParent: {
                                if !request.reframeParentImageId.isEmpty {
                                    onOpenRelated(request.reframeParentImageId)
                                }
                            }
                        )
                    )
                )
            ),
            focusRect: reframeFocusRect,
            focusRotationDegrees: reframeMode != LensReframeSpec.zoomOutMode ? reframeRotationDegrees : 0,
            outpaintSourceRect: reframeZoomOutSourceRect,
            onImageClick: canReframe && reframeMode != LensReframeSpec.zoomOutMode
                ? { point in setReframeFocus(point) }
                : nil,
            onFocusResize: canReframe && reframeMode != LensReframeSpec.zoomOutMode
                ? { rect in applyReframeResize(rect) }
                : nil,
            onFocusMove: canReframe && reframeMode != LensReframeSpec.zoomOutMode
                ? { point in moveReframeFocus(point) }
                : nil,
            onFocusRotate: canReframe && reframeMode != LensReframeSpec.zoomOutMode
                ? { degrees in applyReframeRotate(degrees) }
                : nil,
            onOutpaintSourceMove: canReframe && reframeMode == LensReframeSpec.zoomOutMode
                ? { point in moveReframeZoomOutSource(point) }
                : nil,
            collapsibleDetail: true,
            onClose: onClose
        ) {
            // Variation moved into the dock panel as a proper labeled button
            // (user testing: a borderless grey glyph beside ✕ read as
            // chrome, not as THE create action). The header keeps only
            // Finder + close.
            if FileManager.default.fileExists(atPath: request.imagePath) {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: request.imagePath)])
                } label: {
                    Image(systemName: "folder")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(CanonUtilityButtonStyle())
                .help("Open in Finder")
            }
        } imageActions: {
            LensNarrationBar(
                narration: request.narration,
                canNarrate: canReframe,
                isNarrating: isNarrating,
                player: narrationPlayer,
                onNarrate: onNarrate
            )
        } detailPanel: {
            LensHeroPromptPanel(
                prompt: request.prompt,
                sourcePrompt: request.sourcePrompt,
                enrichmentSummary: request.promptEnrichmentSummary,
                enrichmentDisabled: request.promptEnrichmentDisabled
            )
        }
        .focusable()
        .focusEffectDisabled()
        .focused($browseKeysFocused)
        .onKeyPress(.leftArrow) { navigateByKey(-1) }
        .onKeyPress(.rightArrow) { navigateByKey(1) }
        .onChange(of: request.imageId) { _, _ in
            reframeFocusCenter = nil
            reframeReticleEdge = LensReframeMetrics.reticleEdgePixels
            reframeRotationDegrees = 0
            reframePromptBody = ""
            reframePromptBaseline = ""
            reframePromptDrafts = [:]
            reframePromptBaselines = [:]
            reframeZoomOutSourceScale = LensReframeMetrics.zoomOutDefaultSourceScale
            reframeZoomOutCenter = CGPoint(x: 0.5, y: 0.5)
            narrationPlayer.stop()
        }
        .onChange(of: reframeMode) { oldMode, newMode in
            saveReframePromptDraft(mode: oldMode)
            restoreReframePromptDraft(mode: newMode)
        }
        .onAppear {
            browseKeysFocused = true
            // Inverted from the FAL-default era: only when OpenAI is absent
            // and a FAL key exists does zoom-out fall back to FAL outpaint.
            if !hasOpenAICredential, hasFALCredential,
               let falStack = RenderStackRegistry.shared.stack(id: RenderStackID.falOutpaint) {
                reframeZoomOutStack = falStack
            }
        }
        .onDisappear {
            narrationPlayer.stop()
        }
    }

    /// ←/→ browsing under THE TYPING GUARD (ShotPlayerTransportKeys law): the
    /// retired hidden `.keyboardShortcut` buttons were window-global key
    /// equivalents, so an arrow pressed while editing the reframe prompt
    /// navigated away and dropped the draft. `onKeyPress` + the guard makes
    /// bare arrows go dead the moment any text input owns the keyboard.
    private func navigateByKey(_ direction: Int) -> KeyPress.Result {
        guard let onNavigate, browseItems.count > 1, !shotTextInputOwnsKeyboard() else {
            return .ignored
        }
        onNavigate(direction)
        return .handled
    }

    private var canReframe: Bool {
        request.status.trimmed.lowercased() == "ready" && !request.imagePath.trimmed.isEmpty
    }

    private var animationTitle: String {
        if isAnimating || request.motionArtifact?.normalized().status == "generating" {
            return "Animating…"
        }
        switch request.motionArtifact?.normalized().status {
        case "ready":
            return "Regenerate Animation"
        case "failed":
            return "Retry Animation"
        default:
            return "Animate"
        }
    }

    private var selectedReframeStack: RenderStack {
        reframeMode == LensReframeSpec.zoomOutMode
            ? reframeZoomOutStack
            : reframeStandardStack
    }

    private var activeReframeStackBinding: Binding<RenderStack> {
        Binding(
            get: { selectedReframeStack },
            set: { value in
                if reframeMode == LensReframeSpec.zoomOutMode {
                    reframeZoomOutStack = value
                } else {
                    reframeStandardStack = value
                }
            }
        )
    }

    private var zoomOutSourceScaleBinding: Binding<Double> {
        Binding(
            get: { reframeZoomOutSourceScale },
            set: { value in
                let step = LensReframeMetrics.zoomOutSourceScaleStep
                let stepped = (value / step).rounded() * step
                reframeZoomOutSourceScale = min(
                    LensReframeMetrics.zoomOutMaximumSelectableSourceScale,
                    max(LensReframeMetrics.zoomOutMinimumSelectableSourceScale, stepped)
                )
                moveReframeZoomOutSource(reframeZoomOutCenter)
            }
        )
    }

    private func isReframeStackConfigured(_ stack: RenderStack) -> Bool {
        switch stack.credentialProvider {
        case .openAI: hasOpenAICredential
        case .fal: hasFALCredential
        case .stability: hasStabilityCredential
        default: false
        }
    }

    /// The narration strip only claims height when it has something to show.
    private var narrationBarHeight: CGFloat {
        if isNarrating || request.narration != nil { return 46 }
        return canReframe ? 46 : 0
    }

    /// Source pixel dimensions from image metadata; NSImage.size reports points and
    /// would understate retina renders.
    private var imagePixelSize: CGSize {
        let url = URL(fileURLWithPath: request.imagePath)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width > 0, height > 0 else {
            return displayedImageSize
        }
        return CGSize(width: width, height: height)
    }

    private var reframeFocusRect: CGRect? {
        guard reframeMode != LensReframeSpec.zoomOutMode else { return nil }
        guard let reframeFocusCenter else { return nil }
        let rect = lensReframeFocusRect(
            center: reframeFocusCenter,
            imagePixelSize: imagePixelSize,
            edgePixels: reframeReticleEdge,
            rotationDegrees: reframeRotationDegrees
        )
        return rect.isEmpty ? nil : rect
    }

    private var reframeZoomOutSourceRect: CGRect? {
        guard reframeMode == LensReframeSpec.zoomOutMode,
              let spec = reframeSpecDraft() else {
            return nil
        }
        return spec.zoomOutSourceRect
    }

    private var reframeFocusSummary: String {
        // Reads from the pinned reticle so the panel matches what's drawn
        // (and what the prompt/crop will use), not the raw click.
        guard let rect = reframeFocusRect else { return "" }
        let cx = Int((rect.midX * 100).rounded())
        let cy = Int((rect.midY * 100).rounded())
        let width = Int((rect.width * 100).rounded())
        let base = "Focus · \(cx)% × \(cy)% · \(width)% wide"
        let degrees = Int(reframeRotationDegrees.rounded())
        return degrees == 0 ? base : "\(base) · \(degrees)°"
    }

    private var reframeCropPreview: NSImage? {
        guard let spec = reframeSpecDraft() else { return nil }
        guard !spec.isZoomOut else { return nil }
        let cropRect = lensReframeCropRect(imagePixelSize: imagePixelSize, spec: spec)
        guard !cropRect.isEmpty,
              let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: request.imagePath) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let cropped = lensReframeExtractCrop(
                  from: image,
                  cropRect: cropRect,
                  rotationDegrees: spec.rotationDegrees
              ) else {
            return nil
        }
        return NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
    }

    private func setReframeFocus(_ point: CGPoint) {
        reframeFocusCenter = point
        // A fresh focus point starts at the base reticle, level; the grip and
        // rotate handle then shape it from there.
        reframeReticleEdge = LensReframeMetrics.reticleEdgePixels
        reframeRotationDegrees = 0
        resetReframePromptBody()
    }

    /// Repositions the existing reticle (dragging its body) without changing its size. The default
    /// prompt references the focus coordinates, so refresh it when the user hasn't hand-edited it.
    private func moveReframeFocus(_ point: CGPoint) {
        reframeFocusCenter = point
        refreshReframePromptIfClean()
    }

    /// Applies a rotate-handle drag: snaps the raw angle (magnetic level band,
    /// Shift = 15° detents) and keeps the default prompt honest about the tilt.
    private func applyReframeRotate(_ rawDegrees: Double) {
        reframeRotationDegrees = lensReframeSnappedRotation(
            rawDegrees: rawDegrees,
            shiftDown: NSEvent.modifierFlags.contains(.shift)
        )
        refreshReframePromptIfClean()
    }

    private func moveReframeZoomOutSource(_ point: CGPoint) {
        let scale = reframeZoomOutSourceScale
        let lower = scale / 2
        let upper = 1 - scale / 2
        let snapTargets = [lower, 0.5, upper]
        let snapThreshold = 0.018
        func snapped(_ raw: Double) -> Double {
            let clamped = min(upper, max(lower, raw))
            guard let nearest = snapTargets.min(by: {
                abs($0 - clamped) < abs($1 - clamped)
            }), abs(nearest - clamped) <= snapThreshold else {
                return clamped
            }
            return nearest
        }
        reframeZoomOutCenter = CGPoint(
            x: snapped(point.x),
            y: snapped(point.y)
        )
        refreshReframePromptIfClean()
    }

    /// Applies a grip-drag resize: converts the reported normalized rect to a source-pixel edge and
    /// clamps it between the base reticle and the shorter image dimension. Center stays fixed.
    private func applyReframeResize(_ normalizedRect: CGRect) {
        let pixelSize = imagePixelSize
        guard pixelSize.width > 0, pixelSize.height > 0 else { return }
        // The grip reports a square screen drag; take its extent as the target
        // reticle WIDTH (the 16:9 rect is reconstructed in lensReframeFocusRect).
        let proposedWidth = max(
            normalizedRect.width * pixelSize.width,
            normalizedRect.height * pixelSize.height
        )
        // Cap so the derived 16:9 height still fits inside the image.
        let maxWidth = min(pixelSize.width, pixelSize.height * LensReframeMetrics.reticleAspect)
        reframeReticleEdge = min(max(proposedWidth, LensReframeMetrics.reticleEdgePixels), maxWidth)
        // The default prompt now states the selection's extent — keep it true
        // while the grip drags (only when the user hasn't hand-edited it).
        refreshReframePromptIfClean()
    }

    private func resetReframePromptBody() {
        guard let spec = reframeSpecDraft() else {
            reframePromptBody = ""
            reframePromptBaseline = ""
            return
        }
        let defaultBody = LensReframeComposer.renderDefaultPromptBody(
            spec: spec,
            parent: reframeParentPromptImage,
            model: selectedReframeStack.reframePromptModel,
            promptSettings: promptSettings
        )
        reframePromptBaseline = defaultBody
        reframePromptBody = defaultBody
    }

    private func refreshReframePromptIfClean() {
        if reframePromptBody.trimmed.isEmpty || reframePromptBody == reframePromptBaseline {
            resetReframePromptBody()
        }
    }

    private func saveReframePromptDraft(mode: String) {
        reframePromptDrafts[mode] = reframePromptBody
        reframePromptBaselines[mode] = reframePromptBaseline
    }

    private func restoreReframePromptDraft(mode: String) {
        if let draft = reframePromptDrafts[mode] {
            reframePromptBody = draft
            reframePromptBaseline = reframePromptBaselines[mode] ?? ""
            return
        }
        reframePromptBody = ""
        reframePromptBaseline = ""
        resetReframePromptBody()
    }

    private func submitReframe() {
        guard let spec = reframeSpecDraft() else { return }
        let promptBody = reframePromptBody.trimmed.isEmpty
            ? LensReframeComposer.renderDefaultPromptBody(
                spec: spec,
                parent: reframeParentPromptImage,
                model: selectedReframeStack.reframePromptModel,
                promptSettings: promptSettings
            )
            : reframePromptBody
        onReframe(spec, selectedReframeStack, promptBody)
    }

    private func reframeSpecDraft() -> LensReframeSpec? {
        if reframeMode == LensReframeSpec.zoomOutMode {
            return LensReframeSpec(
                mode: reframeMode,
                centerX: reframeZoomOutCenter.x,
                centerY: reframeZoomOutCenter.y,
                normalizedWidth: reframeZoomOutSourceScale,
                normalizedHeight: reframeZoomOutSourceScale,
                parentImageId: request.imageId
            ).normalized()
        }
        guard let reframeFocusCenter else { return nil }
        let rect = lensReframeFocusRect(
            center: reframeFocusCenter,
            imagePixelSize: imagePixelSize,
            edgePixels: reframeReticleEdge,
            rotationDegrees: reframeRotationDegrees
        )
        let candidate = request.reframeCast.first { $0.id == reframeCastId }
        return LensReframeSpec(
            mode: reframeMode,
            // The PINNED reticle center, not the raw click — near an edge the
            // reticle slides inside the frame, and the prompt/crop coordinates
            // must describe where the selection actually sits.
            centerX: rect.isEmpty ? reframeFocusCenter.x : rect.midX,
            centerY: rect.isEmpty ? reframeFocusCenter.y : rect.midY,
            normalizedWidth: rect.width,
            normalizedHeight: rect.height,
            viewDirection: reframeViewDirection,
            parentImageId: request.imageId,
            characterId: candidate?.id ?? "",
            characterName: candidate?.name ?? "",
            characterPrompt: candidate?.compositePrompt ?? "",
            fidelity: reframeFidelity.rawValue,
            rotationDegrees: reframeRotationDegrees,
            includeCameraMap: reframeIncludeCameraMap
        ).normalized()
    }

    private var reframeParentPromptImage: ProjectLensHeroImage {
        ProjectLensHeroImage(
            imageId: request.imageId,
            prompt: request.prompt,
            sourcePrompt: request.sourcePrompt,
            status: request.status
        )
    }

    private var displayedImageSize: CGSize {
        guard let image = NSImage(contentsOfFile: request.imagePath) else { return .zero }
        return image.size
    }

    private var metadataText: String {
        var parts: [String] = []
        let status = request.status.trimmed
        if !status.isEmpty {
            parts.append(status.capitalized)
        }
        let model = request.model.trimmed
        if !model.isEmpty {
            parts.append(model)
        }
        let requestId = request.requestId.trimmed
        if !requestId.isEmpty {
            parts.append("request \(requestId)")
        }
        let size = displayedImageSize
        if size.width > 0, size.height > 0 {
            parts.append("\(Int(size.width))x\(Int(size.height))")
        }
        let error = request.errorMessage.trimmed
        if !error.isEmpty {
            parts.append(error)
        }
        return parts.joined(separator: " - ")
    }
}

/// The narration play/progress engine now lives in NarrationAudioPlayer.swift,
/// shared with the SHOTS band's narration strip.
private typealias LensNarrationPlayer = NarrationAudioPlayer

/// The narration strip under the preview image: one row that moves through
/// narrate → writing/voicing → play. Voice choice and regenerate live in the same row.
private struct LensNarrationBar: View {
    let narration: LensNarrationArtifact?
    let canNarrate: Bool
    let isNarrating: Bool
    @ObservedObject var player: LensNarrationPlayer
    let onNarrate: (String) -> Void
    @State private var isScriptShown = false

    private var hasElevenLabsKey: Bool {
        ElevenLabsSettingsStore.hasResolvedAPIKey()
    }

    private var voiceOptions: [StoryAudioVoiceOption] {
        StoryAudioVoiceCatalog.voiceOptions(customVoiceId: ElevenLabsSettingsStore.resolvedCustomVoiceId())
            .filter { ($0.voiceId?.trimmed.isEmpty ?? true) == false }
    }

    private var defaultVoicePresetId: String {
        StoryAudioVoiceCatalog.defaultOption(customVoiceId: ElevenLabsSettingsStore.resolvedCustomVoiceId()).id
    }

    var body: some View {
        HStack(spacing: 12) {
            if isNarrating {
                ProgressView()
                    .controlSize(.small)
                Text("Writing & voicing narration…")
                    .font(CanonType.archive(10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.82))
            } else if let narration, narration.isReady, FileManager.default.fileExists(atPath: narration.audioPath) {
                readyPlayer(narration)
            } else if !canNarrate {
                EmptyView()
            } else if !hasElevenLabsKey {
                Image(systemName: "key")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.82))
                Text("Add an ElevenLabs API key in App Settings to narrate this scene.")
                    .font(CanonType.archive(10))
                    .foregroundStyle(Color.white.opacity(0.82))
            } else {
                narrateButton(
                    title: narration?.status == "failed" ? "Retry narration" : "Narrate this scene",
                    presetId: narration?.voicePresetId.nilIfEmpty ?? defaultVoicePresetId
                )
                if narration?.status == "failed" {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CanonColor.rust)
                        .help(narration?.errorMessage.nilIfEmpty ?? "Narration failed")
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func narrateButton(title: String, presetId: String) -> some View {
        HStack(spacing: 4) {
            Button {
                onNarrate(presetId)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "waveform")
                        .font(.system(size: 11, weight: .semibold))
                    Text(title)
                        .font(CanonType.interface(11, weight: .semibold))
                }
                .foregroundStyle(CanonColor.paper)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Capsule().fill(CanonColor.paper.opacity(0.16)))
                .overlay(Capsule().stroke(CanonColor.paper.opacity(0.42), lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Write and voice a short narration for this scene")

            Menu {
                ForEach(voiceOptions, id: \.id) { option in
                    Button("\(option.name) — \(option.descriptor)") {
                        onNarrate(option.id)
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(CanonColor.paper)
                    .frame(width: 24, height: 28)
                    .background(Capsule().fill(CanonColor.paper.opacity(0.13)))
                    .overlay(Capsule().stroke(CanonColor.paper.opacity(0.34), lineWidth: 1))
                    .contentShape(Capsule())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Pick the narration voice")
        }
        .fixedSize()
    }

    @ViewBuilder
    private func readyPlayer(_ narration: LensNarrationArtifact) -> some View {
        Button {
            player.toggle(path: narration.audioPath)
        } label: {
            Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(CanonColor.brass)
        }
        .buttonStyle(.plain)
        .help(player.isPlaying ? "Pause narration" : "Play narration")

        ZStack(alignment: .leading) {
            Capsule()
                .fill(CanonColor.hairlineDark)
            Capsule()
                .fill(CanonColor.brass)
                .frame(width: max(0, 150 * player.progress))
        }
        .frame(width: 150, height: 3)

        Text("\(timeLabel(player.currentTime)) / \(timeLabel(playerDuration(narration)))")
            .font(CanonType.archive(9.5, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.78))
            .monospacedDigit()

        Menu {
            ForEach(voiceOptions, id: \.id) { option in
                Button("\(option.name) — \(option.descriptor)") {
                    onNarrate(option.id)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "person.wave.2")
                    .font(.system(size: 9, weight: .semibold))
                Text(narration.voiceName.isEmpty ? "Voice" : narration.voiceName)
                    .font(CanonType.archive(9.5, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
            }
            .foregroundStyle(Color.white.opacity(0.78))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Re-narrate with a different voice")

        Button {
            isScriptShown.toggle()
        } label: {
            Image(systemName: "text.quote")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.78))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isScriptShown, arrowEdge: .top) {
            Text(narration.script.isEmpty ? "No script saved for this narration." : narration.script)
                .font(CanonType.editorial(14))
                .foregroundStyle(CanonColor.ink)
                .textSelection(.enabled)
                .padding(14)
                .frame(width: 320, alignment: .topLeading)
        }
        .help("Show the narration script")

        Button {
            onNarrate(narration.voicePresetId.nilIfEmpty ?? defaultVoicePresetId)
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.78))
        }
        .buttonStyle(.plain)
        .help("Write and voice a fresh narration")
    }

    private func playerDuration(_ narration: LensNarrationArtifact) -> Double {
        player.duration > 0 ? player.duration : narration.durationSeconds
    }

    private func timeLabel(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct LensReframePanel: View {
    let hasFocus: Bool
    let focusSummary: String
    let cropPreview: NSImage?
    let canReframe: Bool
    let submissionBlockReason: String
    let cast: [LensReframeCastCandidate]
    let reframedFromSummary: String
    /// Current reticle tilt; drives the compact 0° reset beside the summary.
    let rotationDegrees: Double
    @Binding var mode: String
    @Binding var viewDirection: String
    @Binding var includeCameraMap: Bool
    @Binding var selectedCastId: String
    @Binding var stack: RenderStack
    @Binding var fidelity: LensReframeFidelity
    @Binding var zoomOutSourceScale: Double
    @Binding var promptBody: String
    let isStackConfigured: (RenderStack) -> Bool
    let onGenerate: () -> Void
    let onResetPrompt: () -> Void
    let onPromptContextChanged: () -> Void
    let onClearFocus: () -> Void
    let onResetRotation: () -> Void
    let onRecenterZoomOut: () -> Void
    let onOpenSettings: () -> Void
    let onOpenParent: () -> Void

    private var reframeStacks: [RenderStack] {
        RenderStackRegistry.shared.reframeStacks(mode: mode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Rectangle()
                .fill(CanonColor.hairlineDark.opacity(0.72))
                .frame(height: 1)
                .padding(.vertical, 2)
            Text("Reframe")
                .font(CanonType.archive(8.5, weight: .semibold))
                .kerning(1.2)
                .textCase(.uppercase)
                .foregroundStyle(CanonColor.muted)
            if !reframedFromSummary.isEmpty {
                Button {
                    onOpenParent()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 9, weight: .semibold))
                        Text("From source · \(reframedFromSummary)")
                            .font(CanonType.archive(9.5, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(CanonColor.brass)
                }
                .buttonStyle(.plain)
                .help("Open the render this reframe was derived from")
            }
            if !canReframe {
                Text("Reframe needs a ready render.")
                    .font(CanonType.archive(9.5))
                    .foregroundStyle(CanonColor.muted)
            } else {
                HStack(spacing: 6) {
                    modeChip("Zoom In", value: LensReframeSpec.zoomMode, help: "Make a selected source area the whole new frame")
                    modeChip("Zoom Out", value: LensReframeSpec.zoomOutMode, help: "Pull the camera back to reveal a wider world around this frame")
                    modeChip("Viewpoint", value: LensReframeSpec.viewpointMode, help: "Place the camera at the selected point and choose where it looks")
                }

                if mode == LensReframeSpec.zoomOutMode {
                    zoomOutControls
                } else if !hasFocus {
                    Text("Click the image to set a focus point.")
                        .font(CanonType.archive(9.5))
                        .foregroundStyle(CanonColor.muted)
                } else {
                    focusControls
                }

                if mode == LensReframeSpec.zoomOutMode || hasFocus {
                    modelPicker
                    if !isStackConfigured(stack) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "key")
                                .font(.system(size: 9, weight: .semibold))
                            Text("\(stack.label) needs its provider key.")
                                .font(CanonType.archive(9.5))
                            Spacer(minLength: 0)
                            Button("Settings") {
                                onOpenSettings()
                            }
                            .buttonStyle(.plain)
                            .font(CanonType.archive(9.5, weight: .semibold))
                        }
                        .foregroundStyle(CanonColor.brass)
                    }
                    promptEditor
                    Button {
                        onGenerate()
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11, weight: .semibold))
                            Text(generateButtonTitle)
                                .font(CanonType.interface(11, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(CanonSecondaryButtonStyle(isFullWidth: true))
                    .disabled(generateBlocked)
                    .help(generateHelp)
                }
            }
        }
    }

    @ViewBuilder
    private var focusControls: some View {
        HStack(spacing: 6) {
            Text(focusSummary)
                .font(CanonType.archive(9.5, weight: .medium))
                .foregroundStyle(CanonColor.bone)
            Spacer(minLength: 0)
            if rotationDegrees != 0 {
                Button {
                    onResetRotation()
                } label: {
                    Text("0°")
                        .font(CanonType.archive(9.5, weight: .semibold))
                        .foregroundStyle(CanonColor.brass)
                }
                .buttonStyle(.plain)
                .help("Reset rotation — level the selection")
            }
            Button {
                onClearFocus()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(CanonColor.muted)
            }
            .buttonStyle(.plain)
            .help("Clear the focus point")
        }
        if let cropPreview {
            Image(nsImage: cropPreview)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity)
                .frame(height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(CanonColor.brass.opacity(0.4), lineWidth: 1)
                )
                .help("The focus region with surrounding context")
        }
        if mode == LensReframeSpec.zoomMode {
            HStack(spacing: 6) {
                ForEach(LensReframeFidelity.allCases, id: \.self) { option in
                    fidelityChip(option)
                }
            }
        }
        if mode == LensReframeSpec.viewpointMode {
            viewpointCompass
            if !cast.isEmpty {
                Menu {
                    Button("No character") {
                        selectedCastId = ""
                        onPromptContextChanged()
                    }
                    Divider()
                    ForEach(cast) { candidate in
                        Button(candidateLabel(candidate)) {
                            selectedCastId = candidate.id
                            onPromptContextChanged()
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: selectedCastId.isEmpty ? "person.crop.circle.badge.questionmark" : "person.fill")
                            .font(.system(size: 9, weight: .semibold))
                        Text(selectedCastLabel)
                            .font(CanonType.interface(10.5, weight: .medium))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                    }
                    .foregroundStyle(CanonColor.bone)
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: 5).fill(CanonColor.paperInset.opacity(0.35)))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(CanonColor.hairlineDark))
                }
                .menuStyle(.borderlessButton)
                .help("Optional character context for the viewpoint camera")
            }
        }
    }

    private var zoomOutControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Source size")
                    .font(CanonType.archive(10, weight: .semibold))
                    .foregroundStyle(CanonColor.bone)
                Spacer(minLength: 0)
                Button("Recenter") {
                    onRecenterZoomOut()
                }
                .buttonStyle(.plain)
                .font(CanonType.archive(9.5, weight: .semibold))
                .foregroundStyle(CanonColor.brass)
                .help("Center the locked source within the new frame")
                Text("\(zoomOutSourceScalePercent)%")
                    .font(CanonType.archive(11, weight: .bold))
                    .foregroundStyle(CanonColor.ink)
                    .monospacedDigit()
                    .frame(minWidth: 38)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(CanonColor.brass)
                    )
            }
            ZStack {
                Capsule()
                    .fill(CanonColor.bone.opacity(0.28))
                    .frame(height: 6)
                Slider(
                    value: $zoomOutSourceScale,
                    in: LensReframeMetrics.zoomOutMinimumSelectableSourceScale...LensReframeMetrics.zoomOutMaximumSelectableSourceScale,
                    step: LensReframeMetrics.zoomOutSourceScaleStep
                )
                .controlSize(.regular)
                .tint(CanonColor.softGold)
            }
            .frame(height: 28)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(CanonColor.archiveWell)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(CanonColor.brass.opacity(0.48), lineWidth: 1)
            )
            .accessibilityLabel("Original frame size in the final frame")
            .accessibilityValue("\(zoomOutSourceScalePercent) percent")
            .help("How much of the final frame the locked original occupies")
            if zoomOutPassCount > 1 {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "square.stack")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Renders as \(zoomOutPassCount) linked frames · \(zoomOutPassCount) provider calls, each saved as its own take.")
                        .font(CanonType.archive(9.2, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(CanonColor.bone)
            }
        }
    }

    private var zoomOutSourceScalePercent: Int {
        Int((zoomOutSourceScale * 100).rounded())
    }

    private var zoomOutPassCount: Int {
        LensZoomOutGeometry.zoomOutPassCount(totalScale: zoomOutSourceScale)
    }

    private var modelPicker: some View {
        Menu {
            ForEach(reframeStacks) { option in
                Button {
                    stack = option
                    onPromptContextChanged()
                } label: {
                    Text(isStackConfigured(option) ? option.label : "\(option.label) · Needs key")
                }
                .disabled(!isStackConfigured(option))
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "cpu")
                    .font(.system(size: 9, weight: .semibold))
                Text(stack.label)
                    .font(CanonType.interface(10.5, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(CanonColor.bone)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 5).fill(CanonColor.paperInset.opacity(0.35)))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(CanonColor.hairlineDark))
        }
        .menuStyle(.borderlessButton)
        .help("Choose an executable model for this reframe operation")
    }

    private var generateBlocked: Bool {
        !submissionBlockReason.isEmpty
            || !isStackConfigured(stack)
            || (mode != LensReframeSpec.zoomOutMode && !hasFocus)
    }

    private var generateButtonTitle: String {
        if !submissionBlockReason.isEmpty { return "Frame work in progress…" }
        return mode == LensReframeSpec.zoomOutMode ? "Generate zoom out" : "Generate reframe"
    }

    private var generateHelp: String {
        if !submissionBlockReason.isEmpty {
            return submissionBlockReason
        }
        if !isStackConfigured(stack) {
            return "Add the \(stack.credentialProvider.rawValue) provider key in App Settings"
        }
        if mode != LensReframeSpec.zoomOutMode, !hasFocus {
            return "Click the image to choose a focus point"
        }
        if mode == LensReframeSpec.zoomOutMode {
            return "Create a wider frame while preserving the source inset"
        }
        return "Render one new take derived from this focus"
    }

    private var selectedCastLabel: String {
        cast.first { $0.id == selectedCastId }.map(candidateLabel) ?? "No character"
    }

    private var selectedViewDirection: LensReframeViewDirection {
        LensReframeViewDirection.normalized(viewDirection)
    }

    private var viewpointCompass: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("View")
                    .font(CanonType.archive(9.5, weight: .medium))
                    .foregroundStyle(CanonColor.muted)
                Text(selectedViewDirection.label)
                    .font(CanonType.archive(9.5, weight: .semibold))
                    .foregroundStyle(CanonColor.bone)
            }
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    compassButton(.northwest)
                    compassButton(.north)
                    compassButton(.northeast)
                }
                HStack(spacing: 4) {
                    compassButton(.west)
                    Circle()
                        .fill(CanonColor.brass.opacity(0.65))
                        .frame(width: 24, height: 24)
                        .overlay(Circle().stroke(CanonColor.hairlineDark, lineWidth: 1))
                        .help("Selected camera origin")
                    compassButton(.east)
                }
                HStack(spacing: 4) {
                    compassButton(.southwest)
                    compassButton(.south)
                    compassButton(.southeast)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            Toggle(isOn: $includeCameraMap) {
                Text("Camera map")
                    .font(CanonType.archive(9.5, weight: .medium))
                    .foregroundStyle(CanonColor.muted)
            }
            .toggleStyle(.checkbox)
            .help("Send a drawn top-down schematic of the requested camera move (A = original camera, B = this vantage point) alongside the source images.")
        }
    }

    private var promptEditor: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text("Prompt")
                    .font(CanonType.archive(9.5, weight: .semibold))
                    .foregroundStyle(CanonColor.muted)
                Spacer()
                Button {
                    onResetPrompt()
                } label: {
                    Text("Default")
                        .font(CanonType.archive(9.5, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(CanonColor.brass)
                .help("Replace the prompt body with the current default")
            }
            TextEditor(text: $promptBody)
                .font(CanonType.editorial(12.5))
                .foregroundStyle(CanonColor.bone)
                .frame(minHeight: 98)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 5).fill(CanonColor.paperInset.opacity(0.35)))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(CanonColor.hairlineDark))
        }
    }

    private func compassButton(_ direction: LensReframeViewDirection) -> some View {
        let isSelected = selectedViewDirection == direction
        return Button {
            viewDirection = direction.rawValue
            onPromptContextChanged()
        } label: {
            Image(systemName: direction.systemImage)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isSelected ? CanonColor.paper : CanonColor.bone)
                .frame(width: 26, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isSelected ? CanonColor.brass.opacity(0.92) : CanonColor.paperInset.opacity(0.35))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(isSelected ? CanonColor.brass : CanonColor.hairlineDark, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(direction.label)
    }

    private func candidateLabel(_ candidate: LensReframeCastCandidate) -> String {
        candidate.name.trimmed.isEmpty ? candidate.prompt : candidate.name
    }

    /// Zoom fidelity chip: TIGHT / TRUE / WIDE — sets crop context + prompt line.
    private func fidelityChip(_ option: LensReframeFidelity) -> some View {
        let isSelected = fidelity == option
        return Button {
            fidelity = option
            onPromptContextChanged()
        } label: {
            Text(option.label)
                .font(CanonType.interface(9.5, weight: .semibold))
                .kerning(0.4)
                .foregroundStyle(isSelected ? CanonColor.paper : CanonColor.bone)
                .frame(maxWidth: .infinity)
                .frame(height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isSelected ? CanonColor.brass.opacity(0.82) : CanonColor.paperInset.opacity(0.3))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isSelected ? CanonColor.brass : CanonColor.hairlineDark, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(option.help)
    }

    private func modeChip(_ title: String, value: String, help: String) -> some View {
        let isSelected = mode == value
        return Button {
            mode = value
            onPromptContextChanged()
        } label: {
            Text(title)
                .font(CanonType.interface(10.5, weight: .semibold))
                .foregroundStyle(isSelected ? CanonColor.paper : CanonColor.bone)
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isSelected ? CanonColor.brass.opacity(0.92) : CanonColor.paperInset.opacity(0.35))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(isSelected ? CanonColor.brass : CanonColor.hairlineDark, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct LensHeroPromptPanel: View {
    let prompt: String
    var sourcePrompt: String = ""
    var enrichmentSummary: String = ""
    var enrichmentDisabled: Bool = false

    private enum PromptView: String, CaseIterable {
        case sent = "Sent"
        case authored = "Authored"
    }

    @State private var selection: PromptView = .sent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("Generation prompt")
                        .font(CanonType.interface(10, weight: .semibold))
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(CanonColor.brass)
                    if enrichmentDisabled {
                        Text("VERBATIM — PROMPT TRANSFORM OFF")
                            .font(CanonType.archive(7, weight: .bold))
                            .kerning(0.6)
                            .foregroundStyle(CanonColor.rust)
                            .help("The authored scene text went to the provider without the LLM rewrite")
                    }
                    Spacer(minLength: 0)
                    if hasDistinctAuthoredPrompt {
                        Picker("", selection: $selection) {
                            ForEach(PromptView.allCases, id: \.self) { Text($0.rawValue) }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                        .help("Sent = the prompt the provider received · Authored = your original scene text")
                    }
                }
                if !enrichmentSummary.trimmed.isEmpty, selection == .sent {
                    Text("Rewrite: \(enrichmentSummary.trimmed)")
                        .font(CanonType.interface(10.5))
                        .foregroundStyle(CanonColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(displayedPrompt)
                    .font(CanonType.editorial(15))
                    .foregroundStyle(CanonColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(CanonColor.paper)
        .foregroundStyle(CanonColor.ink)
    }

    private var hasDistinctAuthoredPrompt: Bool {
        !sourcePrompt.trimmed.isEmpty && sourcePrompt.trimmed != prompt.trimmed
    }

    private var displayedPrompt: String {
        switch selection {
        case .sent:
            return prompt.trimmed.isEmpty ? "No generation prompt saved for this frame." : prompt.trimmed
        case .authored:
            return sourcePrompt.trimmed.isEmpty
                ? "Authored text was not recorded for this frame."
                : sourcePrompt.trimmed
        }
    }
}

private struct LensHeroImageView: View {
    let imagePath: String
    let status: String
    var iconSize: CGFloat = 20

    var body: some View {
        ZStack {
            CanonColor.mediaCardHover
            if let image = NSImage(contentsOfFile: imagePath) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(6)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: status == "failed" ? "exclamationmark.triangle" : "photo")
                        .font(.system(size: iconSize, weight: .semibold))
                    Text(status.isEmpty ? "Hero" : status.capitalized)
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(CanonColor.ink.opacity(0.56))
            }
        }
        .clipped()
    }
}

private func copyTextToPasteboard(_ value: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
}

struct CreativeResetBanner: View {
    @ObservedObject var library: LibraryEngine

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Project update needed")
                    .font(.system(size: 13, weight: .semibold))
                Text(library.creativeIncompatibilityMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(CanonColor.muted)
            }
            Spacer()
            Button("Update project") {
                _ = library.resetCurrentProjectCreativeData()
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.14))
        .overlay(Rectangle().fill(Color.orange.opacity(0.4)).frame(height: 1), alignment: .bottom)
    }
}

/// Top-of-STORY guidance strip: points at MEDIA while the project has no
/// media, or at analysis while enabled media has never been analyzed (stale
/// or modified analysis stays quiet here — MEDIA and FRAMES carry those
/// warnings). Non-blocking: STORY keeps working either way. Hidden while a
/// scan or analysis runs; dismissible for the launch via keys the window
/// root holds, because this workspace is torn down on every tab switch.
struct GoalMediaReadinessBanner: View {
    @ObservedObject var library: LibraryEngine
    var onAddMedia: () -> Void
    var onOpenAppSettings: () -> Void = {}
    @Binding var dismissedKeys: Set<String>

    private enum Readiness {
        case needsMedia
        case needsAnalysis(missingCount: Int, enabledCount: Int)

        var kind: String {
            switch self {
            case .needsMedia: return "needsMedia"
            case .needsAnalysis: return "needsAnalysis"
            }
        }
    }

    private var readiness: Readiness? {
        guard library.currentProject != nil,
              !library.isScanning,
              !library.isAnalyzingMedia else { return nil }
        if library.sources.isEmpty {
            return .needsMedia
        }
        let health = library.aestheticAnalysisHealth
        if health.enabledCount > 0, health.missingObservationCount > 0 {
            return .needsAnalysis(
                missingCount: health.missingObservationCount,
                enabledCount: health.enabledCount
            )
        }
        return nil
    }

    var body: some View {
        if let readiness, !dismissedKeys.contains(dismissalKey(for: readiness)) {
            HStack(spacing: 12) {
                Image(systemName: icon(for: readiness))
                    .foregroundStyle(tint(for: readiness))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title(for: readiness))
                        .font(CanonType.interface(13, weight: .semibold))
                        .foregroundStyle(CanonColor.ink)
                    Text(detail(for: readiness))
                        .font(CanonType.interface(12))
                        .foregroundStyle(CanonColor.ink.opacity(0.64))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                switch readiness {
                case .needsMedia:
                    Button {
                        onAddMedia()
                    } label: {
                        LitIconLabel(title: "Add Media", icon: .media)
                    }
                    .buttonStyle(CanonSecondaryButtonStyle())
                    .help("Open MEDIA and add photos or footage to this project")
                case .needsAnalysis:
                    if library.isOpenAICredentialConfigured {
                        Button {
                            Task {
                                await library.analyzeUnanalyzedEnabledMedia()
                            }
                        } label: {
                            LitIconLabel(title: "Analyze Media", icon: .analyze)
                        }
                        .buttonStyle(CanonSecondaryButtonStyle())
                        .disabled(!library.canAnalyzeUnanalyzedEnabledMedia)
                        .help("Analyze enabled media so STORY works from what is in it")
                    } else {
                        Button {
                            onOpenAppSettings()
                        } label: {
                            LitIconLabel(title: "Add API Key", icon: .key)
                        }
                        .buttonStyle(CanonSecondaryButtonStyle())
                        .help("Media analysis needs an OpenAI API key — add one in App Settings")
                    }
                }
                Button {
                    dismissedKeys.insert(dismissalKey(for: readiness))
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(CanonUtilityButtonStyle())
                .help("Hide until the next launch")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(tint(for: readiness).opacity(0.12))
            .overlay(
                Rectangle()
                    .fill(tint(for: readiness).opacity(0.4))
                    .frame(height: 1),
                alignment: .bottom
            )
        }
    }

    private func dismissalKey(for readiness: Readiness) -> String {
        "\(library.currentProject?.projectId ?? ""):\(readiness.kind)"
    }

    private func tint(for readiness: Readiness) -> Color {
        switch readiness {
        case .needsMedia: return CanonColor.brass
        case .needsAnalysis: return CanonColor.rust
        }
    }

    private func icon(for readiness: Readiness) -> String {
        switch readiness {
        case .needsMedia: return "photo.on.rectangle.angled"
        case .needsAnalysis: return "exclamationmark.triangle.fill"
        }
    }

    private func title(for readiness: Readiness) -> String {
        switch readiness {
        case .needsMedia: return "This project has no media yet"
        case .needsAnalysis: return "Some media hasn't been analyzed"
        }
    }

    private func detail(for readiness: Readiness) -> String {
        switch readiness {
        case .needsMedia:
            return "STORY grounds in your project's media. Add photos or footage to work from what you actually have."
        case .needsAnalysis(let missingCount, let enabledCount):
            let noun = "item\(enabledCount == 1 ? "" : "s")"
            let verb = missingCount == 1 ? "has" : "have"
            let base = "\(missingCount) of \(enabledCount) enabled media \(noun) \(verb) no analysis yet. STORY can continue, but analyzed media improves grounding."
            guard library.isOpenAICredentialConfigured else {
                return base + " Media analysis needs an OpenAI API key first."
            }
            return base
        }
    }
}
