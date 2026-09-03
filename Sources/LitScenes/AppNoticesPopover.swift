import AppKit
import SwiftUI

/// The quiet notices inbox: a paper plate hung off the always-visible header
/// tray button. v1 carries one notice — per-location disk usage of the
/// generated-output directories — and only informs; pruning stays manual.
/// Opening it acknowledges the current readings (the badge-dot contract).
struct AppNoticesPopover: View {
    @ObservedObject var library: LibraryEngine
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            header
            if library.diskUsageNotice.locations.isEmpty {
                Text("Measuring generated-output locations…")
                    .font(CanonType.interface(11))
                    .foregroundStyle(CanonColor.muted)
            } else {
                storageSection
            }
            projectVitalsSection
            footer
        }
        .padding(14)
        .frame(width: 340, alignment: .leading)
        .background(CanonColor.paper)
        .onAppear {
            library.acknowledgeDiskUsageNotice()
        }
        .task {
            await library.refreshProjectVitals()
        }
    }

    /// What this project has accumulated. Informational like the rest of the
    /// plate — it names the growth, it never prunes it.
    @ViewBuilder
    private var projectVitalsSection: some View {
        if let vitals = library.projectVitals {
            VStack(alignment: .leading, spacing: 6) {
                Text("THIS PROJECT")
                    .font(CanonType.archive(9, weight: .semibold))
                    .kerning(0.6)
                    .foregroundStyle(CanonColor.muted)
                ForEach(Array(vitals.summaryLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(CanonType.interface(line.hasPrefix("  ") ? 10 : 11))
                        .foregroundStyle(line.hasPrefix("  ") ? CanonColor.muted : CanonColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else if library.isMeasuringProjectVitals {
            Text("Measuring this project…")
                .font(CanonType.interface(11))
                .foregroundStyle(CanonColor.muted)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Notices")
                    .font(CanonType.interface(14, weight: .semibold))
                    .foregroundStyle(CanonColor.ink)
                Text("APP STORAGE")
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

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            locationGroup(title: "APP DATA", readings: readings(in: "app"))
            let workspaceReadings = readings(in: "workspace")
            if !workspaceReadings.isEmpty {
                locationGroup(title: "WORKSPACE", readings: workspaceReadings)
            }
            totalRow
        }
    }

    private func readings(in group: String) -> [DiskUsageLocationReading] {
        library.diskUsageNotice.locations.filter { $0.group == group }
    }

    private func locationGroup(title: String, readings: [DiskUsageLocationReading]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(CanonType.archive(8, weight: .semibold))
                .kerning(1.1)
                .foregroundStyle(CanonColor.muted)
            ForEach(readings) { reading in
                locationRow(reading)
            }
        }
    }

    private func locationRow(_ reading: DiskUsageLocationReading) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(reading.label)
                    .font(CanonType.interface(11.5, weight: .semibold))
                    .foregroundStyle(reading.exists ? CanonColor.ink : CanonColor.muted)
                Text(reading.path)
                    .font(CanonType.archive(9))
                    .foregroundStyle(CanonColor.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if reading.exists {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(ByteCountFormatter.string(fromByteCount: reading.byteCount, countStyle: .file))
                        .font(CanonType.archive(10, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(sizeTint(for: reading.byteCount, warnAt: DiskUsageNoticeTunables.perLocationAttentionBytes))
                    Text(fileCountLabel(reading.fileCount))
                        .font(CanonType.archive(8))
                        .foregroundStyle(CanonColor.muted)
                }
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: reading.path)])
                } label: {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CanonColor.ink.opacity(0.55))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Reveal in Finder")
            } else {
                Text("not present")
                    .font(CanonType.archive(9))
                    .foregroundStyle(CanonColor.muted)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(CanonColor.paperInset.opacity(0.52))
        )
    }

    private var totalRow: some View {
        HStack(spacing: 8) {
            Text("Total")
                .font(CanonType.interface(11.5, weight: .semibold))
                .foregroundStyle(CanonColor.ink)
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: library.diskUsageNotice.totalBytes, countStyle: .file))
                .font(CanonType.archive(10, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(sizeTint(for: library.diskUsageNotice.totalBytes, warnAt: DiskUsageNoticeTunables.totalAttentionBytes))
        }
        .padding(.horizontal, 9)
        .padding(.top, 2)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if library.isMeasuringDiskUsage {
                ProgressView()
                    .controlSize(.small)
                Text("Measuring…")
                    .font(CanonType.archive(9))
                    .foregroundStyle(CanonColor.muted)
            } else {
                Text(measuredAtLabel)
                    .font(CanonType.archive(9))
                    .foregroundStyle(CanonColor.muted)
            }
            Spacer()
            Button {
                Task {
                    await library.refreshDiskUsageNotice()
                }
            } label: {
                Text("Refresh")
                    .font(CanonType.interface(11, weight: .semibold))
                    .foregroundStyle(CanonColor.brass)
            }
            .buttonStyle(.plain)
            .disabled(library.isMeasuringDiskUsage)
            .help("Measure the watched locations again")
        }
    }

    private var measuredAtLabel: String {
        guard !library.diskUsageNotice.measuredAt.isEmpty else { return "Not measured yet" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: library.diskUsageNotice.measuredAt) else { return "Measured earlier" }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .abbreviated
        return "Measured \(relative.localizedString(for: date, relativeTo: Date()))"
    }

    private func fileCountLabel(_ count: Int) -> String {
        count == 1 ? "1 file" : "\(count.formatted()) files"
    }

    private func sizeTint(for bytes: Int64, warnAt threshold: Int64) -> Color {
        if bytes >= threshold * 2 {
            return CanonColor.rust
        }
        if bytes >= threshold {
            return CanonColor.brass
        }
        return CanonColor.ink
    }
}
