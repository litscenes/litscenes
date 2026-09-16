import AVKit
import SwiftUI

/// One browser shared by render composers. Its draft is committed only by Use Recipe.
struct CivitAIModelBrowser: View {
    var kind: CivitAIMediaKind
    var requiresEnding = false
    var allowsTriggerWords = true
    var onSelect: (CivitAIRecipe, [String]) -> Void
    var onCancel: () -> Void
    @AppStorage("civitai.browser.includeMature", store: LitScenesPreferences.store) private var includeMature = true
    @State private var recipe: CivitAIRecipe
    @State private var filter = CivitAISearch()
    @State private var items: [CivitAIModelCard] = []
    @State private var selected: CivitAIModelCard?
    @State private var versionId = 0
    @State private var resource: CivitAIResource?
    @State private var previews: [CivitAIPreview] = []
    @State private var canGenerate = false
    @State private var resourceStatus = ""
    @State private var cursor: String?
    @State private var loading = false
    @State private var loadingDetail = false
    @State private var error = ""
    @State private var refresh = 0
    @State private var searchGeneration = UUID()
    @State private var serviceStatuses: [CivitAIProfile: String] = [:]
    @State private var previewSelection = 0
    @State private var triggerWords: [String] = []

    init(kind: CivitAIMediaKind, seed: CivitAIRecipe? = nil, requiresEnding: Bool = false, allowsTriggerWords: Bool = true,
         onSelect: @escaping (CivitAIRecipe, [String]) -> Void, onCancel: @escaping () -> Void) {
        self.kind = kind; self.requiresEnding = requiresEnding; self.allowsTriggerWords = allowsTriggerWords; self.onSelect = onSelect; self.onCancel = onCancel
        var initial = seed ?? CivitAIPreferences.last(kind) ?? CivitAIRecipe(profile: kind == .image ? .sdxl : .wanVideo27)
        if requiresEnding && !initial.profile.supportsEnding { initial = CivitAIRecipe(profile: .wanVideo27) }
        _recipe = State(initialValue: initial)
        var initialFilter = CivitAISearch()
        initialFilter.baseModel = initial.profile.catalogBase
        initialFilter.type = initial.profile.needsCheckpoint || initial.profile.kind == .video ? "Checkpoint" : "LORA"
        _filter = State(initialValue: initialFilter)
    }
    private var profiles: [CivitAIProfile] { CivitAIProfile.allCases.filter { $0.kind == kind } }
    private var searchIdentity: String { "\(filter)|\(includeMature)|\(recipe.profile)|\(refresh)" }
    private var shownItems: [CivitAIModelCard] {
        guard filter.generatable else { return items }
        return items.filter { card in card.versions.contains { candidateProfile($0) != nil } }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Civitai · \(kind == .image ? "Image" : "Video") models", systemImage: "square.grid.2x2")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text("My Civitai key · Buzz").foregroundStyle(.secondary)
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
            }.padding()
            Divider()
            HSplitView {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Search models", text: $filter.query).textFieldStyle(.roundedBorder)
                    HStack {
                        TextField("Creator", text: $filter.creator)
                        TextField("Tag", text: $filter.tag)
                    }.textFieldStyle(.roundedBorder)
                    HStack {
                        Picker("Type", selection: $filter.type) {
                            Text("Checkpoints").tag("Checkpoint")
                            Text("LoRAs").tag("LORA")
                        }.labelsHidden()
                        Picker("Sort", selection: $filter.sort) {
                            ForEach(["Most Downloaded", "Highest Rated", "Newest"], id: \.self) { Text($0).tag($0) }
                        }.labelsHidden()
                    }
                    TextField("Base family filter (optional)", text: $filter.baseModel).textFieldStyle(.roundedBorder)
                    HStack {
                        Toggle("Favorites", isOn: $filter.favorites)
                        Toggle("Include NSFW", isOn: $includeMature)
                    }.toggleStyle(.checkbox)
                    Toggle("Show unsupported models", isOn: Binding(get: { !filter.generatable }, set: { filter.generatable = !$0 }))
                        .toggleStyle(.checkbox)
                    Text("Generation families").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 155))], spacing: 8) {
                        ForEach(profiles, id: \.rawValue) { profile in
                            Button {
                                recipe = CivitAIRecipe(profile: profile)
                                filter.baseModel = profile.catalogBase
                                filter.type = profile.supportsLoRAs && !profile.needsCheckpoint ? "LORA" : "Checkpoint"
                            } label: {
                                Text(profile.label).frame(maxWidth: .infinity, minHeight: 34)
                            }.buttonStyle(.bordered)
                                .tint(recipe.profile == profile ? .accentColor : .gray)
                                .disabled(requiresEnding && !profile.supportsEnding)
                        }
                    }
                    if !error.isEmpty { HStack { Text(error).font(.caption); Button("Retry") { refresh += 1 } }.foregroundStyle(.orange) }
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 10)], spacing: 10) {
                            ForEach(shownItems) { item in
                                Button { selected = item; versionId = item.versions.first?.id ?? 0 } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        preview(item.previews.first, play: false).frame(height: 125).clipped()
                                        Text(item.name).font(.callout.weight(.medium)).lineLimit(2)
                                        Text(item.creator).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        Text(item.versions.first?.baseModel ?? item.type).font(.caption2).foregroundStyle(.secondary)
                                    }.padding(7).frame(maxWidth: .infinity, alignment: .leading)
                                        .background(RoundedRectangle(cornerRadius: 8).fill(selected?.id == item.id ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08)))
                                }.buttonStyle(.plain)
                            }
                        }
                        if loading { ProgressView().padding() }
                        if !loading && shownItems.isEmpty { Text("No matching models on this page. Adjust filters or load more.").foregroundStyle(.secondary).padding() }
                        if cursor != nil { Button("Load more") { Task { await search(more: true) } }.disabled(loading).padding() }
                    }
                }.padding().frame(minWidth: 420)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let selected {
                            Text(selected.name).font(.headline).textSelection(.enabled)
                            Text("By \(selected.creator)").foregroundStyle(.secondary)
                            Picker("Version", selection: $versionId) {
                                ForEach(selected.versions) { Text($0.versionName + " · " + $0.baseModel).tag($0.id) }
                            }
                            if loadingDetail { ProgressView() }
                            preview(previews.indices.contains(previewSelection) ? previews[previewSelection] : previews.first, play: true).frame(height: 180)
                            if previews.count > 1 {
                                HStack { Button("Previous preview") { previewSelection = max(0, previewSelection - 1) }; Spacer(); Button("Next preview") { previewSelection = min(previews.count - 1, previewSelection + 1) } }.font(.caption)
                            }
                            Text(selected.licenseSummary).font(.caption).foregroundStyle(.secondary)
                            Text(selected.tags.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary)
                            Text(resourceStatus).font(.caption).foregroundStyle(canGenerate ? Color.secondary : .orange)
                            if let resource {
                                Text(resource.baseModel + " · " + resource.type).font(.caption)
                                Button(resource.isLoRA ? "Add LoRA" : "Use this checkpoint") { use(resource) }
                                    .disabled(!canGenerate || candidateProfile(resource) == nil || (requiresEnding && candidateProfile(resource)?.supportsEnding != true))
                                if requiresEnding && candidateProfile(resource)?.supportsEnding != true { Text("This resource cannot constrain an ending frame. WAN 2.7 is available above.").font(.caption).foregroundStyle(.orange) }
                                if candidateProfile(resource) == nil { Text("This family or resource type is not supported by the current render adapters.").font(.caption).foregroundStyle(.orange) }
                                if !resource.trainedWords.isEmpty {
                                    Text("Trigger words: " + resource.trainedWords.joined(separator: ", ")).font(.caption).textSelection(.enabled)
                                    if allowsTriggerWords { Button("Add trigger words to prompt") { triggerWords = Array(Set(triggerWords + resource.trainedWords)).sorted() } }
                                }
                            }
                            if let url = URL(string: "https://civitai.com/models/\(selected.id)?modelVersionId=\(versionId)") { Link("Open on Civitai ↗", destination: url) }
                            Text(selected.description).font(.caption).textSelection(.enabled).lineLimit(12)
                            Divider()
                        }
                        recipeEditor
                    }.padding()
                }.frame(minWidth: 310, idealWidth: 350, maxWidth: 390)
            }
            Divider()
            HStack {
                VStack(alignment: .leading) {
                    Text(recipe.label).font(.callout.weight(.medium)).lineLimit(1)
                    Text(recipe.validationError ?? "Applies to this draft. Review the exact Civitai price before rendering.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Use Recipe") { onSelect(recipe, triggerWords) }
                    .buttonStyle(.borderedProminent).disabled(recipe.validationError != nil || !CivitAIPreferences.isConfigured || (requiresEnding && !recipe.profile.supportsEnding))
            }.padding()
        }
        .frame(width: 1000, height: 720)
        .task(id: searchIdentity) { await search(more: false) }
        .task(id: "\(selected?.id ?? 0):\(versionId):\(includeMature)") { await loadVersion() }
        .task { serviceStatuses = (try? await CivitAICatalogClient.shared.serviceStatuses(kind: kind)) ?? [:] }
        .onReceive(NotificationCenter.default.publisher(for: .civitaiCredentialsChanged)) { _ in onCancel() }
        .onChange(of: includeMature) { _, _ in selected = nil; resource = nil; previews = [] }
    }

    private var recipeEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your recipe").font(.headline)
            Text(recipe.profile.label).font(.callout)
            if let status = serviceStatuses[recipe.profile] { Text("Service: " + status).font(.caption).foregroundStyle(.secondary) }
            Toggle("Allow mature generation · Yellow Buzz", isOn: $recipe.allowMatureContent).toggleStyle(.checkbox)
            if let checkpoint = recipe.checkpoint { Text(checkpoint.name + " · " + checkpoint.versionName).font(.caption) }
            ForEach($recipe.loras) { $lora in
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text(lora.resource.name).font(.caption); Spacer(); Button("Remove") { recipe.loras.removeAll { $0.id == lora.id } }.font(.caption) }
                    HStack { Slider(value: $lora.strength, in: -2...2, step: 0.05); Text(lora.strength, format: .number.precision(.fractionLength(2))).monospacedDigit().frame(width: 40) }
                }
            }
            if recipe.profile.supportsLoRAs { Button("Browse compatible LoRAs") { filter.type = "LORA"; filter.query = ""; filter.baseModel = recipe.checkpoint?.baseModel ?? recipe.profile.catalogBase } }
            if recipe.profile.kind == .video {
                Picker("Duration", selection: $recipe.duration) { ForEach(recipe.profile.durations, id: \.self) { Text("\($0)s").tag($0) } }
            }
            if ![.wanVideo25, .wanVideo27, .wanImage27].contains(recipe.profile) {
                Stepper("Steps · \(recipe.steps)", value: $recipe.steps, in: 10...50)
                HStack { Text("Guidance"); Slider(value: $recipe.guidance, in: 1...20, step: 0.5); Text(recipe.guidance, format: .number.precision(.fractionLength(1))) }
                HStack { TextField("Width", value: $recipe.width, format: .number); Text("×"); TextField("Height", value: $recipe.height, format: .number) }.textFieldStyle(.roundedBorder)
            } else if recipe.profile.kind == .video {
                Picker("Resolution", selection: $recipe.height) { Text("720p").tag(720); Text("1080p").tag(1080) }
            }
            TextField("Seed (blank = random)", text: Binding(get: { recipe.seed.map(String.init) ?? "" }, set: { recipe.seed = Int($0) })).textFieldStyle(.roundedBorder)
            TextField("Negative prompt", text: $recipe.negativePrompt, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(2...4)
            if recipe.profile == .sd1 || recipe.profile == .sdxl {
                Text("Image change · \(recipe.strength, specifier: "%.2f")").font(.caption)
                Slider(value: $recipe.strength, in: 0...1, step: 0.01)
                Text("Used when reference images are attached.").font(.caption).foregroundStyle(.secondary)
            }
        }.font(.callout)
    }
    @ViewBuilder private func preview(_ item: CivitAIPreview?, play: Bool) -> some View {
        if let item, !item.isVideo {
            AsyncImage(url: item.url) { image in image.resizable().scaledToFit() } placeholder: { Rectangle().fill(.quaternary).overlay(Image(systemName: "photo")) }
        } else if let item, play {
            CivitAIVideoPreview(url: item.url).id(item.url)
        } else { Rectangle().fill(.quaternary).overlay(Image(systemName: item?.isVideo == true ? "play.rectangle" : "photo")) }
    }
    private func candidateProfile(_ resource: CivitAIResource) -> CivitAIProfile? {
        if !resource.air.isEmpty {
            if resource.isLoRA { return recipe.profile.accepts(resource) ? recipe.profile : nil }
            guard resource.type.lowercased() == "checkpoint" else { return nil }
            return profiles.first { $0.accepts(resource) }
        }
        let base = resource.baseModel.lowercased()
        if kind == .video { return base.contains("wan video 2.2") && base.contains("i2v") ? .wanVideo22 : nil }
        if base.contains("sdxl") || ["pony", "illustrious"].contains(base) { return .sdxl }
        if base == "sd 1.5" { return .sd1 }
        if base.contains("klein") { return base.contains("9b") ? .klein9b : .klein4b }
        return nil
    }
    private func use(_ resource: CivitAIResource) {
        guard let profile = candidateProfile(resource) else { return }
        if resource.isLoRA {
            recipe.loras.removeAll { $0.id == resource.id }
            recipe.loras.append(CivitAILoRA(resource: resource))
        } else {
            if recipe.profile != profile { recipe = CivitAIRecipe(profile: profile) }
            recipe.checkpoint = resource
            recipe.loras.removeAll { !profile.accepts($0.resource) }
        }
    }
    private func search(more: Bool) async {
        if !more { items = []; cursor = nil; searchGeneration = UUID() }
        let generation = searchGeneration
        loading = true; error = ""
        var request = filter; request.mature = includeMature
        do {
            if !more { try await Task.sleep(for: .milliseconds(350)) }
            let result = try await CivitAICatalogClient.shared.search(request, cursor: more ? cursor : nil)
            try Task.checkCancellation()
            guard generation == searchGeneration else { return }
            let known = Set(items.map(\.id))
            items = Array((items + result.items.filter { !known.contains($0.id) }).suffix(300)); cursor = result.cursor
            loading = false
        } catch is CancellationError { } catch { if generation == searchGeneration { self.error = error.localizedDescription; loading = false } }
    }
    private func loadVersion() async {
        resource = nil; previews = []; previewSelection = 0; canGenerate = false; resourceStatus = ""
        guard let chosen = selected?.versions.first(where: { $0.id == versionId }) else { return }
        loadingDetail = true
        do {
            let result = try await CivitAICatalogClient.shared.version(chosen, mature: includeMature)
            try Task.checkCancellation()
            resource = result.resource; previews = result.previews; canGenerate = result.canGenerate; resourceStatus = result.reason
            loadingDetail = false
        } catch is CancellationError { } catch { resourceStatus = error.localizedDescription; loadingDetail = false }
    }
}

