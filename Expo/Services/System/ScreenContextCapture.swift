import AppKit
import ScreenCaptureKit

struct ScreenSource: Identifiable, Hashable, Sendable {
    enum Kind: Sendable { case display, window }
    var id: String
    var name: String
    var kind: Kind
}

/// One still image, taken only when the user asks about their screen.
enum ScreenContextCapture {
    /// Wide enough to read small text on a whole screen.
    private static let maxWidth = 2_048.0
    private static let maxDataURLLength = 2_800_000

    static func sources() async throws -> [ScreenSource] {
        let content = try await shareable()
        let own = Bundle.main.bundleIdentifier
        let displays = content.displays.enumerated().map { index, display in
            ScreenSource(id: "screen:\(display.displayID)", name: content.displays.count > 1 ? "Screen \(index + 1)" : "Entire screen", kind: .display)
        }
        let windows = content.windows.compactMap { window -> ScreenSource? in
            guard window.windowLayer == 0, window.frame.width > 200, window.frame.height > 150,
                  let app = window.owningApplication, app.bundleIdentifier != own,
                  let title = window.title, !title.isEmpty else { return nil }
            return ScreenSource(id: "window:\(window.windowID)", name: "\(app.applicationName) — \(title)", kind: .window)
        }
        return displays + windows
    }

    static func capture(sourceID: String?) async throws -> String {
        if !CGPreflightScreenCaptureAccess() && !CGRequestScreenCaptureAccess() {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                _ = await MainActor.run { NSWorkspace.shared.open(url) }
            }
            throw BackendError("Expo needs Screen Recording access. Turn on Expo in System Settings → Privacy & Security → Screen & System Audio Recording, then reopen Expo.")
        }
        let content = try await shareable()
        let filter: SCContentFilter
        let size: CGSize
        if let sourceID, sourceID.hasPrefix("window:") {
            guard let window = content.windows.first(where: { "window:\($0.windowID)" == sourceID }) else {
                throw BackendError("That window is no longer available. Choose another source.")
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
            size = window.frame.size
        } else {
            let mainID = CGMainDisplayID()
            guard let display = content.displays.first(where: { "screen:\($0.displayID)" == sourceID })
                    ?? content.displays.first(where: { $0.displayID == mainID }) ?? content.displays.first else {
                throw BackendError("No display is available to capture.")
            }
            // Expo's own windows never become part of the question.
            let own = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
            filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
            size = CGSize(width: display.width, height: display.height)
        }
        var width = min(maxWidth, size.width * Double(filter.pointPixelScale))
        for quality in [0.75, 0.6, 0.45, 0.4] {
            let configuration = SCStreamConfiguration()
            configuration.width = max(1, Int(width))
            configuration.height = max(1, Int(width * size.height / max(1, size.width)))
            configuration.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            if let jpeg = NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: quality]) {
                let url = "data:image/jpeg;base64," + jpeg.base64EncodedString()
                if url.count <= maxDataURLLength { return url }
            }
            width *= 0.8
        }
        throw BackendError("That screen capture was too large to send. Try capturing a smaller window.")
    }

    private static func shareable() async throws -> SCShareableContent {
        do { return try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) }
        catch { throw BackendError("Allow Expo under System Settings → Privacy & Security → Screen & System Audio Recording, then try again.") }
    }
}
