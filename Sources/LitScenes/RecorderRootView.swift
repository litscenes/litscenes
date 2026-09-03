import SwiftUI

struct RecorderRootView: View {
    @ObservedObject var engine: RecorderEngine
    @State private var showingSettings = false
    @State private var showingNewProject = false
    @State private var showingProjectLibrary = false
    @State private var showingStopDialog = false
    @State private var showingNewProjectWorkDialog = false
    @State private var openNewProjectAfterStop = false
    @State private var checkedInitialSettings = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    permissionNotice
                    statusBand
                    latestHydration
                    captureStream
                }
                .padding(14)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            guard !checkedInitialSettings else { return }
            checkedInitialSettings = true
            engine.reloadProjects()
            showingSettings = OpenAIKeyStore.currentSource() == .missing
        }
        .onChange(of: engine.isStopping) { _, isStopping in
            if !isStopping, openNewProjectAfterStop, !engine.hasPendingWork {
                openNewProjectAfterStop = false
                showingNewProject = true
            }
        }
        .sheet(isPresented: $showingSettings) {
            RecorderSettingsView(engine: engine)
                .frame(width: 460)
        }
        .sheet(isPresented: $showingNewProject) {
            NewProjectView { name in
                if engine.createProject(named: name) {
                    showingNewProject = false
                    startRecording()
                }
            }
            .frame(width: 420)
        }
        .sheet(isPresented: $showingProjectLibrary) {
            ProjectLibraryView(engine: engine) {
                showingProjectLibrary = false
                requestNewProject()
            }
            .frame(width: 460, height: 520)
        }
        .confirmationDialog("Stop recording?", isPresented: $showingStopDialog) {
            Button("Finish Queued Analysis") {
                engine.finishQueuedAndStop()
            }
            Button("Stop Now", role: .destructive) {
                engine.stopNow()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Finish queued analysis to preserve pending context, or stop now to discard buffered and queued captures.")
        }
        .confirmationDialog("Start a new project?", isPresented: $showingNewProjectWorkDialog) {
            Button("Finish Queued Analysis") {
                openNewProjectAfterStop = true
                engine.finishQueuedAndStop()
            }
            Button("Discard Queued Work", role: .destructive) {
                engine.stopNow()
                showingNewProject = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The current session still has buffered, queued, or active analysis work.")
        }
        .alert("Recorder Error", isPresented: Binding(
            get: { !engine.lastError.isEmpty },
            set: { if !$0 { engine.clearError() } }
        )) {
            Button("OK") { engine.clearError() }
        } message: {
            Text(engine.lastError)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(engine.isStarting ? Color.yellow : (engine.isRecording ? (engine.isPaused ? Color.yellow : Color.red) : Color.gray))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text("Screen Graph Recorder")
                    .font(.headline)
                Text(engine.currentProject?.name ?? "No Project")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(engine.statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                showingProjectLibrary = true
            } label: {
                Image(systemName: "folder")
            }
            .help("Projects")

            Button {
                requestNewProject()
            } label: {
                Image(systemName: "plus.rectangle.on.folder")
            }
            .help("New Project")

            Button {
                startRecording()
            } label: {
                Label("Start", systemImage: "record.circle")
            }
            .disabled(engine.isRecording || engine.isStarting || engine.isStopping || engine.isPaused)

            Button {
                engine.isPaused ? engine.resume() : engine.pause()
            } label: {
                Label(engine.isPaused ? "Resume" : "Pause", systemImage: engine.isPaused ? "play.fill" : "pause.fill")
            }
            .disabled(!engine.isRecording)

            Button {
                engine.eraseLastBufferWindow()
            } label: {
                Image(systemName: "delete.backward")
            }
            .disabled(!engine.isRecording)
            .help("Erase Last \(Int(engine.config.bufferDelaySeconds))s")

            Button {
                showingStopDialog = true
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .disabled(!engine.hasPendingWork || engine.isStarting)

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Settings")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func startRecording() {
        guard OpenAIKeyStore.currentSource() != .missing else {
            showingSettings = true
            return
        }
        guard engine.currentProject != nil else {
            showingNewProject = true
            return
        }
        engine.start()
    }

    private func requestNewProject() {
        if engine.hasPendingWork {
            showingNewProjectWorkDialog = true
        } else {
            showingNewProject = true
        }
    }

    private var permissionNotice: some View {
        Group {
            if !engine.screenPermissionNotice.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lock.rectangle.on.rectangle")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Screen Recording Permission")
                                .font(.subheadline.weight(.semibold))
                            Text(engine.screenPermissionNotice)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    HStack {
                        Button {
                            engine.openScreenRecordingSettings()
                        } label: {
                            Label("Open Settings", systemImage: "gearshape")
                        }

                        Button {
                            engine.quitApp()
                        } label: {
                            Label("Quit LitScenes", systemImage: "power")
                        }

                        Spacer()

                        Button {
                            engine.clearScreenPermissionNotice()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .help("Dismiss")
                    }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var statusBand: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                metric("Captured", "\(engine.totals.captured)")
                metric("Skipped", "\(engine.totals.skipped)")
                metric("Hydrated", "\(engine.totals.hydrated)")
            }
            HStack {
                metric("Queued", "\(engine.totals.queued)")
                metric("Actual", engine.totals.actualCostUsd.dollars)
                metric("Est.", engine.totals.estimatedCostUsd.dollars)
            }
            if !engine.sessionDirectory.isEmpty {
                Text(engine.sessionDirectory)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.callout, design: .monospaced).weight(.semibold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
    }

    private var latestHydration: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Hydration Stream", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.subheadline.weight(.semibold))
            if engine.analyses.isEmpty {
                Text("Newest OpenAI hydration output will appear here after the buffer and diff check.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                ForEach(engine.analyses.prefix(10)) { envelope in
                    HydrationCard(envelope: envelope)
                }
            }
        }
    }

    private var captureStream: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Capture States", systemImage: "list.bullet.rectangle")
                .font(.subheadline.weight(.semibold))
            ForEach(engine.captures.prefix(16)) { capture in
                CaptureRow(capture: capture)
            }
        }
    }
}

