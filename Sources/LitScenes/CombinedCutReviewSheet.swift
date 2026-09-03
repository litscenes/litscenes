import SwiftUI

struct StageCombineReviewRequest: Identifiable {
    let id = UUID()
    var stageId: String
    var sourceCutIds: [String]
    var preflight: CombinedCutPreflight
}

struct CombinedCutReviewSheet: View {
    let request: StageCombineReviewRequest
    var onCancel: () -> Void
    var onCombine: () -> Void

    private var preflight: CombinedCutPreflight { request.preflight }

    /// The preflight bailed before it could describe the sources — showing
    /// empty ORDER rows and all-zero metrics beside a failure block would be
    /// noise dressed as facts, so the sheet shows only the failure.
    private var isFailureOnly: Bool {
        preflight.sourceNames.isEmpty && !preflight.hardFailures.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("COMBINE SHOTS")
                        .font(CanonType.archive(13, weight: .bold))
                        .kerning(1.5)
                        .foregroundStyle(CanonColor.ink)
                    Text("A fresh raw timeline · sources remain preserved")
                        .font(CanonType.archive(8, weight: .semibold))
                        .kerning(0.6)
                        .foregroundStyle(CanonColor.muted)
                }
                Spacer()
                Text("$0")
                    .font(CanonType.archive(18, weight: .bold))
                    .foregroundStyle(CanonColor.brass)
            }
            .padding(20)

            Rectangle().fill(CanonColor.hairlinePaper).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    if isFailureOnly {
                        messageBlock(
                            title: "CAN'T COMBINE YET",
                            messages: preflight.hardFailures,
                            color: CanonColor.rust
                        )
                        Text("Nothing was changed. Fix the issue above and combine again.")
                            .font(CanonType.archive(8, weight: .medium))
                            .foregroundStyle(CanonColor.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        reviewSection("ORDER") {
                            VStack(alignment: .leading, spacing: 7) {
                                ForEach(Array(preflight.sourceNames.enumerated()), id: \.offset) { index, name in
                                    HStack(spacing: 8) {
                                        Text(FrameCreatorModal.romanNumeral(index + 1))
                                            .frame(width: 20, alignment: .leading)
                                            .foregroundStyle(CanonColor.brass)
                                        Text(name)
                                            .foregroundStyle(CanonColor.ink)
                                        if index < preflight.sourceNames.count - 1 {
                                            Spacer()
                                            Text("HARD BOUNDARY")
                                                .foregroundStyle(CanonColor.muted)
                                        }
                                    }
                                    .font(CanonType.archive(8.5, weight: .semibold))
                                }
                            }
                        }

                        reviewSection("COPY") {
                            metricRow([
                                "\(preflight.frameCount) frames",
                                "\(preflight.footageCount) footage",
                                "~\(Int(preflight.estimatedSeconds.rounded()))s"
                            ])
                        }

                        reviewSection("VIDEO") {
                            metricRow([
                                "\(preflight.reusableSegmentCount) reusable",
                                "\(preflight.missingSegmentCount) missing"
                            ])
                        }

                        reviewSection("AUDIO + LOOKS") {
                            metricRow([
                                "\(preflight.audioRegionCount) audio region\(preflight.audioRegionCount == 1 ? "" : "s")",
                                "\(preflight.activeLookCount) source Look\(preflight.activeLookCount == 1 ? "" : "s") excluded"
                            ])
                        }

                        if !preflight.warnings.isEmpty {
                            messageBlock(
                                title: "CONTINUE WITH WARNINGS",
                                messages: preflight.warnings,
                                color: CanonColor.brass
                            )
                        }
                        if !preflight.hardFailures.isEmpty {
                            messageBlock(
                                title: "CAN'T COMBINE YET",
                                messages: preflight.hardFailures,
                                color: CanonColor.rust
                            )
                        }

                        Text("Source Shots become collapsed snapshots. Editing them later will not update the combined Shot, and editing the combined Shot will not alter them.")
                            .font(CanonType.archive(8, weight: .medium))
                            .foregroundStyle(CanonColor.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(20)
            }
            .frame(maxHeight: 560)

            Rectangle().fill(CanonColor.hairlinePaper).frame(height: 1)
            HStack {
                Button("CANCEL", action: onCancel)
                    .buttonStyle(.plain)
                    .foregroundStyle(CanonColor.muted)
                Spacer()
                // A disabled CTA that still promises COMBINE would be a dead
                // button wearing a live label.
                Button(
                    preflight.canCombine ? "COMBINE & OPEN · $0" : "CAN'T COMBINE YET",
                    action: onCombine
                )
                .buttonStyle(PlateButtonStyle(isProminent: preflight.canCombine))
                .disabled(!preflight.canCombine)
            }
            .padding(16)
        }
        .frame(width: 560)
        .background(CanonColor.paper)
    }

    private func reviewSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(CanonType.archive(7.5, weight: .bold))
                .kerning(1.2)
                .foregroundStyle(CanonColor.muted)
            content()
        }
    }

    private func metricRow(_ labels: [String]) -> some View {
        HStack(spacing: 8) {
            ForEach(labels, id: \.self) { label in
                Text(label.uppercased())
                    .font(CanonType.archive(8, weight: .semibold))
                    .foregroundStyle(CanonColor.ink)
                    .padding(.horizontal, 9)
                    .frame(height: 25)
                    .background(Capsule().fill(CanonColor.paperInset))
                    .overlay(Capsule().stroke(CanonColor.hairlinePaper))
            }
        }
    }

    private func messageBlock(title: String, messages: [String], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(CanonType.archive(7.5, weight: .bold))
                .kerning(1)
            ForEach(messages, id: \.self) { message in
                Text("• \(message)")
                    .font(CanonType.archive(8, weight: .medium))
            }
        }
        .foregroundStyle(color)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(color.opacity(0.35)))
    }
}
