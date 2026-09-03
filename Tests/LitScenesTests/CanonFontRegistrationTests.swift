import AppKit
import Testing
@testable import LitScenes

// The bundled display faces (Fraunces statics, SIL OFL 1.1) must ship in the
// resource bundle and resolve by their PostScript names after registration —
// CanonType.display* falls back to the system serif when this fails, but the
// bundle itself going missing is a packaging regression this test pins.
@Test func bundledDisplayFacesRegisterAndResolve() {
    #expect(CanonFontRegistration.registerBundledFonts())
    #expect(CanonFontRegistration.displayFaceAvailable)
    #expect(NSFont(name: CanonFontRegistration.displayRegularName, size: 12) != nil)
    #expect(NSFont(name: CanonFontRegistration.displaySemiBoldName, size: 12) != nil)
    #expect(NSFont(name: CanonFontRegistration.displayItalicName, size: 12) != nil)
}