private struct CivitAIVideoPreview: View {
    var url: URL
    @State private var player: AVPlayer?
    var body: some View {
        VideoPlayer(player: player)
            .onAppear { let value = AVPlayer(url: url); value.isMuted = true; player = value }
            .onDisappear { player?.pause(); player = nil }
    }
}

struct CivitAIBrowserButton: View {
    var kind: CivitAIMediaKind
    var seed: CivitAIRecipe? = nil
    var requiresEnding = false
    var allowsTriggerWords = true
    var onSelect: (CivitAIRecipe, [String]) -> Void
    @State private var presented = false
    @State private var revision = 0
    var body: some View {
        let _ = revision
        Group {
        if CivitAIPreferences.isConfigured {
            Button("Browse Civitai…") { presented = true }
                .sheet(isPresented: $presented) {
                    CivitAIModelBrowser(kind: kind, seed: seed, requiresEnding: requiresEnding, allowsTriggerWords: allowsTriggerWords, onSelect: { recipe, words in
                        onSelect(recipe, words); presented = false
                    }, onCancel: { presented = false })
                }
        }
        }.onReceive(NotificationCenter.default.publisher(for: .civitaiCredentialsChanged)) { _ in
            revision += 1; presented = false
        }
    }
}

extension Notification.Name {
    static let civitaiCredentialsChanged = Notification.Name("LitScenesCivitaiCredentialsChanged")
}
