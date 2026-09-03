import SwiftUI

/// The GOAL rail CAST panel: the project's nascent characters articulated as steerable
/// unusual-character identities. Sits directly below Style taxonomy in the rail's
/// articulated-artifacts zone; every gesture auto-saves to the goal-cast document,
/// independent of the brief's Save/Revert.
struct GoalCastPanelView: View {
    @ObservedObject var library: LibraryEngine

    private var goalIsReady: Bool {
        library.projectGoalV2.activeVersion?.brief.isReady == true
    }

    private var castIsFull: Bool {
        library.goalCast.members.count >= GoalCastDocument.maximumMembers
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Text("Cast")
                    .font(CanonType.interface(13, weight: .semibold))
                    .foregroundStyle(CanonColor.ink)
                Text("steerable")
                    .font(CanonType.archive(9))
                    .foregroundStyle(CanonColor.brass.opacity(0.85))
                Spacer()
                if library.isArticulatingGoalCast {
                    ProgressView()
                        .controlSize(.mini)
                }
                castActionButton("Re-cast", disabled: !goalIsReady || library.isArticulatingGoalCast) {
                    Task { await library.rearticulateGoalCast() }
                }
                .help("Re-articulate from the current Goal — matched characters keep their takes and pins")
                castActionButton("+ Add", disabled: !goalIsReady || library.isArticulatingGoalCast || castIsFull) {
                    Task { await library.addGoalCastMember() }
                }
                .help("Articulate one more character from the Goal")
            }
            Text("Articulated from the saved Goal. Steer each character here or in chat; takes are non-destructive.")
                .font(CanonType.editorial(11.5))
                .foregroundStyle(CanonColor.ink.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)

