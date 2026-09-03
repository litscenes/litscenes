import SwiftUI

/// Guided readiness checklist: blocking issues and warnings as actionable rows with jump
/// actions, replacing the old flat warning-chip pile.
struct LensReadinessChecklistView: View {
    enum JumpTarget {
        case editBlend
        case regenerateMedia
        case editNotes
    }

    let report: LensReadinessReport
    let hasTreatment: Bool
    let hasMedia: Bool
    var onJump: (JumpTarget) -> Void

    private var rows: [(issue: LensReadinessIssue, blocking: Bool)] {
        report.blockingIssues.map { ($0, true) } + report.warnings.map { ($0, false) }
    }

    var body: some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: report.isReady ? "checkmark.seal" : "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(report.isReady ? CanonColor.olive : CanonColor.rust)
                    Text(report.isReady ? "Ready, with notes" : "Not ready yet")
                        .font(CanonType.interface(12.5, weight: .semibold))
                        .foregroundStyle(CanonColor.ink)
                    Text("\(report.blockingIssues.count) blocking · \(report.warnings.count) advisory")
                        .font(CanonType.archive(9))
                        .foregroundStyle(CanonColor.muted)
                    Spacer()
                }
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(rows.prefix(12), id: \.issue) { row in
                        checklistRow(issue: row.issue, blocking: row.blocking)
                    }
                    if rows.count > 12 {
                        Text("+ \(rows.count - 12) more")
                            .font(CanonType.archive(9))
                            .foregroundStyle(CanonColor.muted)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                (report.isReady ? CanonColor.olive : CanonColor.rust).opacity(0.06),
                in: RoundedRectangle(cornerRadius: 9)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke((report.isReady ? CanonColor.olive : CanonColor.rust).opacity(0.28))
            )
        }
    }

    private func checklistRow(issue: LensReadinessIssue, blocking: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: blocking ? "circle" : "circle.dotted")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(blocking ? CanonColor.rust : CanonColor.muted)
            Text(issue.label)
                .font(CanonType.interface(11))
                .foregroundStyle(CanonColor.ink.opacity(blocking ? 0.85 : 0.65))
            Spacer(minLength: 6)
            if let action = jumpAction(for: issue) {
                Button(action.label) { onJump(action.target) }
                    .buttonStyle(.plain)
                    .font(CanonType.interface(10.5, weight: .semibold))
                    .foregroundStyle(CanonColor.brass)
            }
        }
    }

    private func jumpAction(for issue: LensReadinessIssue) -> (label: String, target: JumpTarget)? {
        switch issue {
        case .noStyleIngredients:
            return hasTreatment ? nil : ("Choose styles", .editBlend)
        case .missingVisualHydration, .thinVisualSummary, .noPaletteOrMotif:
            return hasMedia ? nil : ("Generate media", .regenerateMedia)
        case .openQuestionsRemain:
            return ("Review notes", .editNotes)
        default:
            return nil
        }
    }
}