struct NewProjectView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    let onCreate: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("New Project")
                    .font(CanonType.editorial(22, weight: .semibold))
                    .foregroundStyle(CanonColor.ink)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(CanonUtilityButtonStyle())
                .help("Cancel")
            }
            .padding(16)

            Rectangle()
                .fill(CanonColor.hairlinePaper)
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 12) {
                TextField("Project name", text: $name)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Spacer()
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(CanonSecondaryButtonStyle())
                    Button {
                        onCreate(name)
                    } label: {
                        Label("Create", systemImage: "plus")
                    }
                    .buttonStyle(CanonPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(16)
        }
        .background(CanonColor.paper)
        .foregroundStyle(CanonColor.ink)
    }
}

struct ProjectLibraryView: View {
    @ObservedObject var engine: RecorderEngine
    @Environment(\.dismiss) private var dismiss
    let onNewProject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Projects")
                    .font(.headline)
                Spacer()
                Button {
                    onNewProject()
                } label: {
                    Label("New", systemImage: "plus")
                }
                Button("Done") {
                    dismiss()
                }
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if engine.projects.isEmpty {
                        Text("No projects yet.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    } else {
                        ForEach(engine.projects) { project in
                            ProjectLibraryRow(
                                project: project,
                                isCurrent: project.projectId == engine.currentProject?.projectId,
                                canOpen: engine.canSwitchProject
                            ) {
                                engine.selectProject(project)
                                dismiss()
                            }
                        }
                    }
                }
                .padding(12)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            engine.reloadProjects()
        }
    }
}

