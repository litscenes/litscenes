import Foundation

// MARK: - Temporal direction compiler (neutral plan → provider dialect)

/// Bumped whenever any dialect's wording changes, so provenance can tell
/// "same beats, new compiler" from "new beats".
let shotTemporalCompilerVersion = 1

/// One element of Kling v3's native `multi_prompt` array.
struct ShotCompiledKlingShot: Codable, Hashable, Sendable {
    var prompt: String = ""
    var durationSeconds: Int = 0

    private enum CodingKeys: String, CodingKey {
        case prompt
        case durationSeconds
    }

    init(prompt: String = "", durationSeconds: Int = 0) {
        self.prompt = prompt
        self.durationSeconds = durationSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        durationSeconds = try container.decodeIfPresent(Int.self, forKey: .durationSeconds) ?? 0
    }
}

/// The compiled form of one segment's temporal direction: exactly one payload
/// shape, plus the dialect label provenance wears. `canonicalText` is TOTAL —
/// for `.prompt` it IS the payload; for `.klingMultiShot` it is the
/// deterministic human-readable serialization the plan item shows as its
/// generated prompt.
struct ShotCompiledSegmentDirection: Equatable, Sendable {
    enum Payload: Equatable, Sendable {
        case prompt(String)
        case klingMultiShot([ShotCompiledKlingShot])
    }

    var payload: Payload
    var dialect: String
    var compilerVersion: Int = shotTemporalCompilerVersion

    var canonicalText: String {
        switch payload {
        case .prompt(let text):
            return text
        case .klingMultiShot(let shots):
            return shots.enumerated().map { index, shot in
                "Shot \(index + 1) (\(shot.durationSeconds)s): \(shot.prompt)"
            }.joined(separator: "\n")
        }
    }

    var klingShots: [ShotCompiledKlingShot]? {
        if case .klingMultiShot(let shots) = payload { return shots }
        return nil
    }
}

/// PURE compile of a temporal direction plan into one provider's dialect.
/// Dialect keys off the `VideoModelSelection` the render actually resolves to
/// (`renderStack.modelSelection(for:)`), never off provider guesswork. Blank
/// beats drop before allocation (you cannot direct nothing); an effectively
/// empty plan or non-positive duration returns nil and the caller falls back
/// to the classic `shotSegmentPrompt` sentence.
///
/// The beats ≠ shots law lives here: only `shotMode == .multiShot` may emit
/// a hard-cut structure (`.klingMultiShot`, "Cut to"); continuous plans
/// always compile to a single-take prompt no matter how many beats they hold.
func compileTemporalDirection(
    plan: ShotTemporalDirectionPlan,
    modelSelection: VideoModelSelection,
    durationSeconds: Int
) -> ShotCompiledSegmentDirection? {
    let directed = ShotTemporalDirectionPlan(
        shotMode: plan.shotMode,
        beats: plan.beats.map { $0.normalized() }.filter { !$0.isBlank }
    )
    guard durationSeconds > 0, !directed.beats.isEmpty else { return nil }
    let windows = shotTemporalBeatAllocation(plan: directed, totalSeconds: durationSeconds)
    guard !windows.isEmpty else { return nil }
    let multiShot = directed.shotMode == .multiShot

    switch modelSelection {
    case .falSeedance25ImageToVideo:
        return ShotCompiledSegmentDirection(
            payload: .prompt(seedance25Intervals(windows: windows, multiShot: multiShot)),
            dialect: "seedance25_intervals"
        )
    case .falKlingV3ProImageToVideo:
        if multiShot, windows.count >= 2,
           windows.allSatisfy({ (1...15).contains($0.endSecond - $0.startSecond) }),
           windows.last?.endSecond == durationSeconds {
            let shots = windows.map { window in
                ShotCompiledKlingShot(
                    prompt: sentence(clause(window.beat)),
                    durationSeconds: window.endSecond - window.startSecond
                )
            }
            return ShotCompiledSegmentDirection(
                payload: .klingMultiShot(shots),
                dialect: "kling_multi_prompt"
            )
        }
        // A multi-shot plan that cannot form a valid shot array degrades to
        // timed prose — never a silently mangled array.
        return ShotCompiledSegmentDirection(
            payload: .prompt(klingTimedProse(windows: windows, multiShot: multiShot)),
            dialect: "kling_timed_prose"
        )
    case .falWan27ImageToVideo, .civitaiWanV27, .civitaiWanV25ImageToVideo:
        return ShotCompiledSegmentDirection(
            payload: .prompt(wanShotStamps(windows: windows, multiShot: multiShot)),
            dialect: "wan_shots"
        )
    case .falSeedance20ImageToVideo:
        return ShotCompiledSegmentDirection(
            payload: .prompt(seedance20Ordered(windows: windows, multiShot: multiShot)),
            dialect: "seedance20_ordered"
        )
    default:
        return ShotCompiledSegmentDirection(
            payload: .prompt(collapsedOrdering(windows: windows)),
            dialect: "collapsed"
        )
    }
}

