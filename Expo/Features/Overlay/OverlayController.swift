import AppKit
import SwiftUI

private final class OverlayPanel: NSPanel {
    var acceptsKeyboard = false
    override var canBecomeKey: Bool { acceptsKeyboard }
    override var canBecomeMain: Bool { false }
}

/// Floating controls respond to the first click while another app is active.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Owns the launcher, Assist dock, and assistant response windows, and applies
/// screen-capture privacy to every Expo window.
@MainActor
final class OverlayController {
    enum Part { case launcher, dock, assistant }

    private unowned let model: AppModel
    private var launcher: OverlayPanel?
    private var dock: OverlayPanel?
    private var assistant: OverlayPanel?
    private var idleDockOpen = false
    private var hidden = true
    var onReplaceWindows: () -> Void = {}
    var onProtectionFailure: () -> Void = {}
    private var failedChecks = 0
    private var watchdog: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    private static let launcherSize = NSSize(width: 64, height: 64)
    /// The bar and the conversation under it share one width.
    private static let wideWidth: CGFloat = 700
    private static let narrowWidth: CGFloat = 480
    /// The bar draws its card this far inside its window.
    private static let barInset: CGFloat = 6
    private static let glanceHeight: CGFloat = 340
    private static let minimumHeight: CGFloat = 300
    private static let idleDockSize = NSSize(width: 360, height: 262)
    private static let signedOutDockSize = NSSize(width: 340, height: 160)
    private static let miniDockSize = NSSize(width: 236, height: 68)
    private static let shortHeight: CGFloat = 430
    private var barWidth: CGFloat { model.panelCompact ? Self.narrowWidth : Self.wideWidth }
    private var activeDockSize: NSSize { NSSize(width: barWidth, height: Self.barHeight) }
    private var heightKey: String { "assistantPanelHeight.\(model.state.account?.id ?? "none")" }
    private var wasActive = false
    private static let barHeight: CGFloat = 68

    init(model: AppModel) {
        self.model = model
        startWatchdog()
        observe(NSApplication.didChangeScreenParametersNotification) { controller, _ in controller.clampAll() }
        // Sheets, popovers and dialogs are new windows: protect them as they appear.
        observe(NSApplication.didUpdateNotification) { controller, _ in NSApp.windows.forEach(controller.protect) }
        observe(NSWindow.didEndLiveResizeNotification) { controller, window in
            guard window === controller.assistant, let height = window?.frame.height else { return }
            if !controller.model.glanceMode && !controller.model.panelCompact {
                UserDefaults.standard.set(Double(height), forKey: controller.heightKey)
            }
            controller.layoutStack()
        }
    }

