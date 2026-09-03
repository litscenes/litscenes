import SwiftUI

/// Navigable media-version timeline: one chip per version carrying its blend and plan
/// provenance, a Compare toggle that pins a second version for side-by-side reading, and
/// a lossless "Restore this blend" that copies an old version's treatment snapshot back
/// into the draft.
struct LensVersionTimelineView: View {
    let lens: ProjectLens
    @Binding var selectedVersionId: String?
    @Binding var compareVersionId: String?
    var onRestoreBlend: (String) -> Void

    private var versionIds: [String] {
        lens.mediaVersionIds
    }

    private var effectiveSelection: String {
        selectedVersionId ?? versionIds.last ?? ""
    }

    var body: some View {
        if versionIds.count > 1 {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("VERSIONS")
                        .font(CanonType.archive(8.5, weight: .semibold))
                        .kerning(1.4)
                        .foregroundStyle(CanonColor.muted)
                    Spacer()
                    if compareVersionId != nil {
                        Button("Exit compare") { compareVersionId = nil }
                            .buttonStyle(.plain)
                            .font(CanonType.interface(10.5, weight: .semibold))
                            .foregroundStyle(CanonColor.brass)
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(versionIds.enumerated()), id: \.element) { index, versionId in
                            versionChip(versionId: versionId, index: index)
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
        }
    }

    private func versionChip(versionId: String, index: Int) -> some View {
        let isSelected = versionId == effectiveSelection
        let isCompare = versionId == compareVersionId
        let isNewest = versionId == versionIds.last
        let snapshot = lens.blendSnapshot(mediaVersion: versionId)
        let readyCount = lens.heroImages(mediaVersion: versionId).filter { $0.status == "ready" }.count
        return Button {
            if compareVersionId != nil, versionId != effectiveSelection {
                compareVersionId = versionId
            } else {
                selectedVersionId = isNewest ? nil : versionId
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(isNewest ? "v\(index + 1) · newest" : "v\(index + 1)")
                        .font(CanonType.archive(9, weight: .semibold))
                        .foregroundStyle(isSelected ? CanonColor.ink : CanonColor.ink.opacity(0.6))
                    if isCompare {
                        Text("COMPARE")
                            .font(CanonType.archive(7, weight: .bold))
                            .kerning(0.8)
                            .foregroundStyle(CanonColor.paper)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(CanonColor.focusBlue))
                    }
                    if readyCount == 0 {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: 8))
                            .foregroundStyle(CanonColor.rust)
                    }
                }
                if !snapshot.isEmpty {
                    Text(snapshot)
                        .font(CanonType.archive(8))
                        .foregroundStyle(CanonColor.ink.opacity(0.5))
                        .lineLimit(1)
                        .frame(maxWidth: 210, alignment: .leading)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? CanonColor.paper : CanonColor.paperInset.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(
                        isCompare ? CanonColor.focusBlue : (isSelected ? CanonColor.brass.opacity(0.8) : CanonColor.hairlinePaper),
                        lineWidth: isSelected || isCompare ? 1.4 : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .contextMenu {
            if compareVersionId == nil, versionIds.count > 1, versionId != effectiveSelection {
                Button("Compare with selected") { compareVersionId = versionId }
            }
            if !isNewest, hasRestorableBlend(versionId: versionId) {
                Button("Restore this blend") { onRestoreBlend(versionId) }
            }
        }
        .help(snapshot.isEmpty ? "Media version \(index + 1)" : snapshot)
    }

    private func hasRestorableBlend(versionId: String) -> Bool {
        lens.heroImages(mediaVersion: versionId).contains {
            $0.sourceRecipeId?.hasPrefix(LensStyleTreatment.snapshotPrefix) == true
        }
    }
}

extension LensStyleTreatment {
    /// Prefix marking a JSON-encoded treatment snapshot stored in a hero image's
    /// previously-unused sourceRecipeId, enabling lossless blend restore.
    static let snapshotPrefix = "treatment-json:"

    var snapshotIdentifier: String {
        guard let data = try? JSONCoding.encoder.encode(self) else { return "" }
        return Self.snapshotPrefix + data.base64EncodedString()
    }

    static func fromSnapshotIdentifier(_ value: String?) -> LensStyleTreatment? {
        guard let value, value.hasPrefix(snapshotPrefix) else { return nil }
        let encoded = String(value.dropFirst(snapshotPrefix.count))
        guard let data = Data(base64Encoded: encoded),
              let treatment = try? JSONCoding.decoder.decode(LensStyleTreatment.self, from: data) else {
            return nil
        }
        return treatment.normalized()
    }
}
