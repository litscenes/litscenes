import Foundation
import Testing
@testable import LitScenes

@Suite struct ReleaseIdentityAdoptionTests {
    @Test func releaseLanesUsePermanentDistinctDataRoots() {
        let development = LitScenesReleaseIdentity.resolve(channelValue: "development")
        let community = LitScenesReleaseIdentity.resolve(channelValue: "community-release")
        let official = LitScenesReleaseIdentity.resolve(
            channelValue: "official-commercial-release",
            bundleIdentifier: "ai.litscenes.official"
        )

        #expect(development.applicationSupportDirectoryName == "LitScenes")
        #expect(community.applicationSupportDirectoryName == "LitScenes Community")
        #expect(official.applicationSupportDirectoryName == "LitScenes Official")
        #expect(Set([
            development.preferenceSuiteName,
            community.preferenceSuiteName,
            official.preferenceSuiteName,
        ]).count == 3)
    }

    @Test func proInterestPromotionShowsEverywhereButTheCommercialBuild() {
        let development = LitScenesReleaseIdentity.resolve(channelValue: "development")
        let community = LitScenesReleaseIdentity.resolve(channelValue: "community-release")
        let official = LitScenesReleaseIdentity.resolve(
            channelValue: "official-commercial-release",
            bundleIdentifier: "ai.litscenes.official"
        )

        #expect(development.showsProInterestPromotion)
        #expect(community.showsProInterestPromotion)
        #expect(!official.showsProInterestPromotion)
        #expect(LitScenesReleaseIdentity.proInterestURL.absoluteString == "https://litscenes.ai/#join")
    }

    @Test func developmentMigratesBothLegacyPreferenceDomainsOnce() throws {
        let destinationName = "litscenes.tests.adoption-destination-\(UUID().uuidString)"
        let destination = try #require(UserDefaults(suiteName: destinationName))
        defer { destination.removePersistentDomain(forName: destinationName) }

        let processDomain: [String: Any] = [
            "litscenes.session_recording.capture_scope": "screen",
            "LITSCENES_LAST_WORKSPACE_TAB": "story",
            "LITSCENES_SHOT_LOOK_PROVIDER": "fal",
        ]
        let bundleDomain: [String: Any] = [
            "litscenes.session_recording.capture_scope": "window",
            "litscenes.capture.preferred_audio_input_id": "legacy-mic",
            "shot_player_loop_enabled": true,
        ]
        destination.set("destination-mic", forKey: "litscenes.capture.preferred_audio_input_id")

        #expect(LitScenesLegacyPreferenceMigration.migrateIfNeeded(
            channel: .development,
            from: [processDomain, bundleDomain],
            into: destination
        ))
        #expect(destination.string(forKey: "litscenes.session_recording.capture_scope") == "screen")
        #expect(destination.string(forKey: "litscenes.capture.preferred_audio_input_id") == "destination-mic")
        #expect(destination.string(forKey: "LITSCENES_LAST_WORKSPACE_TAB") == "story")
        #expect(destination.string(forKey: "LITSCENES_SHOT_LOOK_PROVIDER") == "fal")
        #expect(destination.bool(forKey: "shot_player_loop_enabled"))
        #expect(destination.integer(forKey: LitScenesLegacyPreferenceMigration.migrationVersionKey) == 1)

        destination.removeObject(forKey: "LITSCENES_LAST_WORKSPACE_TAB")
        #expect(!LitScenesLegacyPreferenceMigration.migrateIfNeeded(
            channel: .development,
            from: [["LITSCENES_LAST_WORKSPACE_TAB": "media"]],
            into: destination
        ))
        #expect(destination.object(forKey: "LITSCENES_LAST_WORKSPACE_TAB") == nil)
    }

    @Test func isolatedReleaseLanesNeverMigrateLegacyPreferences() throws {
        for channel in [LitScenesReleaseChannel.community, .officialCommercial] {
            let destinationName = "litscenes.tests.isolated-destination-\(UUID().uuidString)"
            let destination = try #require(UserDefaults(suiteName: destinationName))
            defer { destination.removePersistentDomain(forName: destinationName) }

            #expect(!LitScenesLegacyPreferenceMigration.migrateIfNeeded(
                channel: channel,
                from: [["shot_player_loop_enabled": true]],
                into: destination
            ))
            #expect(destination.object(forKey: "shot_player_loop_enabled") == nil)
            #expect(destination.object(
                forKey: LitScenesLegacyPreferenceMigration.migrationVersionKey
            ) == nil)
        }
    }

    @Test func migrationCoversEveryLaneScopedAppStorageKey() {
        #expect(LitScenesLegacyPreferenceMigration.adoptedPreferenceKeys.contains(
            "LITSCENES_LAST_WORKSPACE_TAB"
        ))
        #expect(LitScenesLegacyPreferenceMigration.adoptedPreferenceKeys.contains(
            "LITSCENES_SHOT_LOOK_PROVIDER"
        ))
        #expect(LitScenesLegacyPreferenceMigration.adoptedPreferenceKeys.contains(
            "litscenes.welcome.seen_version"
        ))
        #expect(LitScenesLegacyPreferenceMigration.adoptedPreferenceKeys.count == 11)
    }
}
