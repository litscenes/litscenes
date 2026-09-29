import SwiftUI

struct ImagePromptDetailsView: View {
    var preparation: PreparedImagePrompt

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(preparation.model) · \(preparation.billingSource == "go" ? "LitScenes Go" : "Personal provider")")
                .font(CanonType.interface(11, weight: .semibold))
            if preparation.wasShortened { ImagePromptShorteningNotice(preparation: preparation) }
            if !preparation.errorMessage.isEmpty { Text(preparation.errorMessage).foregroundStyle(CanonColor.rust) }
            stage("Authored prompt", fields: ["prompt": preparation.sourcePrompt])
            stage("Assembled prompt", fields: preparation.assembledFields)
            stage("Prepared for provider", fields: preparation.providerFields)
            if let submitted = preparation.submittedFields {
                stage("Submitted prompt", fields: submitted)
            } else {
                Text("No image submission recorded for this preparation.").foregroundStyle(.secondary)
            }
            ForEach(preparation.constraints, id: \.self) { constraint in
                Text("\(constraint.field): maximum \(constraint.maximum.formatted()) characters · \(constraint.evidence)")
                    .font(CanonType.interface(10)).textSelection(.enabled)
            }
            if preparation.constraints.isEmpty { Text("No verified character maximum for this endpoint.").foregroundStyle(.secondary) }
            ForEach(preparation.references, id: \.id) { reference in
                Text("\(reference.id) · \(reference.role) · \(reference.filename)").textSelection(.enabled)
            }
            Text("Trace: \(preparation.traceId)").font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
        }.font(CanonType.interface(12))
    }

    private func stage(_ title: String, fields: [String: String]) -> some View {
        DisclosureGroup(title) {
            ForEach(fields.keys.sorted(), id: \.self) { key in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(key.replacingOccurrences(of: "_", with: " ")) · \((fields[key] ?? "").unicodeScalars.count.formatted()) characters")
                        .font(CanonType.interface(10)).foregroundStyle(.secondary)
                    Text(fields[key] ?? "").textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

struct ImagePromptHistoryView: View {
    var projectId: String
    var artifactId: String
    @ObservedObject private var workflows = WorkflowCoordinator.shared

    var body: some View {
        if let job = workflows.jobs.filter({ $0.projectId == projectId && $0.artifactId == artifactId && !($0.imagePrompts ?? []).isEmpty })
            .max(by: { $0.updatedAt < $1.updatedAt }), let preparation = job.imagePrompts?.last {
            DisclosureGroup("Latest image request") {
                ImagePromptDetailsView(preparation: preparation)
                Button("View render log") {
                    workflows.selectedLogId = job.id
                    workflows.showingLogs = true
                }.buttonStyle(.plain)
            }
        }
    }
}


struct ImagePromptShorteningNotice: View {
    var preparation: PreparedImagePrompt
    @State private var showingChanges = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(preparation.shorteningNotice).fixedSize(horizontal: false, vertical: true)
            Button("See what changed") { showingChanges = true }
                .buttonStyle(.plain).underline()
                .popover(isPresented: $showingChanges) { ImagePromptChangesView(preparation: preparation) }
        }.font(CanonType.interface(11))
    }
}

struct ImagePromptChangesView: View {
    var preparation: PreparedImagePrompt

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Prompt changes for this render").font(CanonType.interface(16, weight: .semibold))
            Text("Your authored prompt is unchanged. This render uses the shortened version.").font(CanonType.interface(12))
            if !preparation.changeSummary.isEmpty { Text(preparation.changeSummary).font(CanonType.interface(12)) }
            ScrollView {
                ForEach(preparation.assembledFields.keys.sorted().filter { preparation.assembledFields[$0] != preparation.providerFields[$0] }, id: \.self) { field in
                    let before = preparation.assembledFields[field] ?? ""
                    let after = preparation.providerFields[field] ?? ""
                    let change = imagePromptComparison(before: before, after: after)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(field.replacingOccurrences(of: "_", with: " ").capitalized).font(CanonType.interface(12, weight: .semibold))
                        HStack(alignment: .top, spacing: 16) {
                            column("Before · \(before.unicodeScalars.count.formatted()) characters", text: change.before)
                            column("Prepared · \(after.unicodeScalars.count.formatted()) characters", text: change.after)
                        }
                    }
                }
            }
        }.padding(20).frame(width: 860, height: 600)
    }

    private func column(_ title: String, text: AttributedString) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(CanonType.interface(11, weight: .semibold))
            Text(text).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Linear comparison keeps very long prompts responsive and preserves every character.
func imagePromptComparison(before: String, after: String) -> (before: AttributedString, after: AttributedString) {
    let old = Array(before), new = Array(after)
    var prefix = 0
    while prefix < min(old.count, new.count), old[prefix] == new[prefix] { prefix += 1 }
    var suffix = 0
    while suffix < min(old.count, new.count) - prefix,
          old[old.count - suffix - 1] == new[new.count - suffix - 1] { suffix += 1 }
    func highlighted(_ characters: [Character], color: Color) -> AttributedString {
        var result = AttributedString(String(characters.prefix(prefix)))
        var changed = AttributedString(String(characters[prefix..<(characters.count - suffix)]))
        changed.backgroundColor = color.opacity(0.18)
        result.append(changed)
        result.append(AttributedString(String(characters.suffix(suffix))))
        return result
    }
    return (highlighted(old, color: .red), highlighted(new, color: .green))
}

/// Nonblocking notice in the existing workspace; the durable comparison also lives in Logs.
struct ImagePromptNoticeBanner: View {
    var projectId: String
    @ObservedObject private var workflows = WorkflowCoordinator.shared
    @State private var dismissed: Set<String> = []

    var body: some View {
        let latest = workflows.jobs.filter { $0.projectId == projectId && !($0.imagePrompts ?? []).isEmpty }
            .max { $0.createdAt < $1.createdAt }?.imagePrompts?.last
        if let preparation = latest, preparation.wasShortened, !dismissed.contains(preparation.id) {
            HStack(alignment: .center, spacing: 12) {
                ImagePromptShorteningNotice(preparation: preparation)
                Spacer(minLength: 0)
                Button { dismissed.insert(preparation.id) } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).help("Hide this notice; prompt changes remain in Logs")
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .foregroundStyle(CanonColor.ink).background(CanonColor.paper)
        }
    }
}
