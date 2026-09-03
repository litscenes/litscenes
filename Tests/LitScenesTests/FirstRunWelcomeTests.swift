import Foundation
import Testing
@testable import LitScenes

// MARK: - First-run eligibility decision table

@Test
func coldInstallShowsWelcome() {
    #expect(
        FirstRunWelcomeEligibility.decide(seenVersion: 0, hasAnyCredential: false, hasAnyProject: false)
            == .showWelcome
    )
}

@Test
func existingCredentialGrandfathersSilently() {
    // Keys in the environment or credentials.env mean this is not a cold
    // user — the flag latches without ever showing the journey.
    #expect(
        FirstRunWelcomeEligibility.decide(seenVersion: 0, hasAnyCredential: true, hasAnyProject: false)
            == .markSeenSilently
    )
    #expect(
        FirstRunWelcomeEligibility.decide(seenVersion: 0, hasAnyCredential: true, hasAnyProject: true)
            == .markSeenSilently
    )
}

@Test
func existingProjectGrandfathersSilently() {
    #expect(
        FirstRunWelcomeEligibility.decide(seenVersion: 0, hasAnyCredential: false, hasAnyProject: true)
            == .markSeenSilently
    )
}

@Test
func seenVersionSuppressesEverything() {
    for hasCredential in [false, true] {
        for hasProject in [false, true] {
            #expect(
                FirstRunWelcomeEligibility.decide(
                    seenVersion: FirstRunWelcomeEligibility.currentVersion,
                    hasAnyCredential: hasCredential,
                    hasAnyProject: hasProject
                ) == FirstRunWelcomeEligibility.Decision.none
            )
        }
    }
}

@Test
func futureVersionBumpReopensForColdStateOnly() {
    // A materially changed welcome bumps currentVersion; an older seen
    // version behaves exactly like unseen.
    let olderSeen = FirstRunWelcomeEligibility.currentVersion - 1
    #expect(
        FirstRunWelcomeEligibility.decide(seenVersion: olderSeen, hasAnyCredential: false, hasAnyProject: false)
            == .showWelcome
    )
    #expect(
        FirstRunWelcomeEligibility.decide(seenVersion: olderSeen, hasAnyCredential: true, hasAnyProject: false)
            == .markSeenSilently
    )
}

// MARK: - Analyze pre-flight contract

@Test @MainActor
func missingKeyAnalysisStatusPointsAtAppSettings() {
    // The keyless Analyze path must steer to App Settings, never to a raw
    // environment-variable instruction.
    #expect(LibraryEngine.missingOpenAIKeyAnalysisStatus.contains("App Settings"))
}
