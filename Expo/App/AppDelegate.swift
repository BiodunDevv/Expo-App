import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private(set) lazy var overlays = OverlayController(model: model)
    private let hotKeys = HotKeys()
    private var mainWindow: NSWindow?
    private var shortcutsActive = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.applyDockIcon()
        model.onPrivacyChange = { [weak self] in self?.overlays.setHidden($0) }
        overlays.onReplaceWindows = { [weak self] in self?.replaceMainWindow() }
        overlays.onProtectionFailure = { [weak self] in Task { await self?.model.privacyProtectionFailed() } }
        model.onPrivacyRetry = { [weak self] in self?.overlays.retryProtection() }
        // Errors show in the main window or a floating panel; otherwise macOS notifies.
        model.canShowToast = {
            NSApp.windows.contains { $0.isVisible && $0.occlusionState.contains(.visible) && ($0.styleMask.contains(.titled) || $0.frame.height > 100) && $0.level.rawValue <= NSWindow.Level.statusBar.rawValue }
        }
        model.onOverlayChange = { [weak self] in
            self?.fitMainWindow()
            self?.overlays.synchronize()
            self?.updateShortcuts()
        }
        model.showMainWindow = { [weak self] in self?.showMain() }
        model.hideMainWindow = { [weak self] in self?.mainWindow?.orderOut(nil) }
        model.showAssistantPanel = { [weak self] in self?.overlays.showAssistant() }
        showMain()
        Task {
            await model.start()
            if !compact, model.state.settings.openMaximized, let window = mainWindow, !window.isZoomed { window.zoom(nil) }
        }
    }

    private static let compactSize = NSSize(width: 720, height: 500)
    private static let fullSize = NSSize(width: 1_040, height: 720)
    /// Signing in is a small window; the workspace gets the full one.
    private var compact = Preference.bool("compactWindow", default: true)

    func showMain() {
        if mainWindow == nil {
            let window = makeMainWindow()
            let host = NSHostingView(rootView: RootView().environment(model))
            host.sizingOptions = []
            window.contentView = host
            applyLayout(to: window)
            mainWindow = window
        }
        NSApp.activate()
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    private func fitMainWindow() {
        guard model.phase == .ready, compact == model.isSignedIn else { return }
        compact = !model.isSignedIn
        Preference.set(compact, "compactWindow")
        if let window = mainWindow { applyLayout(to: window) }
    }

    private func applyLayout(to window: NSWindow) {
        // Only the workspace frame is remembered.
        window.setFrameAutosaveName("")
        if compact {
            window.styleMask.remove(.resizable)
            window.contentMinSize = Self.compactSize
            window.setContentSize(Self.compactSize)
            window.center()
        } else {
            window.styleMask.insert(.resizable)
            window.contentMinSize = NSSize(width: 860, height: 580)
            window.setContentSize(Self.fullSize)
            window.center()
            window.setFrameUsingName("ExpoWorkspaceWindow")
            window.setFrameAutosaveName("ExpoWorkspaceWindow")
        }
    }

    private func makeMainWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.compactSize),
                              styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Expo"
        window.identifier = .expoMain
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        overlays.protect(window)
        return window
    }

    /// Swaps in a window with the new capture privacy, keeping the page as it was.
    private func replaceMainWindow() {
        guard let old = mainWindow else { return }
        // A sheet belongs to the old window and cannot move with the page.
        model.presentingStart = false
        old.sheets.forEach(old.endSheet)
        old.setFrameAutosaveName("")
        guard old.isVisible else {
            old.close()
            mainWindow = nil
            return
        }
        let window = makeMainWindow()
        let content = old.contentView
        old.contentView = nil
        window.contentView = content
        window.styleMask = old.styleMask.subtracting(.fullScreen)
        window.contentMinSize = old.contentMinSize
        window.setFrame(old.frame, display: true)
        if !compact { window.setFrameAutosaveName("ExpoWorkspaceWindow") }
        window.order(.above, relativeTo: old.windowNumber)
        if old.isKeyWindow { window.makeKey() }
        old.close()
        mainWindow = window
    }

    /// ⌘↩ and ⇧⌘↩ are claimed system-wide only while Expo can act on them.
    private func updateShortcuts() {
        let wanted = model.overlaysEligible
        guard wanted != shortcutsActive else { return }
        shortcutsActive = wanted
        guard wanted else { hotKeys.unregisterAll(); return }
        hotKeys.register(keyCode: kVK_Return, modifiers: cmdKey) { [weak self] in
            guard let self else { return }
            self.overlays.showAssistant()
            self.model.layout.asked()
            Task { await self.model.assist.suggest() }
        }
        hotKeys.register(keyCode: kVK_Return, modifiers: cmdKey | shiftKey) { [weak self] in
            guard let self else { return }
            self.overlays.showAssistant()
            // Give a newly created panel time to subscribe.
            Task {
                try? await Task.sleep(for: .milliseconds(200))
                NotificationCenter.default.post(name: .expoScreenAsk, object: nil)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMain()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.phase == .ready else { return .terminateNow }
        Task {
            // Stop capture and write state; the session stays recoverable.
            await model.assist.pause()
            await model.store.flush()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
