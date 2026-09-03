import Foundation

enum LitScenesReleaseChannel: String, Codable, CaseIterable, Sendable {
    case development
    case community = "community-release"
    case officialCommercial = "official-commercial-release"
}

struct LitScenesReleaseIdentity: Equatable, Sendable {
    static let publicRepositoryURL = URL(string: "https://github.com/litscenes/litscenes")!
    static let catalogTermsURL = URL(string: "https://litscenes.ai/catalog-terms/")!
    /// The public signup for LitScenes Pro (the hosted story service). The app
    /// only links here — it never collects or transmits an address itself.
    static let proInterestURL = URL(string: "https://litscenes.ai/#join")!

    var channel: LitScenesReleaseChannel
    var displayName: String
    var bundleIdentifier: String
    var applicationSupportDirectoryName: String
    var preferenceSuiteName: String
    var licenseLabel: String
    var correspondingSourceURL: URL?
    var sourceRevision: String?

    var usesOfficialBranding: Bool { channel == .officialCommercial }
    /// The "Pro — coming soon" interest card shows in Development and
    /// Community builds; the commercial build is the product it announces.
    var showsProInterestPromotion: Bool { channel != .officialCommercial }

    static let current: LitScenesReleaseIdentity = resolve(
        channelValue: Bundle.main.object(forInfoDictionaryKey: "LitScenesReleaseChannel") as? String
            ?? ProcessInfo.processInfo.environment["LITSCENES_RELEASE_CHANNEL"],
        bundleIdentifier: Bundle.main.bundleIdentifier,
        sourceURLString: Bundle.main.object(forInfoDictionaryKey: "LitScenesCorrespondingSourceURL") as? String,
        sourceRevision: Bundle.main.object(forInfoDictionaryKey: "LitScenesSourceRevision") as? String
    )

    static func resolve(
        channelValue: String?,
        bundleIdentifier: String? = nil,
        sourceURLString: String? = nil,
        sourceRevision: String? = nil
    ) -> LitScenesReleaseIdentity {
        let channel = channelValue.flatMap(LitScenesReleaseChannel.init(rawValue:)) ?? .development
        let revision = sourceRevision?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        switch channel {
        case .development:
            return LitScenesReleaseIdentity(
                channel: channel,
                displayName: "LitScenes Development",
                bundleIdentifier: "ai.litscenes.development",
                // Development is the continuation of the pre-release app. Its
                // registry contains absolute paths beneath this legacy root,
                // so moving the directory would orphan otherwise valid work.
                applicationSupportDirectoryName: "LitScenes",
                preferenceSuiteName: "ai.litscenes.development",
                licenseLabel: "Unreleased development build",
                correspondingSourceURL: nil,
                sourceRevision: revision
            )
        case .community:
            let exactURL = sourceURLString.flatMap(URL.init(string:))
            return LitScenesReleaseIdentity(
                channel: channel,
                displayName: "LitScenes Community",
                bundleIdentifier: "ai.litscenes.community",
                applicationSupportDirectoryName: "LitScenes Community",
                preferenceSuiteName: "ai.litscenes.community",
                licenseLabel: "AGPL-3.0-only",
                correspondingSourceURL: exactURL,
                sourceRevision: revision
            )
        case .officialCommercial:
            let resolvedBundleIdentifier = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? "ai.litscenes.official.invalid"
            return LitScenesReleaseIdentity(
                channel: channel,
                displayName: "LitScenes",
                bundleIdentifier: resolvedBundleIdentifier,
                applicationSupportDirectoryName: "LitScenes Official",
                preferenceSuiteName: resolvedBundleIdentifier,
                licenseLabel: "Commercial EULA",
                correspondingSourceURL: nil,
                sourceRevision: revision
            )
        }
    }
}

/// One-time preference migration for the Development lane.
///
/// Development keeps the legacy Application Support directory in place. Only
/// the small behavioral defaults move into the new lane-scoped suite. Reading
/// persistent domains directly avoids importing global defaults accidentally.
enum LitScenesLegacyPreferenceMigration {
    static let currentVersion = 1
    static let migrationVersionKey = "litscenes.release_identity.legacy_preferences_migration_version"
    static let legacyDomainNames = ["LitScenes", "local.litscenes.LitScenes"]
    static let adoptedPreferenceKeys = [
        "litscenes.session_recording.capture_scope",
        "litscenes.session_recording.face_cam",
        "litscenes.session_recording.microphone",
        "litscenes.session_recording.system_audio",
        "litscenes.session_recording.camera_device_id",
        "litscenes.capture.preferred_audio_input_id",
        "litscenes.shot_voiceover.playback_while_recording",
        "shot_player_loop_enabled",
        "LITSCENES_LAST_WORKSPACE_TAB",
        "LITSCENES_SHOT_LOOK_PROVIDER",
        "litscenes.welcome.seen_version",
    ]

    static func persistentDomains(defaults: UserDefaults = .standard) -> [[String: Any]] {
        legacyDomainNames.compactMap { defaults.persistentDomain(forName: $0) }
    }

    @discardableResult
    static func migrateIfNeeded(
        channel: LitScenesReleaseChannel,
        from sourceDomains: [[String: Any]],
        into destination: UserDefaults
    ) -> Bool {
        guard channel == .development,
              destination.integer(forKey: migrationVersionKey) < currentVersion else { return false }
        for key in adoptedPreferenceKeys where destination.object(forKey: key) == nil {
            if let value = sourceDomains.lazy.compactMap({ $0[key] }).first {
                destination.set(value, forKey: key)
            }
        }
        destination.set(currentVersion, forKey: migrationVersionKey)
        return true
    }
}

enum LitScenesPreferences {
    // UserDefaults is process-safe and thread-safe, but Foundation does not
    // declare it Sendable. The suite is immutable after process startup.
    nonisolated(unsafe) static let store: UserDefaults = {
        let environment = ProcessInfo.processInfo.environment
        let isTestProcess = environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || ProcessInfo.processInfo.arguments.contains { $0.hasSuffix(".xctest") }
        let suffix = isTestProcess ? ".tests.\(ProcessInfo.processInfo.processIdentifier)" : ""
        let destination = UserDefaults(
            suiteName: LitScenesReleaseIdentity.current.preferenceSuiteName + suffix
        ) ?? .standard
        if !isTestProcess {
            LitScenesLegacyPreferenceMigration.migrateIfNeeded(
                channel: LitScenesReleaseIdentity.current.channel,
                from: LitScenesLegacyPreferenceMigration.persistentDomains(),
                into: destination
            )
        }
        return destination
    }()
}
