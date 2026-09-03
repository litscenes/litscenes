import Foundation

struct ProjectLibrary {
    let root: URL

    init(root: URL = litScenesApplicationSupportDirectory().appendingPathComponent("projects", isDirectory: true)) {
        self.root = root
    }

    func listProjects() throws -> [ProjectRecord] {
        try LitScenesDesktopDatabase.listCurrentProjects(projectLibrary: self)
    }

    func createProject(named name: String) throws -> ProjectRecord {
        let cleaned = cleanedProjectName(name)
        let now = DateFormats.now()
        let project = ProjectRecord(
            projectId: Self.projectId(for: cleaned),
            name: cleaned,
            createdAt: now,
            updatedAt: now,
            sessionCount: 0,
            lastSessionId: nil
        )
        try saveProject(project)
        return project
    }

    func renameProject(_ project: ProjectRecord, to name: String) throws -> ProjectRecord {
        var updated = project
        updated.name = cleanedProjectName(name)
        updated.updatedAt = DateFormats.now()
        try saveProject(updated)
        return updated
    }

    func recordSessionStarted(project: ProjectRecord, sessionId: String) throws -> ProjectRecord {
        var updated = project
        updated.updatedAt = DateFormats.now()
        updated.lastSessionId = sessionId
        updated.sessionCount = max(project.sessionCount + 1, sessionCount(for: project))
        try saveProject(updated)
        return updated
    }

    func saveProject(_ project: ProjectRecord) throws {
        let directory = projectDirectory(for: project)
        try ensureDirectory(directory)
        _ = try LitScenesDesktopDatabase.prepareProjectDatabase(for: project, projectLibrary: self)
    }

    func projectDirectory(for project: ProjectRecord) -> URL {
        root.appendingPathComponent(project.projectId, isDirectory: true)
    }

    func sessionsDirectory(for project: ProjectRecord) -> URL {
        projectDirectory(for: project).appendingPathComponent("sessions", isDirectory: true)
    }

    func projectJSONURL(for project: ProjectRecord) -> URL {
        projectDirectory(for: project).appendingPathComponent("project.json")
    }

    static func projectId(for name: String, date: Date = Date(), uuid: UUID = UUID()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let timestamp = formatter.string(from: date)
        let slug = stableSlug(name, fallback: "project")
        let suffix = uuid.uuidString.prefix(8).lowercased()
        return "project_\(timestamp)_\(slug)_\(suffix)"
    }

    private func cleanedProjectName(_ name: String) -> String {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Untitled Project" : cleaned
    }

    private func sessionCount(for project: ProjectRecord) -> Int {
        project.sessionCount
    }
}