struct ProjectLibraryRow: View {
    let project: ProjectRecord
    let isCurrent: Bool
    let canOpen: Bool
    let onOpen: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: isCurrent ? "folder.fill" : "folder")
                .foregroundStyle(isCurrent ? .blue : .secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(project.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text("\(project.sessionCount) \(project.sessionCount == 1 ? "session" : "sessions") - \(project.updatedAt)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(isCurrent ? "Current" : "Open") {
                onOpen()
            }
            .disabled(isCurrent || !canOpen)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct RecorderSettingsView: View {
    @ObservedObject var engine: RecorderEngine
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = ""
    @State private var keySource = OpenAIKeySource.missing
    @State private var hasSavedKey = false
    @State private var keyMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                apiKeySection
                captureSection
            }
            .padding(16)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            refreshKeyState()
        }
    }

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("OpenAI API Key", systemImage: "key.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(keySource.rawValue)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(keySource == .missing ? .red : .secondary)
            }

            SecureField(hasSavedKey ? "Saved locally" : "sk-...", text: $apiKey)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button {
                    saveAPIKey()
                } label: {
                    Label("Save", systemImage: "checkmark.circle")
                }
                .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button(role: .destructive) {
                    deleteAPIKey()
                } label: {
                    Label("Remove", systemImage: "trash")
                }
                .disabled(!hasSavedKey)

                Spacer()
            }

            if !keyMessage.isEmpty {
                Text(keyMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private var captureSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Capture", systemImage: "display")
                .font(.subheadline.weight(.semibold))

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("Buffer")
                        .foregroundStyle(.secondary)
                    Picker("", selection: Binding(
                        get: { engine.config.bufferDelaySeconds },
                        set: { engine.config.bufferDelaySeconds = $0 }
                    )) {
                        Text("5s").tag(5.0)
                        Text("10s").tag(10.0)
                        Text("60s").tag(60.0)
                    }
                    .pickerStyle(.segmented)
                }

                GridRow {
                    Text("Model")
                        .foregroundStyle(.secondary)
                    TextField("Model", text: Binding(
                        get: { engine.config.model },
                        set: { engine.config.model = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }

                GridRow {
                    Text("Detail")
                        .foregroundStyle(.secondary)
                    Picker("", selection: Binding(
                        get: { engine.config.detail },
                        set: { engine.config.detail = $0 }
                    )) {
                        ForEach(ImageDetail.allCases) { detail in
                            Text(detail.rawValue).tag(detail)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                GridRow {
                    Text("Privacy")
                        .foregroundStyle(.secondary)
                    Toggle("Exclude recorder UI from capture", isOn: Binding(
                        get: { engine.config.excludeOwnWindows },
                        set: { engine.config.excludeOwnWindows = $0 }
                    ))
                }
            }
            .font(.caption)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func refreshKeyState() {
        apiKey = ""
        hasSavedKey = OpenAIKeyStore.hasSavedAPIKey()
        keySource = OpenAIKeyStore.currentSource()
    }

    private func saveAPIKey() {
        do {
            try OpenAIKeyStore.saveAPIKey(apiKey)
            refreshKeyState()
            keyMessage = "Saved locally at \(OpenAIKeyStore.savedKeyURL.path)."
        } catch {
            keyMessage = error.localizedDescription
        }
    }

    private func deleteAPIKey() {
        do {
            try OpenAIKeyStore.deleteAPIKey()
            refreshKeyState()
            keyMessage = keySource == .environment ? "Using environment key." : "Removed."
        } catch {
            keyMessage = error.localizedDescription
        }
    }
}

struct HydrationCard: View {
    let envelope: AnalysisEnvelope
    @State private var showJSON = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(envelope.payload.operatorSummary.isEmpty ? "No summary" : envelope.payload.operatorSummary)
                    .font(.callout.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Text(envelope.usage.actualCostUsd.dollars)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if !envelope.payload.subject.oneLineIdentity.isEmpty || !envelope.payload.subject.canonicalName.isEmpty {
                Text(envelope.payload.subject.canonicalName.isEmpty ? envelope.payload.subject.oneLineIdentity : envelope.payload.subject.canonicalName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            tokenWrap(title: "Surfaces", values: envelope.payload.surfaces.map { $0.appOrSite.isEmpty ? $0.kind.rawValue : $0.appOrSite })
            tokenWrap(title: "Claims", values: envelope.payload.claims.prefix(4).map(\.claim))
            if !envelope.payload.privacyWarnings.isEmpty {
                tokenWrap(title: "Privacy", values: envelope.payload.privacyWarnings)
            }
            DisclosureGroup("Raw JSON", isExpanded: $showJSON) {
                Text(rawJSON)
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.top, 4)
            }
            .font(.caption)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func tokenWrap<T: Sequence>(title: String, values: T) -> some View where T.Element == String {
        let cleaned = values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return Group {
            if !cleaned.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    FlowLayout(items: cleaned)
                }
            }
        }
    }

    private var rawJSON: String {
        guard let data = try? JSONCoding.prettyEncoder.encode(envelope.payload) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

struct CaptureRow: View {
    let capture: CaptureRecord

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(capture.status.rawValue)
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text(capture.estimatedCostUsd.dollars)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(capture.message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 7))
    }

    private var icon: String {
        switch capture.status {
        case .buffered: "hourglass"
        case .diffCheck: "waveform.path.ecg"
        case .skipped: "forward.end"
        case .queued: "tray"
        case .analyzing: "sparkles"
        case .hydrated: "checkmark.circle.fill"
        case .erased: "trash"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch capture.status {
        case .hydrated: .green
        case .failed: .red
        case .erased: .orange
        case .skipped: .secondary
        case .analyzing: .blue
        default: .primary
        }
    }
}

struct FlowLayout: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(items.prefix(6), id: \.self) { item in
                Text(item)
                    .font(.caption2)
                    .lineLimit(3)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.background, in: Capsule())
            }
        }
    }
}