    private func observe(_ name: Notification.Name, _ action: @escaping @MainActor (OverlayController, NSWindow?) -> Void) {
        observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
            nonisolated(unsafe) let object = note.object
            MainActor.assumeIsolated {
                if let self { action(self, object as? NSWindow) }
            }
        })
    }

    /// The conversation's height: the person's choice for the usual size.
    private var panelHeight: CGFloat {
        if model.glanceMode { return Self.glanceHeight }
        if model.panelCompact { return Self.shortHeight }
        let saved = UserDefaults.standard.double(forKey: heightKey)
        return saved >= Self.minimumHeight ? saved : 600
    }

    /// Reads back from the window server, which is what capture tools see. True
    /// when Expo is meant to be visible, or every visible window is excluded.
    func isProtectionConfirmed() -> Bool {
        guard hidden else { return true }
        return NSApp.windows
            .filter { $0.isVisible && $0.windowNumber > 0 && ($0 is OverlayPanel || $0.identifier == .expoMain) }
            .allSatisfy { window in
                let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(window.windowNumber)) as? [[String: Any]]
                guard let state = info?.first?[kCGWindowSharingState as String] as? Int else { return true }
                return state == 0
            }
    }

    /// One failed check rebuilds the windows; a second one in a row is reported.
    func checkProtection() {
        if isProtectionConfirmed() { failedChecks = 0; return }
        failedChecks += 1
        if failedChecks == 1 { replaceWindows() }
        else if failedChecks == 2 { onProtectionFailure() }
    }

    func retryProtection() {
        failedChecks = 0
        replaceWindows()
    }

    private func startWatchdog() {
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                self.checkProtection()
            }
        }
    }

    func setHidden(_ hidden: Bool) {
        guard hidden != self.hidden else { return }
        self.hidden = hidden
        // Deferred so a window is never replaced while it is handling the click.
        DispatchQueue.main.async { [weak self] in self?.replaceWindows() }
    }

    /// Hides a window from capture. This is deliberately one-way: macOS does not
    /// reliably re-apply `.none` to a window whose sharing was switched back, so
    /// changing privacy replaces windows (see `replaceWindows`).
    func protect(_ window: NSWindow) {
        if hidden { window.sharingType = .none }
    }

    /// Recreates Expo's windows with the current privacy, carrying their content over.
    private func replaceWindows() {
        launcher = launcher.map(replacement)
        dock = dock.map(replacement)
        assistant = assistant.map(replacement)
        onReplaceWindows()
    }

    private func replacement(for old: OverlayPanel) -> OverlayPanel {
        let panel = blankPanel(frame: old.frame, style: old.styleMask, keyboard: old.acceptsKeyboard)
        panel.minSize = old.minSize
        panel.isMovableByWindowBackground = old.isMovableByWindowBackground
        let content = old.contentView
        old.contentView = nil
        panel.contentView = content
        panel.setFrame(old.frame, display: true)
        if old.isVisible {
            panel.orderFrontRegardless()
            if old.isKeyWindow { panel.makeKey() }
        }
        old.close()
        return panel
    }

    /// Reconciles the visible windows with sign-in and session state. The launcher
    /// is available before sign-in so screen-share privacy is always in reach.
    func synchronize() {
        guard model.phase == .ready, model.privacyFailure == nil else {
            [launcher, dock, assistant].forEach { $0?.orderOut(nil) }
            idleDockOpen = false
            return
        }
        let active = model.overlaysEligible && model.assist.isActive
        guard active || model.showsFloatingButton else {
            [launcher, dock, assistant].forEach { $0?.orderOut(nil) }
            idleDockOpen = false
            return
        }
        // The floating bot steps aside whenever one of Expo's panels is open.
        showLauncher(visible: !active && !idleDockOpen)
        defer { wasActive = active }
        if active {
            showDock(model.dockMinimized ? Self.miniDockSize : activeDockSize)
            // The conversation opens with the session, under the bar.
            if !wasActive && !model.dockMinimized { showAssistant() }
        } else {
            assistant?.orderOut(nil)
            if idleDockOpen { showDock(model.overlaysEligible ? Self.idleDockSize : Self.signedOutDockSize) } else { dock?.orderOut(nil) }
        }
    }

    /// Turns the floating bot off, saying where to find it again.
    func hideFloatingBot() {
        idleDockOpen = false
        model.showsFloatingButton = false
        model.notify("The floating bot is off. Turn it on from the Expo icon in the menu bar, or in Settings.")
    }

    func closeDock() {
        idleDockOpen = false
        synchronize()
    }

    /// Folds the Assist bar into a small pill, or opens it again.
    func setDockMinimized(_ minimized: Bool) {
        if minimized { hideAssistant() }
        model.dockMinimized = minimized
        synchronize()
        if !minimized { showAssistant() }
    }

    func toggleDock() {
        if model.overlaysEligible && model.assist.isActive { toggleAssistant(); return }
        idleDockOpen.toggle()
        synchronize()
    }

    func toggleAssistant() {
        if assistant?.isVisible == true { hideAssistant() } else { showAssistant() }
    }

    func showAssistant() {
        guard model.privacyFailure == nil else { model.showMainWindow(); return }
        guard model.overlaysEligible else { model.showMainWindow(); return }
        guard model.assist.isActive else {
            idleDockOpen = true
            synchronize()
            return
        }
        if model.dockMinimized { model.dockMinimized = false }
        showDock(activeDockSize)
        let panel = assistant ?? makePanel(size: NSSize(width: barWidth - Self.barInset * 2, height: panelHeight),
                                           keyboard: true, resizable: true) {
            AssistantPanelView(overlays: self)
        }
        assistant = panel
        layoutStack(showing: true)
        panel.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .expoFocusAsk, object: nil)
    }

    /// Puts the conversation directly under the bar, at the same width. When
    /// there is no room below, the bar moves up to make some.
    private func layoutStack(showing: Bool = false) {
        guard let dock, let panel = assistant, showing || panel.isVisible,
              let screen = screen(of: dock) else { return }
        let area = usable(screen)
        let width = barWidth - Self.barInset * 2
        let height = min(panelHeight, area.height - dock.frame.height - 4)
        var bar = dock.frame
        bar.size.width = barWidth
        bar.origin.x = min(max(bar.minX, area.minX), area.maxX - bar.width)
        // The panel's top edge sits just under the bar's card.
        bar.origin.y = min(max(bar.minY, area.minY + height - Self.barInset + 2), area.maxY - bar.height)
        if bar != dock.frame { dock.setFrame(bar, display: true) }
        // Only the height can be dragged; the width follows the bar.
        panel.minSize = NSSize(width: width, height: min(Self.minimumHeight, height))
        panel.maxSize = NSSize(width: width, height: area.height - bar.height - 4)
        panel.setFrame(NSRect(x: bar.minX + Self.barInset, y: bar.minY + Self.barInset - 2 - height, width: width, height: height), display: true)
    }

    func hideAssistant() { assistant?.orderOut(nil) }

    /// Resizes the conversation for the current view, still under the bar.
    func fitAssistant() { layoutStack() }

    /// Switches the bar and conversation between a small and the usual size.
    func toggleAssistantSize() {
        model.panelCompact.toggle()
        if let dock, !model.dockMinimized {
            let old = dock.frame
            // The right edge stays put, as the controls that were clicked are there.
            dock.setFrame(NSRect(x: old.maxX - barWidth, y: old.minY, width: barWidth, height: old.height), display: true)
        }
        layoutStack()
    }

    // MARK: Moving

    private func panel(_ part: Part) -> OverlayPanel? {
        switch part {
        case .launcher: launcher
        case .dock: dock
        case .assistant: assistant
        }
    }

    func origin(of part: Part) -> NSPoint? { panel(part)?.frame.origin }

    /// Dragging either the bar or the conversation moves both together.
    func move(_ part: Part, to origin: NSPoint) {
        switch part {
        case .launcher: launcher?.setFrameOrigin(origin)
        case .dock:
            dock?.setFrameOrigin(origin)
            follow()
        case .assistant:
            guard let panel = assistant, let dock else { return }
            let travel = NSSize(width: origin.x - panel.frame.minX, height: origin.y - panel.frame.minY)
            panel.setFrameOrigin(origin)
            dock.setFrameOrigin(NSPoint(x: dock.frame.minX + travel.width, y: dock.frame.minY + travel.height))
        }
    }

    /// Keeps the conversation under the bar while it is dragged.
    private func follow() {
        guard let dock, let panel = assistant, panel.isVisible else { return }
        panel.setFrameOrigin(NSPoint(x: dock.frame.minX + Self.barInset, y: dock.frame.minY + Self.barInset - 2 - panel.frame.height))
    }

    /// Keeps the window on screen and remembers where it was put.
    func finishMove(_ part: Part) {
        switch part {
        case .launcher:
            guard let launcher else { return }
            clamp(launcher)
            save(launcher.frame.origin, "launcherOrigin")
        case .dock, .assistant:
            guard let dock else { return }
            clamp(dock)
            layoutStack()
            if model.assist?.isActive == true { save(dock.frame.origin, "dockOrigin") }
            // The launcher returns where the open chooser was left.
            else { save(dock.frame.origin, "launcherOrigin"); launcher?.setFrameOrigin(dock.frame.origin) }
        }
    }

    private func save(_ point: NSPoint, _ key: String) { UserDefaults.standard.set(NSStringFromPoint(point), forKey: key) }
    private func savedPoint(_ key: String) -> NSPoint? { UserDefaults.standard.string(forKey: key).map(NSPointFromString) }

    private func showLauncher(visible: Bool) {
        let panel = launcher ?? makePanel(size: Self.launcherSize) { LauncherView(overlays: self) }
        if launcher == nil {
            launcher = panel
            let area = NSScreen.main?.visibleFrame ?? .zero
            let saved = UserDefaults.standard.string(forKey: "launcherOrigin").map(NSPointFromString)
            panel.setFrameOrigin(saved ?? NSPoint(x: area.maxX - 88, y: area.minY + 24))
        }
        clamp(panel)
        if visible { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
    }

    private func showDock(_ size: NSSize) {
        let panel = dock ?? makePanel(size: size) { DockView(overlays: self) }
        dock = panel
        if panel.frame.size != size || !panel.isVisible {
            let wasVisible = panel.isVisible
            let old = panel.frame
            panel.setContentSize(size)
            if wasVisible {
                // Resizing keeps the bar where the person sees it.
                panel.setFrameOrigin(NSPoint(x: old.minX, y: old.minY))
            } else if let anchor = launcher?.frame, let area = (launcher?.screen ?? NSScreen.main)?.visibleFrame {
                // Opens over the launcher, extending away from the screen edge.
                let x = anchor.midX > area.midX ? anchor.maxX - size.width : anchor.minX
                panel.setFrameOrigin(NSPoint(x: x, y: anchor.minY - 2))
                // The Assist bar returns to where it was last dragged.
                if model.assist?.isActive == true {
                    // Near the top of the screen until the person puts it elsewhere.
                    panel.setFrameOrigin(savedPoint("dockOrigin") ?? NSPoint(x: area.midX - size.width / 2, y: area.maxY - size.height - 8))
                }
            }
        }
        clamp(panel)
        panel.orderFrontRegardless()
    }

    /// Anywhere on whichever screen the window is mostly on, including over the
    /// macOS Dock, but never under the menu bar.
    private func screen(of panel: NSPanel) -> NSScreen? {
        let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        return NSScreen.screens.first { $0.frame.contains(center) } ?? panel.screen ?? NSScreen.main
    }

    private func usable(_ screen: NSScreen) -> NSRect {
        NSRect(x: screen.frame.minX, y: screen.frame.minY, width: screen.frame.width, height: screen.visibleFrame.maxY - screen.frame.minY)
    }

    private func clamp(_ panel: NSPanel) {
        guard let screen = screen(of: panel) else { return }
        let area = usable(screen)
        var frame = panel.frame
        frame.size.width = min(frame.width, area.width - 4)
        frame.size.height = min(frame.height, area.height - 4)
        frame.origin.x = min(max(frame.minX, area.minX + 2), area.maxX - frame.width - 2)
        frame.origin.y = min(max(frame.minY, area.minY + 2), area.maxY - frame.height - 2)
        if frame != panel.frame { panel.setFrame(frame, display: true) }
    }

    private func clampAll() {
        [launcher, dock].compactMap { $0 }.forEach(clamp)
        layoutStack()
    }

    private func blankPanel(frame: NSRect, style: NSWindow.StyleMask, keyboard: Bool) -> OverlayPanel {
        let panel = OverlayPanel(contentRect: frame, styleMask: style, backing: .buffered, defer: false)
        panel.acceptsKeyboard = keyboard
        // Above the macOS Dock, so the controls can be placed anywhere.
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        // Privacy is applied before the window is ever shown.
        protect(panel)
        return panel
    }

    private func makePanel<Content: View>(
        size: NSSize, keyboard: Bool = false, resizable: Bool = false, @ViewBuilder content: () -> Content
    ) -> OverlayPanel {
        var style: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
        if resizable { style.insert(.resizable) }
        let panel = blankPanel(frame: NSRect(origin: .zero, size: size), style: style, keyboard: keyboard)
        let host = FirstClickHostingView(rootView: content().environment(model))
        host.sizingOptions = []
        panel.contentView = host
        return panel
    }
}

extension NSUserInterfaceItemIdentifier {
    static let expoMain = NSUserInterfaceItemIdentifier("expo.main")
}

extension Notification.Name {
    static let expoFocusAsk = Notification.Name("expo.focusAsk")
    static let expoScreenAsk = Notification.Name("expo.screenAsk")
}
