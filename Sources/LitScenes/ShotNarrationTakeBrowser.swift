import AppKit
import SwiftUI

/// Auditioning a recording and choosing the Shot's voice-over are separate
/// actions. This list stays available alongside either video render recipe.
struct ShotNarrationTakeBrowser: View {
    let shot: ProjectShot
    let projectId: String
    let isBusy: Bool
    let pasteRefusal: String?
    @ObservedObject var player: NarrationAudioPlayer
    var onUse: (String) -> Void
    var onPaste: () -> Void
    @StateObject private var copyFeedback = ShotClipboardCopyFeedback()
    @State private var focusedTakeId = ""
    @FocusState private var hasTakeFocus: Bool

    private var takes: [ShotNarrationArtifact] { shot.sortedNarrationTakes }
    private var focusedTake: ShotNarrationArtifact? {
        takes.first { $0.takeId == focusedTakeId } ?? shot.narrationArtifact
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("NARRATION TAKES · \(takes.count)")
                    .font(CanonType.archive(8, weight: .semibold))
                    .kerning(0.7)
                Spacer()
                Button("PASTE NARRATION", action: onPaste)
                    .disabled(pasteRefusal != nil)
                    .help(pasteRefusal ?? "Paste the whole narration at the start of this Shot")
                    .font(CanonType.archive(7.5, weight: .semibold))
            }
            if let pasteRefusal {
                Text(pasteRefusal).font(CanonType.interface(11)).foregroundStyle(CanonColor.muted)
            }
            ShotClipboardFeedbackView(feedback: copyFeedback)
            Text(shot.renderStack.isNarrationDriven
                ? "The active take drives LTX and plays through the narration lane."
                : "The active take plays as voice-over. This video model does not use it for lip-sync.")
                .font(CanonType.interface(10))
                .foregroundStyle(CanonColor.muted)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(takes) { take in takeRow(take) }
                }
            }
            .frame(height: min(CGFloat(takes.count) * 83, 265))
            if shot.narrationVideoNeedsSync {
                Text("The current LTX video was made with different narration. Render again to synchronize the picture with this take.")
                    .font(CanonType.interface(10)).foregroundStyle(CanonColor.rust)
            }
            if let narration = shot.narrationArtifact, narration.isReady,
               let seconds = shot.renderArtifact?.totalSeconds, seconds > 0,
               narration.durationSeconds + shot.audioMix.lane(ShotAudioLaneId.narration).effectiveStartSeconds > Double(seconds) + 0.05 {
                Text("Narration extends beyond the current video. Playback and export stop with the video; adjust the narration or extend the Shot.")
                    .font(CanonType.interface(10))
                    .foregroundStyle(CanonColor.rust)
            }
        }
        .padding(12)
        .frame(maxWidth: 720, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9).fill(CanonColor.paperInset.opacity(0.45)))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(CanonColor.hairlinePaper, lineWidth: 1))
        .foregroundStyle(CanonColor.ink)
        .buttonStyle(.borderless)
        .focusable()
        .focusEffectDisabled()
        .focused($hasTakeFocus)
        .onCopyCommand {
            guard !(NSApp.keyWindow?.firstResponder is NSTextView), let take = focusedTake else { return [] }
            return copyFeedback.providers { try ShotNarrationClipboard.contents(for: payload(take)) }
        }
    }

    private func payload(_ take: ShotNarrationArtifact) -> ShotNarrationClipboardPayload {
        .init(take: take, sourceProjectId: projectId, sourceShotId: shot.shotId)
    }

    private func focus(_ take: ShotNarrationArtifact) {
        focusedTakeId = take.takeId
        hasTakeFocus = true
    }

    private func takeRow(_ take: ShotNarrationArtifact) -> some View {
        let active = take.takeId == shot.activeNarrationTakeId
        let readable = take.isReady && FileManager.default.fileExists(atPath: take.audioPath)
        let copyRefusal = payload(take).pasteRefusal
        let copyable = readable && copyRefusal == nil
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(take.voiceName.nilIfEmpty ?? "Narration")
                    .font(CanonType.interface(11, weight: .semibold))
                if take.isReady {
                    Text("\(ShotNarrationDuration.label(take.durationSeconds)) · \(String(format: "%.2f×", take.effectiveVoiceSpeed))")
                        .font(CanonType.archive(8))
                }
                if active { badge("ACTIVE") }
                if !take.copiedAt.isEmpty { badge("COPIED") }
                Spacer(minLength: 4)
                if take.isReady {
                    Button(player.isPlaying(path: take.audioPath) ? "PAUSE" : "PLAY") {
                        focus(take)
                        player.toggle(path: take.audioPath)
                    }.disabled(!readable)
                    Button("USE") { focus(take); player.stop(); onUse(take.takeId) }
                        .disabled(!readable || active || isBusy)
                    Button("COPY") { copy(take) }
                        .disabled(!copyable)
                        .help(copyRefusal ?? "Copy the whole narration for another Shot")
                } else {
                    Text(take.status.uppercased()).foregroundStyle(CanonColor.rust)
                        .font(CanonType.archive(8))
                }
            }
            .font(CanonType.archive(7.5, weight: .semibold))
            Text(take.script.nilIfEmpty ?? take.messagingText)
                .font(CanonType.interface(11))
                .lineLimit(2)
                .help(take.script)
            if take.isReady && !readable {
                Text("Audio file missing — restore the file or use another take.")
                    .font(CanonType.interface(10)).foregroundStyle(CanonColor.rust)
            } else if !take.errorMessage.isEmpty {
                Text(take.errorMessage).font(CanonType.interface(10)).foregroundStyle(CanonColor.rust)
            }
        }
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(CanonColor.paper.opacity(0.75)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(
            focusedTakeId == take.takeId || active ? CanonColor.brass.opacity(0.6) : CanonColor.hairlinePaper,
            lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { focus(take) }
        .contextMenu {
            Button("Copy Narration") { copy(take) }
                .disabled(!copyable)
        }
    }

    private func copy(_ take: ShotNarrationArtifact) {
        focus(take)
        copyFeedback.copy { try ShotNarrationClipboard.contents(for: payload(take)) }
    }

    private func badge(_ text: String) -> some View {
        Text(text).font(CanonType.archive(7, weight: .semibold)).foregroundStyle(CanonColor.brass)
    }
}
