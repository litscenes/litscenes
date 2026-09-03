import CoreGraphics
import Foundation

/// Everything the fixed-width track header needs to draw one audio lane,
/// resolved BEFORE the view builds.
///
/// The type deliberately carries no widths: the header lays out fixed slots
/// (see `ShotAudioLaneHeadLayout`), so a lane physically cannot widen the
/// gutter and break the shared time axis. That was the old defect — the
/// accessory cluster lived in the row flow, so each lane's waveform began at
/// a different x, up to 163pt apart.
struct ShotAudioLaneHead: Equatable, Sendable {
    var laneId: String
    var name: String
    var isEnabled: Bool
    var isAvailable: Bool
    var chip: Chip
    var action: Action
    /// Live input level, non-nil only on the microphone lane.
    var inputLevel: Double?
    var ownsSelection: Bool

    /// The lane's summary + its picker. Always present at the same x on every
    /// lane, so varying MENU CONTENTS is invisible to layout — which is what
    /// let the old conditional "N REGIONS" control disappear without losing
    /// the affordance.
    struct Chip: Equatable, Sendable {
        var text: String
        var tone: Tone
        /// False when the menu would be empty — rendered quiet, not clickable.
        var isActionable: Bool
        var help: String
    }

    enum Action: Equatable, Sendable {
        case none
        case record(isActive: Bool, isBusy: Bool)
    }

    enum Tone: Equatable, Sendable {
        case ink
        case faint
        /// Operator intent is shaping this lane — a region or segment muted or
        /// turned down. Outranked by `rust`, which stays reserved for a missing
        /// file: a deliberate mute must never read as breakage.
        case brass
        case rust
    }
}

/// The head gutter's slot budget. `totalWidth` must equal
/// `ShotTimelineAxis.headWidth` — pinned by a test, because a slot edit that
/// silently overflowed would push the time area right on one lane only and
/// re-break the axis.
enum ShotAudioLaneHeadLayout {
    static let muteWidth: CGFloat = 20
    static let identityWidth: CGFloat = 78
    static let meterWidth: CGFloat = 4
    static let actionWidth: CGFloat = 20
    static let muteGap: CGFloat = 4
    static let identityGap: CGFloat = 4
    static let meterGap: CGFloat = 2

    static var totalWidth: CGFloat {
        muteWidth + muteGap + identityWidth + identityGap + meterWidth + meterGap + actionWidth
    }
}

/// True when a lane should offer the flat region selector. Carried over from
/// the old inline control's threshold: one region needs no chooser.
func shotAudioLaneOffersRegionSelector(regionCount: Int) -> Bool {
    regionCount > 1
}

/// Resolves one lane's header. Pure: missing-file state arrives as an injected
/// set rather than being probed here, so the whole resolver is testable (the
/// view computes it once per render, where `FileManager` belongs).
func shotAudioLaneHead(
    laneId: String,
    laneLabel: String,
    isEnabled: Bool,
    laneVolume: Double,
    regions: [ShotAudioRegion],
    missingRegionIds: Set<String>,
    /// Files that exist on disk but could not be read — cloud placeholders
    /// awaiting download. MISSING outranks OFFLINE: a gone file needs a
    /// relink, an offline one only a download, and when both afflict a lane
    /// the harder repair leads.
    offlineRegionIds: Set<String> = [],
    emptyText: String,
    unit: String,
    hasPickerTargets: Bool,
    /// True when the operator has muted or attenuated something on this lane.
    /// Colours the chip brass so a shaped lane is legible without opening it.
    hasOperatorAttenuation: Bool = false,
    takeSummary: String? = nil,
    microphoneMode: ShotMicrophoneControlMode? = nil,
    microphoneLevel: Double? = nil,
    selectedRegionId: String? = nil,
    /// Combined-cut source ENVELOPE regions (authored per-section gain) ride
    /// the source lane's menu but are not spans, so they must not change the
    /// chip's span count — they only keep the chip actionable and let the
    /// head own an envelope selection.
    sourceEnvelopeCount: Int = 0,
    ownsEnvelopeSelection: Bool = false
) -> ShotAudioLaneHead {
    // These two compare the LANE ID, not the kind, and must keep doing so.
    // Recording targets the base `microphone` lane, so only that row may carry
    // the record action; SOURCE never extends at all.
    let isMicrophone = laneId == ShotAudioLaneId.microphone
    let isSource = ShotAudioLaneId.kind(ofLaneId: laneId) == ShotAudioLaneId.source

    var chipText: String
    var tone: ShotAudioLaneHead.Tone
    let hasMissing = regions.contains { missingRegionIds.contains($0.regionId) }
    let hasOffline = regions.contains { offlineRegionIds.contains($0.regionId) }
    if let takeSummary {
        chipText = takeSummary
        tone = regions.isEmpty ? .faint : .ink
    } else if regions.isEmpty {
        chipText = emptyText
        tone = .faint
    } else if hasMissing {
        chipText = "MISSING \(unit)"
        tone = .rust
    } else if hasOffline {
        chipText = "OFFLINE \(unit)"
        tone = .rust
    } else if regions.count == 1 {
        chipText = (regions[0].label.trimmed.nilIfEmpty ?? unit).uppercased()
        tone = hasOperatorAttenuation ? .brass : .ink
    } else {
        chipText = "\(regions.count) \(unit)S"
        tone = hasOperatorAttenuation ? .brass : .ink
    }

    // A source lane has no picker — its bands are the picture's own audio —
    // so its chip is a selector and goes quiet when there is nothing to pick.
    let offersSelector = shotAudioLaneOffersRegionSelector(regionCount: regions.count)
    var isActionable = hasPickerTargets || offersSelector
    if isSource { isActionable = offersSelector || sourceEnvelopeCount > 0 }
    // Changing routing mid-take would rewrite what is being recorded.
    if isMicrophone, microphoneMode?.isActive == true { isActionable = false }

    let help: String
    if isSource {
        help = offersSelector
            ? "Select one of this cut's source spans"
            : (regions.isEmpty
                ? "Source audio rides the picture and cannot be re-pointed"
                : "This cut's own picture audio")
    } else if regions.isEmpty {
        help = "Place audio on the \(laneLabel) lane — or drag a file straight onto it"
    } else if tone == .rust, hasMissing {
        help = "A file behind this lane is missing — REPLACE in the inspector relinks it"
    } else if tone == .rust {
        help = "A file behind this lane is offline in cloud storage — open it in Finder to download it"
    } else {
        help = "\(regions.count) region\(regions.count == 1 ? "" : "s") on the \(laneLabel) lane"
    }

    let action: ShotAudioLaneHead.Action
    if isMicrophone, let microphoneMode {
        // Structural, not incidental: with the strip replaced in Look mode
        // this is the only recording affordance on screen.
        action = .record(
            isActive: microphoneMode.isActive,
            isBusy: microphoneMode == .finalizing
        )
    } else {
        action = .none
    }

    return ShotAudioLaneHead(
        laneId: laneId,
        name: laneLabel.uppercased(),
        isEnabled: isEnabled,
        isAvailable: !regions.isEmpty || isMicrophone,
        chip: ShotAudioLaneHead.Chip(
            text: chipText,
            tone: tone,
            isActionable: isActionable,
            help: help
        ),
        action: action,
        inputLevel: isMicrophone ? (microphoneLevel ?? 0) : nil,
        ownsSelection: ownsEnvelopeSelection
            || (selectedRegionId.map { id in regions.contains { $0.regionId == id } } ?? false)
    )
}