            if !goalIsReady {
                Text("Save a Goal first — the cast articulates from it.")
                    .font(CanonType.interface(12))
                    .foregroundStyle(CanonColor.ink.opacity(0.5))
                    .padding(.top, 2)
            } else if library.goalCast.members.isEmpty {
                if library.isArticulatingGoalCast {
                    HStack(spacing: 9) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Articulating cast")
                            .font(CanonType.interface(12, weight: .semibold))
                            .foregroundStyle(CanonColor.ink.opacity(0.72))
                    }
                    .padding(.top, 2)
                } else if library.goalCast.articulatedAt.isEmpty {
                    Text("Not cast yet — save the Goal and the characters appear here.")
                        .font(CanonType.interface(12))
                        .foregroundStyle(CanonColor.ink.opacity(0.5))
                        .padding(.top, 2)
                } else {
                    Text("No cast articulated — Re-cast to try again, or ask for characters in chat.")
                        .font(CanonType.interface(12))
                        .foregroundStyle(CanonColor.ink.opacity(0.5))
                        .padding(.top, 2)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(library.goalCast.members) { member in
                        GoalCastMemberCard(library: library, member: member)
                    }
                }
            }

            if !library.goalCastStatus.isEmpty {
                Text(library.goalCastStatus)
                    .font(CanonType.interface(10.5))
                    .foregroundStyle(CanonColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
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

    private func castActionButton(_ title: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(CanonType.interface(11, weight: .semibold))
                .foregroundStyle(CanonColor.ink.opacity(disabled ? 0.35 : 0.75))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.46), in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(CanonColor.hairlinePaper)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

/// One steerable character card: provenance-tooltipped roman-numeral take cycler,
/// engraved strangeness tick meter, pinnable dimension rows, one-tap steer chips, and
/// the "Same soul, but…" feedback field.
private struct GoalCastMemberCard: View {
    @ObservedObject var library: LibraryEngine
    let member: GoalCastMember

    @State private var feedbackDraft = ""

    private var identity: GoalCastIdentity { member.activeIdentity }

    private var isSteering: Bool {
        library.steeringGoalCastMemberIds.contains(member.memberId)
    }

    private var pinnedSet: Set<GoalCastDimension> { member.pinnedDimensionSet }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            nameRow
            if member.takes.count > 1 {
                takeCycler
            }
            if !identity.essence.isEmpty {
                Text(identity.essence)
                    .font(CanonType.editorial(12).italic())
                    .foregroundStyle(CanonColor.ink.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
                    .help(identity.formativePressure.isEmpty ? identity.essence : identity.formativePressure)
            }
            strangenessMeter
            dimensionRows
            steerChipRow
            feedbackField
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.35), in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(CanonColor.hairlinePaper)
        )
    }

    private var nameRow: some View {
        HStack(spacing: 7) {
            Text(member.name)
                .font(CanonType.interface(12.5, weight: .semibold))
                .foregroundStyle(CanonColor.ink)
            if !member.roleLabel.isEmpty {
                Text(member.roleLabel.uppercased())
                    .font(CanonType.archive(8))
                    .kerning(1.0)
                    .foregroundStyle(CanonColor.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if isSteering {
                ProgressView()
                    .controlSize(.mini)
            }
            Button {
                library.removeGoalCastMember(memberId: member.memberId)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(CanonColor.ink.opacity(0.4))
            }
            .buttonStyle(.plain)
            .help("Remove from cast — the roster character is kept")
        }
    }

    /// Lowercase roman numerals, brass underline rule under the active take; each
    /// numeral's tooltip is the take's gesture provenance — the recovery breadcrumb.
    private var takeCycler: some View {
        HStack(spacing: 10) {
            ForEach(Array(member.takes.enumerated()), id: \.element.takeId) { index, take in
                let isActive = take.takeId == member.activeTakeId
                Button {
                    library.activateGoalCastTake(memberId: member.memberId, takeId: take.takeId)
                } label: {
                    VStack(spacing: 2) {
                        Text(castRomanNumeral(index + 1))
                            .font(CanonType.archive(11, weight: isActive ? .semibold : .regular))
                            .foregroundStyle(isActive ? CanonColor.ink : CanonColor.ink.opacity(0.45))
                        Rectangle()
                            .fill(isActive ? CanonColor.brass : Color.clear)
                            .frame(width: 14, height: 0.75)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(take.origin)
            }
            Spacer(minLength: 0)
        }
    }

    private var strangenessMeter: some View {
        let litTicks = Int((identity.strangeness * 10).rounded())
        return HStack(spacing: 7) {
            Text("STRANGENESS")
                .font(CanonType.archive(8.5, weight: .semibold))
                .kerning(1.3)
                .foregroundStyle(CanonColor.muted)
            HStack(spacing: 3) {
                ForEach(0..<10, id: \.self) { tick in
                    Rectangle()
                        .fill(tick < litTicks ? CanonColor.brass : CanonColor.hairlinePaper)
                        .frame(width: 2, height: 6)
                }
            }
            Text(String(format: "%.2f", identity.strangeness))
                .font(CanonType.archive(9))
                .foregroundStyle(CanonColor.brass)
            Spacer(minLength: 0)
        }
        .help("The distance between the familiar role and the incongruous desire — 0 is honestly plain")
    }

    private var dimensionRows: some View {
        let rows: [(label: String, dimension: GoalCastDimension, value: String)] = [
            ("FUNCTION", .publicFunction, identity.publicFunction),
            ("WANTS", .desire, identity.desire),
            ("RULE", .operatingRule, identity.operatingRule),
            ("COST", .cost, identity.cost),
            ("TELL", .signature, identity.signature)
        ]
        return VStack(alignment: .leading, spacing: 5) {
            ForEach(rows.filter { !$0.value.isEmpty }, id: \.label) { row in
                dimensionRow(row.label, dimension: row.dimension, value: row.value)
            }
            if !identity.visualDescription.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("VISUAL")
                        .font(CanonType.archive(8.5, weight: .semibold))
                        .kerning(1.3)
                        .foregroundStyle(CanonColor.muted.opacity(0.8))
                        .frame(width: 74, alignment: .leading)
                    Text(identity.visualDescription)
                        .font(CanonType.interface(10.5))
                        .foregroundStyle(CanonColor.muted)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .help("Render-facing appearance — this line syncs to the roster description")
            }
        }
    }

    private func dimensionRow(_ label: String, dimension: GoalCastDimension, value: String) -> some View {
        let isPinned = pinnedSet.contains(dimension)
        return HStack(alignment: .firstTextBaseline, spacing: 7) {
            HStack(spacing: 3) {
                Text(label)
                    .font(CanonType.archive(8.5, weight: .semibold))
                    .kerning(1.3)
                    .foregroundStyle(isPinned ? CanonColor.brass : CanonColor.muted)
                if isPinned {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(CanonColor.brass)
                }
            }
            .frame(width: 74, alignment: .leading)
            Text(value)
                .font(CanonType.interface(11.5))
                .foregroundStyle(CanonColor.ink.opacity(0.86))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            library.toggleGoalCastPin(memberId: member.memberId, dimension: dimension)
        }
        .help(isPinned
            ? "Pinned — kept exactly through steers and Re-cast. Click to unpin."
            : "Click to pin — keep this exactly through steers and Re-cast")
    }

    private var steerChipRow: some View {
        StyleStudioFlowLayout(spacing: 5) {
            steerChip("Stranger", gesture: .stranger, help: "Widen the distance between the role and the desire — one new take")
            steerChip("Tamer", gesture: .tamer, help: "Ease toward ordinary — bottoms out at plain")
            steerChip("New rule", gesture: .newRule, help: "A different private rule for the same contradiction")
            steerChip("Raise cost", gesture: .raiseCost, help: "Escalate what living by the rule costs")
            steerChip("New tell", gesture: .newTell, help: "A different recurring action, object, or silhouette")
        }
    }

    private func steerChip(_ label: String, gesture: GoalCastSteerGesture, help: String) -> some View {
        Button {
            Task { await library.steerGoalCastMember(memberId: member.memberId, gesture: gesture) }
        } label: {
            Text(label)
                .font(CanonType.archive(8, weight: .semibold))
                .kerning(0.7)
                .foregroundStyle(CanonColor.ink.opacity(isSteering ? 0.35 : 0.68))
                .padding(.horizontal, 9)
                .frame(height: 21)
                .background(Capsule().fill(Color.white.opacity(0.5)))
                .overlay(Capsule().stroke(CanonColor.hairlinePaper))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isSteering)
        .help(help)
    }

    private var feedbackField: some View {
        HStack(spacing: 6) {
            TextField("Same soul, but…", text: $feedbackDraft)
                .textFieldStyle(.plain)
                .font(CanonType.interface(11.5))
                .foregroundStyle(CanonColor.ink)
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(Color.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(CanonColor.hairlinePaper))
                .onSubmit(sendFeedback)
                .disabled(isSteering)
            if isSteering {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 26, height: 26)
            } else {
                Button(action: sendFeedback) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(CanonColor.paper)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(CanonColor.ink.opacity(0.85)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(feedbackDraft.trimmed.isEmpty)
                .help("Steer this character per your direction — same soul, one new take")
            }
        }
    }

    private func sendFeedback() {
        let directive = feedbackDraft.trimmed
        guard !directive.isEmpty, !isSteering else { return }
        feedbackDraft = ""
        Task {
            await library.steerGoalCastMember(memberId: member.memberId, gesture: .feedback(directive))
            if library.goalCastStatus.hasPrefix("Steer failed"), feedbackDraft.isEmpty {
                feedbackDraft = directive
            }
        }
    }
}

/// Local roman-numeral helper (the Frame Creator's is private to its modal; this branch
/// avoids refactoring shared code).
private func castRomanNumeral(_ value: Int) -> String {
    let numerals = ["i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix", "x"]
    guard value >= 1, value <= numerals.count else { return "\(value)" }
    return numerals[value - 1]
}
