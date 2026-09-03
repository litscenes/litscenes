import AppKit
import Foundation
@preconcurrency import ScreenCaptureKit

struct CapturedFrame {
    var image: CGImage
    var displayId: CGDirectDisplayID
    var capturedAt: Date
}

@MainActor
final class ScreenCaptureService {
    func captureFullDisplay(excludingOwnWindows: Bool = true) async throws -> CapturedFrame {
        let content = try await SCShareableContent.current
        guard let display = selectDisplay(from: content) else {
            throw ScreenGraphError.capture("No capturable display was found.")
        }

        let filter: SCContentFilter
        if excludingOwnWindows {
            let ownApplications = content.applications.filter { $0.processID == getpid() }
            filter = SCContentFilter(display: display, excludingApplications: ownApplications, exceptingWindows: [])
        } else {
            filter = SCContentFilter(display: display, excludingWindows: [])
        }
        filter.includeMenuBar = true

        let configuration = SCStreamConfiguration()
        configuration.width = max(display.width, 1)
        configuration.height = max(display.height, 1)
        configuration.showsCursor = false
        configuration.queueDepth = 3
        configuration.captureResolution = .best

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        return CapturedFrame(image: image, displayId: display.displayID, capturedAt: Date())
    }

    private func selectDisplay(from content: SCShareableContent) -> SCDisplay? {
        let mainDisplayId = CGMainDisplayID()
        return content.displays.first { $0.displayID == mainDisplayId } ?? content.displays.first
    }
}
