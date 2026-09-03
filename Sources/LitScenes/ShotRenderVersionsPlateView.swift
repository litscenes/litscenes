import AppKit
import SwiftUI

/// THE VERSIONS PLATE — provenance archaeology for every render version of a
/// cut: what each version was rendered with (per-segment model, requested →
/// measured duration, audio, resolution), the exact prompt each clip was
/// paid with, its trace id, and which clips traveled in from an earlier
/// version (REUSED · from N). Everything shown is read from the versions'
/// own persisted clips — never from the next-render default — under the
/// provenance label law in `ShotRenderProvenance.swift`.
///
/// Read-only except VIEW, which activates a version exactly like the footer
/// numerals (viewing IS selecting).
struct ShotRenderVersionsPlateView: View {
    let shot: ProjectShot
    /// The current plan's placement order; old versions' clips follow it
    /// where they match, orphans after (`shotVersionClipsInPlanOrder`).
    let planPlacementKeys: [String]
    var onActivateVersion: (String) -> Void
    var onClose: () -> Void

    /// "versionId|pairKey" entries whose prompt is disclosed.
    @State private var expandedPrompts: Set<String> = []
    @State private var copiedTraceKey: String?

    /// Newest first: the question is usually "what did I just do".
    private var versions: [ShotRenderArtifact] {
        shot.sortedRenderVersions.reversed()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                PlateLabel(text: "VERSIONS", size: 11, weight: .bold, color: PlateColor.ink)
                PlateLabel(
                    text: shot.name.trimmed.nilIfEmpty ?? "This cut",
                    size: 9,
                    color: PlateColor.inkFaint
                )
                Spacer(minLength: 0)
                PlateLabel(
                    text: "NEXT RENDER DEFAULT · \(shot.renderStack.shortLabel)",
                    size: 8,
                    weight: .semibold,
                    color: PlateColor.inkFaint
                )
                .help("The picker's current default — intent, not provenance. Every line below is what was actually rendered.")
                Button("Close") { onClose() }
                    .buttonStyle(PlateButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Rectangle().fill(PlateColor.hairline).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(versions, id: \.versionId) { version in
                        versionRow(version)
                    }
                    if versions.isEmpty {
                        PlateLabel(
                            text: "No renders yet — the first render becomes version i.",
                            size: 9,
                            color: PlateColor.inkFaint
                        )
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 940, height: 610)
        .background(PlateColor.cream)
        .environment(\.colorScheme, .light)
    }

    private func versionRow(_ version: ShotRenderArtifact) -> some View {
        let isActive = shot.isActiveRenderVersion(version)
        let clips = shotVersionClipsInPlanOrder(
            version: version,
            planPlacementKeys: planPlacementKeys
        )
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Text(FrameCreatorModal.romanNumeral(version.versionNumber).lowercased())
                    .font(.system(size: 14, weight: .bold, design: .serif))
                    .foregroundStyle(PlateColor.ink)
                    .frame(minWidth: 26, alignment: .leading)
                statusLabel(version)
                PlateLabel(
                    text: shotRenderProvenanceSummary(version: version),
                    size: 9,
                    weight: .semibold,
                    color: PlateColor.ink
                )
                if version.totalSeconds > 0 {
                    PlateLabel(
                        text: "~\(version.totalSeconds)s",
                        size: 8.5,
                        color: PlateColor.inkFaint
                    )
                }
                PlateLabel(
                    text: displayDate(version.generatedAt),
                    size: 8.5,
                    color: PlateColor.inkFaint
                )
                Spacer(minLength: 0)
                if isActive {
                    PlateLabel(text: "ACTIVE", size: 8, weight: .bold, color: CanonColor.brass)
                        .help("The shot's selected render — what the player and Stage show")
                } else if version.isReady {
                    Button("View") {
                        onActivateVersion(version.versionId)
                    }
                    .buttonStyle(PlateButtonStyle())
                    .help("Show this version and make it the shot's selected render — same as its footer numeral")
                }
            }
            if version.status == "failed", let message = version.errorMessage.trimmed.nilIfEmpty {
                PlateLabel(text: message, size: 8, color: CanonColor.rust)
                    .lineLimit(2)
            }
            ForEach(Array(clips.enumerated()), id: \.offset) { index, clip in
                clipRow(clip, ordinal: index + 1, version: version)
            }
            if clips.isEmpty {
                PlateLabel(
                    text: "No per-segment records — a version from before per-clip provenance.",
                    size: 8,
                    color: PlateColor.inkFaint
                )
            }
        }
        .padding(12)
        .background(PlateColor.creamDeep.opacity(isActive ? 0.5 : 0.28))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(isActive ? CanonColor.brass.opacity(0.7) : PlateColor.hairline, lineWidth: isActive ? 1.2 : 0.7)
        )
    }

    private func clipRow(
        _ clip: ShotRenderSegmentClip,
        ordinal: Int,
        version: ShotRenderArtifact
    ) -> some View {
        let promptKey = "\(version.versionId)|\(clip.placementKey)"
        let isFootage = clip.provider == "footage" || clip.model == "source"
        let reusedFrom = shotClipFirstVersionNumber(
            requestId: clip.requestId,
            versions: shot.sortedRenderVersions
        ).flatMap { $0 < version.versionNumber ? $0 : nil }
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                PlateLabel(text: "\(ordinal)", size: 8, weight: .bold, color: PlateColor.inkFaint)
                    .frame(minWidth: 12, alignment: .trailing)
                PlateLabel(
                    text: shotClipModelShortLabel(provider: clip.provider, model: clip.model),
                    size: 8.5,
                    weight: .semibold,
                    color: PlateColor.ink
                )
                PlateLabel(text: durationLabel(clip), size: 8, color: PlateColor.inkFaint)
                if clip.generateAudio {
                    PlateLabel(text: "AUDIO", size: 7.5, weight: .bold, color: PlateColor.inkFaint)
                        .help("Rendered with the model's native audio — it plays on the SOURCE lane")
                }
                if let resolution = clip.resolution.trimmed.nilIfEmpty {
                    PlateLabel(text: resolution, size: 8, color: PlateColor.inkFaint)
                }
                if let reusedFrom {
                    PlateLabel(
                        text: "REUSED · from \(FrameCreatorModal.romanNumeral(reusedFrom).lowercased())",
                        size: 7.5,
                        weight: .bold,
                        color: CanonColor.brass
                    )
                    .help("This clip traveled in verbatim from version \(reusedFrom) — nothing was re-rendered or spent for it here")
                }
                Spacer(minLength: 0)
                if !isFootage, !clip.prompt.trimmed.isEmpty {
                    Button(expandedPrompts.contains(promptKey) ? "Hide prompt" : "Prompt") {
                        if expandedPrompts.contains(promptKey) {
                            expandedPrompts.remove(promptKey)
                        } else {
                            expandedPrompts.insert(promptKey)
                        }
                    }
                    .buttonStyle(PlateButtonStyle())
                    .help("The exact prompt this clip was rendered with")
                }
                if let trace = clip.traceId.trimmed.nilIfEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(trace, forType: .string)
                        copiedTraceKey = promptKey
                    } label: {
                        PlateLabel(
                            text: copiedTraceKey == promptKey ? "COPIED" : "TRACE",
                            size: 7.5,
                            weight: .bold,
                            color: PlateColor.inkFaint
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Copy this clip's trace id (\(trace))")
                }
            }
            if expandedPrompts.contains(promptKey) {
                Text(clip.prompt)
                    .font(.system(size: 9, design: .serif))
                    .foregroundStyle(PlateColor.ink)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PlateColor.cream.opacity(0.9), in: RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4).stroke(PlateColor.hairline, lineWidth: 0.7)
                    )
            }
        }
        .padding(.leading, 26)
    }

    private func statusLabel(_ version: ShotRenderArtifact) -> some View {
        let (text, color): (String, Color) = {
            switch version.status {
            case "ready": return ("READY", PlateColor.inkFaint)
            case "failed": return ("FAILED", CanonColor.rust)
            case "generating": return ("RENDERING", CanonColor.brass)
            default: return (version.status.uppercased(), PlateColor.inkFaint)
            }
        }()
        return PlateLabel(text: text, size: 8, weight: .bold, color: color)
    }

    private func durationLabel(_ clip: ShotRenderSegmentClip) -> String {
        let measured = clip.durationSeconds > 0
            ? String(format: "%.1fs", clip.durationSeconds)
            : nil
        if clip.requestedDurationSeconds > 0 {
            return measured.map { "\(clip.requestedDurationSeconds)s → \($0)" }
                ?? "\(clip.requestedDurationSeconds)s"
        }
        return measured ?? "—"
    }

    /// "2001-01-31T19:20:00Z" → "2001-01-31 · 19:20", tolerant of anything.
    private func displayDate(_ raw: String) -> String {
        let cleaned = raw.trimmed
        guard cleaned.count >= 16, cleaned.contains("T") else { return cleaned }
        let date = String(cleaned.prefix(10))
        let timeStart = cleaned.index(cleaned.startIndex, offsetBy: 11)
        let time = String(cleaned[timeStart..<cleaned.index(timeStart, offsetBy: 5)])
        return "\(date) · \(time)"
    }
}
