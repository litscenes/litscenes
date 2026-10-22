import AppKit
import MeaningGraphCore
import SwiftUI
import UniformTypeIdentifiers

struct MeaningGraphProjectControl: View {
    @ObservedObject var library: LibraryEngine
    @State private var showing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button { showing = true } label: {
                Label("Meaning graph", systemImage: "point.3.connected.trianglepath.dotted")
            }
            if let selection = library.projectMeaningGraphSelection {
                Text("\(selection.base.title) · \(selection.base.version) · \(selection.overlays.filter(\.enabled).count) overlays")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Project graph unavailable").font(.caption).foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showing) {
            if let selection = library.projectMeaningGraphSelection, let project = library.currentProject {
                MeaningGraphProjectSheet(library: library, projectId: project.projectId, original: selection)
            } else {
                Text("Reopen the project to load its graph configuration.").padding(30)
            }
        }
    }
}

private struct MeaningGraphProjectSheet: View {
    @ObservedObject var library: LibraryEngine
    let projectId: String
    let original: ProjectMeaningGraphSelection
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ProjectMeaningGraphSelection
    @State private var sources: [MeaningGraphSource] = []
    @State private var preview: MeaningGraphChangePreview?
    @State private var message = ""
    @State private var busy = false

    init(library: LibraryEngine, projectId: String, original: ProjectMeaningGraphSelection) {
        self.library = library; self.projectId = projectId; self.original = original
        _draft = State(initialValue: original)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Project meaning graph").font(.title2)
            Text("This project keeps its own graph version and ordered overlays. Applying a change refreshes local context for future work. Saved stories and frames keep their original provenance.")
                .font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Base pack", selection: Binding(get: { draft.base.hash }, set: { hash in
                        if let source = sources.first(where: { $0.hash == hash }) { draft.base = source }
                    })) {
                        ForEach(sources.filter { $0.kind == "base" }) { source in
                            Text("\(source.title) · \(source.version)").tag(source.hash)
                        }
                    }
                    Text("Overlays apply from top to bottom. Later overrides win.").font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(draft.overlays.enumerated()), id: \.element.id) { index, layer in
                        HStack {
                            Toggle(isOn: Binding(get: { draft.overlays[index].enabled }, set: { draft.overlays[index].enabled = $0 })) {
                                Text("\(layer.source.title) · \(layer.source.version)")
                            }
                            Button("↑") { draft.overlays.swapAt(index, index - 1) }.disabled(index == 0)
                            Button("↓") { draft.overlays.swapAt(index, index + 1) }.disabled(index == draft.overlays.count - 1)
                            Button("Remove") { draft.overlays.remove(at: index) }
                        }
                    }
                    Menu("Add installed overlay") {
                        ForEach(sources.filter { source in source.kind == "overlay" && !draft.overlays.contains(where: { $0.source.hash == source.hash }) }) { source in
                            Button("\(source.title) · \(source.version)") { draft.overlays.append(MeaningGraphLayer(source: source)) }
                        }
                    }
                    HStack {
                        Button("Import YAML…") { importYAML() }
                        Button("Use bundled graph") {
                            perform {
                                let installed = try await MeaningGraphRuntime.shared.installedSources()
                                let source = try MeaningGraphSource.bundled()
                                sources = installed
                                draft = ProjectMeaningGraphSelection(base: source)
                            }
                        }
                        Button("Revert edits") { draft = original }
                    }
                    Text("Version \(draft.base.version) · fingerprint \(draft.effectiveHash.prefix(16))")
                        .font(.caption.monospaced()).textSelection(.enabled)
                    if let preview {
                        Divider()
                        Text("Preview").font(.headline)
                        Text(preview.counts.sorted(by: { $0.key < $1.key }).map { "\($0.value) \($0.key)" }.joined(separator: " · "))
                        ForEach(preview.changes, id: \.self) { Text($0).font(.callout) }
                        if preview.changes.isEmpty { Text("No graph records change.").font(.callout) }
                    }
                }
            }
            if !message.isEmpty { Text(message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
            HStack {
                Button("Close") { dismiss() }
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button("Preview changes") {
                    perform { preview = try await MeaningGraphRuntime.shared.preview(draft, replacing: original) }
                }
                Button("Apply to project") {
                    perform {
                        try await library.applyMeaningGraph(draft, projectId: projectId, replacing: original.effectiveHash)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(preview?.provenance.effectiveHash != draft.effectiveHash || draft == original)
            }
        }
        .padding(24).frame(width: 720, height: 560).disabled(busy)
        .task {
            do {
                sources = try await MeaningGraphRuntime.shared.installedSources()
                for source in [original.base] + original.overlays.map(\.source) where !sources.contains(where: { $0.hash == source.hash }) {
                    sources.append(source)
                }
            } catch { message = error.localizedDescription }
        }
        .onChange(of: draft) { _, _ in preview = nil; message = "" }
    }

    private func importYAML() {
        guard let url = meaningGraphImportURL() else { return }
        perform {
            let source = try await MeaningGraphRuntime.shared.importSource(url)
            if !sources.contains(where: { $0.hash == source.hash }) { sources.append(source) }
            if source.kind == "base" { draft.base = source }
            else if !draft.overlays.contains(where: { $0.source.hash == source.hash }) { draft.overlays.append(MeaningGraphLayer(source: source)) }
        }
    }

    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        busy = true; message = ""
        Task { @MainActor in
            defer { busy = false }
            do { try await action() } catch { message = error.localizedDescription }
        }
    }
}

