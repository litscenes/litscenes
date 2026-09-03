import SwiftUI

// THE ACTIVITY POPOVER — everything the app is doing right now, reachable
// from anywhere: running work (cancel only where a real cancel exists), the
// global pause, the recent spend feed, and the honest totals. Opening it
// acknowledges any spend failures (open == ack, the notices law).

/// Display name for a ledger kind — shared by the popover feed and the
/// full plate.
func spendKindDisplayLabel(_ kind: String) -> String {
    switch kind {
    case "shot_render_segment": return "Segment"
    case "shot_render_narration_driven": return "Narration render"
    case "join_bridge": return "Join bridge"
    case "shot_look": return "Shot Look"
    case "clip_look": return "Clip Look"
    case "image": return "Image"
    case "narration_tts": return "Narration"
    case "story_audio_tts": return "Voice"
    case "sound_effect": return "Sound effect"
    default: return kind.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

/// "8s" / "3 images" / "812 chars" — or "" when the row carries no units.
func spendUnitsLabel(unit: String, unitCount: Double) -> String {
    guard unitCount > 0 else { return "" }
    let count = unitCount == unitCount.rounded()
        ? "\(Int(unitCount))"
        : String(format: "%.1f", unitCount)
    switch unit {
    case "seconds": return "\(count)s"
    case "images": return unitCount == 1 ? "1 image" : "\(count) images"
    case "characters": return "\(count) chars"
    default: return unit.isEmpty ? "" : "\(count) \(unit)"
    }
}

/// "14:32" local wall-clock for a ledger stamp; "" when unparsable.
func spendClockLabel(_ isoAt: String) -> String {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let plain = ISO8601DateFormatter()
    guard let date = fractional.date(from: isoAt) ?? plain.date(from: isoAt) else { return "" }
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
}

/// The caption every surfaced total wears — UNPRICED, NEVER $0's sibling.
let spendHonestyCaption = "Estimates at submission-time rates — not a bill"

struct ActivityPopover: View {
    @ObservedObject var library: LibraryEngine
    var onOpenLedger: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            header
            runningSection
            pauseSection
            recentSection
            spendSection
            footer
        }
        .padding(14)
        .frame(width: 420, alignment: .leading)
        .background(CanonColor.paper)
        .onAppear {
            library.acknowledgeSpendFailures()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Activity")
                    .font(CanonType.interface(14, weight: .semibold))
                    .foregroundStyle(CanonColor.ink)
                Text("RUNNING · RECENT · SPEND")
                    .font(CanonType.archive(9, weight: .semibold))
                    .kerning(0.6)
                    .foregroundStyle(CanonColor.muted)
            }
            Spacer()
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(CanonColor.ink.opacity(0.55))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close")
        }
    }

    // MARK: - Running

    private var runningSection: some View {
        let rows = library.activitySnapshot
        return VStack(alignment: .leading, spacing: 7) {
            Text("RUNNING")
                .font(CanonType.archive(8, weight: .semibold))
                .kerning(1.1)
                .foregroundStyle(CanonColor.muted)
            if rows.isEmpty {
                Text("Nothing running.")
                    .font(CanonType.interface(11))
                    .foregroundStyle(CanonColor.muted)
            } else {
                ForEach(rows) { row in
                    runningRow(row)
                }
            }
        }
    }

    private func runningRow(_ row: ActivityRow) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Circle()
                .fill(row.isPaid ? CanonColor.brass : CanonColor.muted.opacity(0.5))
                .frame(width: 5, height: 5)
                .help(row.isPaid ? "Spends money" : "Free local work")
            Text(row.label)
                .font(CanonType.interface(11.5, weight: .semibold))
                .foregroundStyle(CanonColor.ink)
            if !row.detail.isEmpty {
                Text(row.detail)
                    .font(CanonType.interface(10.5))
                    .foregroundStyle(CanonColor.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if row.cancel != .none {
                Button {
                    library.performActivityCancel(row.cancel)
                } label: {
                    Text("Cancel")
                        .font(CanonType.interface(10.5, weight: .semibold))
                        .foregroundStyle(CanonColor.rust)
                }
                .buttonStyle(.plain)
                .help("Stop this operation")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(CanonColor.paperInset.opacity(0.52))
        )
    }

    // MARK: - Pause

    private var pauseSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(
                get: { library.isGenerationPaused },
                set: { library.setGenerationPaused($0) }
            )) {
                Text("Pause all generation")
                    .font(CanonType.interface(11.5, weight: .semibold))
                    .foregroundStyle(CanonColor.ink)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            Text("Paid work refuses to start while paused; an in-flight step finishes, then parks. Free local bakes continue.")
                .font(CanonType.archive(9))
                .foregroundStyle(CanonColor.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Recent

    private var recentSection: some View {
        let entries = Array(library.spendLedgerSummary.recentEntries.prefix(10))
        return VStack(alignment: .leading, spacing: 6) {
            Text("RECENT")
                .font(CanonType.archive(8, weight: .semibold))
                .kerning(1.1)
                .foregroundStyle(CanonColor.muted)
            if entries.isEmpty {
                Text("No paid operations recorded yet.")
                    .font(CanonType.interface(11))
                    .foregroundStyle(CanonColor.muted)
            } else {
                ForEach(entries) { entry in
                    recentRow(entry)
                }
            }
        }
    }

    private func recentRow(_ entry: SpendLedgerEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(spendClockLabel(entry.at))
                .font(CanonType.archive(9))
                .monospacedDigit()
                .foregroundStyle(CanonColor.muted)
                .frame(width: 34, alignment: .leading)
            Text(spendKindDisplayLabel(entry.kind))
                .font(CanonType.interface(10.5, weight: .semibold))
                .foregroundStyle(entry.isFailure ? CanonColor.rust : CanonColor.ink)
            if !entry.contextLabel.isEmpty {
                Text(entry.contextLabel)
                    .font(CanonType.interface(10))
                    .foregroundStyle(CanonColor.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(entry.isFailure
                ? "failed · charge unknown"
                : spendAmountLabel(usd: entry.estimatedUSD, credits: entry.estimatedCredits))
                .font(CanonType.archive(9, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(entry.isFailure ? CanonColor.rust : CanonColor.ink)
        }
    }

    // MARK: - Spend

    private var spendSection: some View {
        let summary = library.spendLedgerSummary
        let today = summary.totalsByDay[spendLedgerDayKey(DateFormats.now())]
        return VStack(alignment: .leading, spacing: 6) {
            Text("SPEND")
                .font(CanonType.archive(8, weight: .semibold))
                .kerning(1.1)
                .foregroundStyle(CanonColor.muted)
            totalRow(label: "Today", total: today ?? SpendLedgerDayTotal())
            totalRow(label: "This project", total: summary.projectTotal)
            Text(spendHonestyCaption)
                .font(CanonType.archive(9))
                .foregroundStyle(CanonColor.muted)
        }
    }

    private func totalRow(label: String, total: SpendLedgerDayTotal) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(CanonType.interface(11, weight: .semibold))
                .foregroundStyle(CanonColor.ink)
            Spacer()
            if total.unpricedCount > 0 {
                Text(total.unpricedCount == 1 ? "1 unpriced" : "\(total.unpricedCount) unpriced")
                    .font(CanonType.archive(9))
                    .foregroundStyle(CanonColor.muted)
            }
            if total.failedCount > 0 {
                Text(total.failedCount == 1 ? "1 failed" : "\(total.failedCount) failed")
                    .font(CanonType.archive(9))
                    .foregroundStyle(CanonColor.rust)
            }
            Text(total.pricedCount + total.unpricedCount == 0
                ? "—"
                : spendAmountLabel(
                    usd: total.usd > 0 || total.credits == 0 ? total.usd : nil,
                    credits: total.credits > 0 ? total.credits : nil
                ))
                .font(CanonType.archive(10, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(CanonColor.ink)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button {
                onOpenLedger()
            } label: {
                Text("Full ledger…")
                    .font(CanonType.interface(11, weight: .semibold))
                    .foregroundStyle(CanonColor.brass)
            }
            .buttonStyle(.plain)
            .help("Open the full spend ledger, day by day")
        }
    }
}