// MARK: - Dialect spellings (all built from ONE allocation — N spellings)

/// "action — camera" with tidy punctuation; either side may be absent.
private func clause(_ beat: ShotTemporalBeat) -> String {
    let action = strippingTrailingPeriod(beat.action.trimmed)
    let camera = strippingTrailingPeriod(beat.camera.trimmed)
    if action.isEmpty { return camera }
    if camera.isEmpty { return action }
    return "\(action) — \(camera)"
}

private func sentence(_ text: String) -> String {
    let trimmed = text.trimmed
    guard !trimmed.isEmpty else { return trimmed }
    return trimmed.hasSuffix(".") ? trimmed : "\(trimmed)."
}

private func strippingTrailingPeriod(_ text: String) -> String {
    text.hasSuffix(".") ? String(text.dropLast()).trimmed : text
}

/// Seedance 2.5 understands integer-second timelines natively.
private func seedance25Intervals(windows: [ShotAllocatedBeat], multiShot: Bool) -> String {
    var parts = windows.enumerated().map { index, window in
        let cut = multiShot && index > 0 ? "Cut to: " : ""
        return "\(window.startSecond)-\(window.endSecond) seconds: \(cut)\(sentence(clause(window.beat)))"
    }
    if !multiShot, windows.count > 1 {
        parts.append("One continuous take — no cuts.")
    }
    return parts.joined(separator: " ")
}

/// Kling 3 continuous: timed prose over one unbroken take. Also the honest
/// degradation target for a multi-shot plan that cannot form a valid
/// `multi_prompt` array.
private func klingTimedProse(windows: [ShotAllocatedBeat], multiShot: Bool) -> String {
    var parts = windows.enumerated().map { index, window in
        let clauseText = sentence(clause(window.beat))
        let cut = multiShot && index > 0 ? "Cut to: " : ""
        if index == 0 {
            return "For the first \(window.endSecond - window.startSecond) seconds, \(cut)\(clauseText)"
        }
        return "From \(window.startSecond) to \(window.endSecond) seconds, \(cut)\(clauseText)"
    }
    if !multiShot, windows.count > 1 {
        parts.append("One continuous take — no cuts.")
    }
    return parts.joined(separator: " ")
}

/// WAN's official formula: overall description + numbered, second-stamped
/// shots. The timing vocabulary uses "Shot" labels even for a continuous
/// take; the guard sentence carries the no-cut intent.
private func wanShotStamps(windows: [ShotAllocatedBeat], multiShot: Bool) -> String {
    let actions = windows.map { strippingTrailingPeriod($0.beat.action.trimmed) }.filter { !$0.isEmpty }
    let overall = actions.isEmpty
        ? strippingTrailingPeriod(clause(windows[0].beat))
        : actions.joined(separator: ", then ")
    let lead = multiShot
        ? "\(sentence(overall))"
        : "Single continuous take, no cuts — \(sentence(overall))"
    let shots = windows.enumerated().map { index, window in
        "Shot \(index + 1) [\(window.startSecond)-\(window.endSecond) s]: \(sentence(clause(window.beat)))"
    }
    return ([lead] + shots).joined(separator: " ")
}

/// Seedance 2.0's own guidance: exact second ranges are unstable — order the
/// beats chronologically with NO timestamps.
private func seedance20Ordered(windows: [ShotAllocatedBeat], multiShot: Bool) -> String {
    var parts = windows.enumerated().map { index, window in
        let clauseText = sentence(clause(window.beat))
        let connector: String
        if index == 0 {
            connector = "First, "
        } else if multiShot {
            connector = "Cut to: "
        } else if index == windows.count - 1 {
            connector = "Finally, "
        } else {
            connector = "Then, "
        }
        return "\(connector)\(clauseText)"
    }
    if !multiShot, windows.count > 1 {
        parts.append("All in one continuous take.")
    }
    return parts.joined(separator: " ")
}

/// Legacy/soft-timing models: ≤3 ordered clauses in one paragraph, capped
/// well under the native Kling (2,500) and CivitAI (1,800) truncators —
/// truncation stays the backstop, never the plan.
private func collapsedOrdering(windows: [ShotAllocatedBeat]) -> String {
    var clauses = windows.map { strippingTrailingPeriod(clause($0.beat)) }.filter { !$0.isEmpty }
    while clauses.count > 3 {
        let last = clauses.removeLast()
        clauses[clauses.count - 1] = "\(clauses[clauses.count - 1]), then \(last)"
    }
    var text = sentence(clauses.joined(separator: ", then "))
    if windows.count > 1 {
        text += " One continuous motion — no cuts, no captions."
    }
    if text.count > 1_200 {
        text = String(text.prefix(1_197)).trimmed + "…"
    }
    return text
}