struct MeaningGraphLibraryPanel: View {
    @State private var sources: [MeaningGraphSource] = []
    @State private var message = ""
    @State private var busy = false
    @AppStorage(MeaningGraphProjectStore.defaultKey) private var defaultHash = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Meaning graph library", systemImage: "point.3.connected.trianglepath.dotted").font(.headline)
            Text("The full graph runs locally. Install independent updates or custom YAML here; existing projects keep their pinned versions until you apply a change in Goal → Meaning graph.")
                .font(.caption).foregroundStyle(.secondary)
            Picker("Default for new projects", selection: $defaultHash) {
                Text("Bundled graph").tag("")
                ForEach(sources.filter { $0.kind == "base" }) { source in
                    Text("\(source.title) · \(source.version)").tag(source.hash)
                }
            }
            HStack {
                Button("Import YAML…") {
                    guard let url = meaningGraphImportURL() else { return }
                    perform {
                        let source = try await MeaningGraphRuntime.shared.importSource(url)
                        message = "Installed \(source.title) · \(source.version)."
                    }
                }
                Button("Download official update") {
                    perform {
                        let source = try await MeaningGraphRuntime.shared.downloadOfficialUpdate()
                        message = "Installed \(source.version). Choose it as the new-project default or preview it in a project's graph controls."
                    }
                }
                if busy { ProgressView().controlSize(.small) }
            }
            if !message.isEmpty { Text(message).font(.caption).textSelection(.enabled) }
        }
        .disabled(busy)
        .task { do { sources = try await MeaningGraphRuntime.shared.installedSources() } catch { message = error.localizedDescription } }
    }

    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        busy = true; message = ""
        Task { @MainActor in
            defer { busy = false }
            do {
                try await action()
                sources = try await MeaningGraphRuntime.shared.installedSources()
            } catch { message = error.localizedDescription }
        }
    }
}

@MainActor
private func meaningGraphImportURL() -> URL? {
    let panel = NSOpenPanel()
    panel.title = "Import a meaning graph pack or overlay"
    panel.allowedContentTypes = [UTType(filenameExtension: "yaml") ?? .plainText, UTType(filenameExtension: "yml") ?? .plainText]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    return panel.runModal() == .OK ? panel.url : nil
}
