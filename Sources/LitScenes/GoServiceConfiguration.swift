import Foundation
import SwiftUI
import Synchronization

/// A synchronous snapshot for provider routing outside the main actor.
enum GoAvailability {
    private static let state = Mutex(false)

    static var membershipsEnabled: Bool { state.withLock { $0 } }

    @MainActor
    static func update(_ enabled: Bool) {
        state.withLock { $0 = enabled }
    }
}

struct AppAnnouncement: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let body: String
    let url: URL?

    init?(_ document: GoDocument) {
        let id = document.string("id").trimmingCharacters(in: .whitespacesAndNewlines)
        let title = document.string("title").trimmingCharacters(in: .whitespacesAndNewlines)
        let body = document.string("body").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, id.count <= 160, !title.isEmpty, title.count <= 200,
              !body.isEmpty, body.count <= 6000 else { return nil }
        let address = document.string("url")
        if address.isEmpty {
            url = nil
        } else {
            guard address.count <= 2048, !address.contains(where: \.isWhitespace),
                  let parsed = URL(string: address), parsed.scheme == "https",
                  let host = parsed.host, !host.isEmpty, parsed.user == nil, parsed.password == nil else { return nil }
            url = parsed
        }
        self.id = id
        self.title = title
        self.body = body
    }
}

@MainActor
final class GoServiceConfiguration: ObservableObject {
    static let shared = GoServiceConfiguration()
    @Published private(set) var announcements: [AppAnnouncement] = []
    @Published private(set) var membershipsEnabled = false
    private var lastAttempt: Date?
    private var request: Task<Void, Never>?

    private struct Availability: Decodable {
        let memberships_enabled: Bool?
    }

    func refresh(force: Bool = false) async {
        if let request {
            await request.value
            return
        }
        guard force || lastAttempt.map({ Date().timeIntervalSince($0) >= 300 }) != false else { return }
        lastAttempt = Date()
        let task = Task { await fetch() }
        request = task
        await task.value
        request = nil
    }

    private func fetch() async {
        let document: GoDocument
        do {
            let response = try await GoAPI.call("config", authenticated: false, timeout: 5)
            let availability = try? JSONDecoder().decode(Availability.self, from: response.data)
            var object = response.object
            object["memberships_enabled"] = availability?.memberships_enabled == true
            document = try GoDocument(object)
        } catch {
            document = GoDocument(data: Data("{}".utf8))
        }
        let changed = membershipsEnabled != document.bool("memberships_enabled")
        membershipsEnabled = document.bool("memberships_enabled")
        GoAvailability.update(membershipsEnabled)
        var seen = Set<String>()
        announcements = document.documents("announcements").compactMap(AppAnnouncement.init).filter { seen.insert($0.id).inserted }
        GoAccountStore.shared.applyServiceConfiguration(document)
        if changed {
            NotificationCenter.default.post(name: .goFundingChanged, object: nil)
        }
    }
}
