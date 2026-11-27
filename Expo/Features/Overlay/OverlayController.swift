import AppKit
import SwiftUI

private final class OverlayPanel: NSPanel {
    var acceptsKeyboard = false
    override var canBecomeKey: Bool { acceptsKeyboard }
    override var canBecomeMain: Bool { false }

    /// While Expo is hidden from screen sharing, its windows are invisible to
    /// others, so the pointer must not change shape over them and give them away.
    var plainPointer = false {
        didSet {
            guard plainPointer != oldValue else { return }
            if plainPointer { disableCursorRects(); NSCursor.arrow.set() } else { enableCursorRects() }
        }
    }

    override func sendEvent(_ event: NSEvent) {
        guard plainPointer else { return super.sendEvent(event) }
        switch event.type {
        case .cursorUpdate:
            NSCursor.arrow.set()
        case .mouseMoved, .mouseEntered, .mouseExited, .leftMouseDown, .leftMouseUp, .leftMouseDragged:
            super.sendEvent(event)
            NSCursor.arrow.set()
            // Text views set their own pointer a moment later.
            DispatchQueue.main.async { NSCursor.arrow.set() }
        default:
            super.sendEvent(event)
        }
    }
}

/// Floating controls respond to the first click while another app is active.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Owns the floating bot, its chooser and the session window, and applies
/// screen-capture privacy to every Expo window.
@MainActor
final class OverlayController {
    enum Part { case launcher, chooser, session }

    private unowned let model: AppModel
    private var launcher: OverlayPanel?
    private var chooser: OverlayPanel?
    private var session: OverlayPanel?
    private var chooserOpen = false
    private var hidden = true
    var onReplaceWindows: () -> Void = {}
    var onProtectionFailure: () -> Void = {}
    private var failedChecks = 0
    private var watchdog: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    private static let launcherSize = NSSize(width: 64, height: 64)
    private static let chooserSize = NSSize(width: 360, height: 262)
    private static let signedOutSize = NSSize(width: 340, height: 160)
    private var wasActive = false
    /// The input row and toolbar, as the view last measured them.
    private var closedHeight: CGFloat = 104
    /// Whether the session window is laid out as the small note.
    private var showingCompact = false
    /// Where an animation is taking the session window.
    private var target: NSRect?

    init(model: AppModel) {
        self.model = model
        startWatchdog()
        observe(NSApplication.didChangeScreenParametersNotification) { controller, _ in controller.clampAll() }
        // Sheets, popovers and dialogs are new windows: protect them as they appear.
        observe(NSApplication.didUpdateNotification) { controller, _ in NSApp.windows.forEach(controller.protect) }
        // Menus open their own windows, which exist one turn of the run loop later.
        observe(NSMenu.didBeginTrackingNotification) { controller, _ in
            RunLoop.main.perform(inModes: [.common, .eventTracking]) { [weak controller] in
                MainActor.assumeIsolated {
                    if let controller { NSApp.windows.forEach(controller.protect) }
                }
            }
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
        chooser = chooser.map(replacement)
        session = session.map(replacement)
        onReplaceWindows()
    }

    private func replacement(for old: OverlayPanel) -> OverlayPanel {
        let panel = blankPanel(frame: old.frame, style: old.styleMask, keyboard: old.acceptsKeyboard)
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

    /// Reconciles the visible windows with sign-in and session state. The floating
    /// bot is available before sign-in so screen-share privacy is always in reach.
    func synchronize() {
        guard model.phase == .ready, model.privacyFailure == nil else {
            [launcher, chooser, session].forEach { $0?.orderOut(nil) }
            chooserOpen = false
            return
        }
        let active = model.overlaysEligible && model.assist.isActive
        defer { wasActive = active }
        if active {
            chooserOpen = false
            chooser?.orderOut(nil)
            if model.sessionHidden {
                session?.orderOut(nil)
                // The way back to a hidden session, even with the bot switched off.
                showLauncher(visible: true)
            } else {
                showLauncher(visible: false)
                showSessionWindow(focus: !wasActive)
            }
            return
        }
        session?.orderOut(nil)
        guard model.showsFloatingButton else {
            [launcher, chooser].forEach { $0?.orderOut(nil) }
            chooserOpen = false
            return
        }
        // The bot steps aside while its chooser is open.
        showLauncher(visible: !chooserOpen)
        if chooserOpen { showChooser() } else { chooser?.orderOut(nil) }
    }

    /// Turns the floating bot off, saying where to find it again.
    func hideFloatingBot() {
        chooserOpen = false
        model.showsFloatingButton = false
        model.notify("The floating bot is off. Turn it on from the Expo icon in the menu bar, or in Settings.")
    }

    func closeChooser() {
        chooserOpen = false
        synchronize()
    }

    /// A click on the floating bot.
    func openFromBot() {
        if model.overlaysEligible && model.assist.isActive { showAssistant(); return }
        chooserOpen.toggle()
        synchronize()
    }

    func showAssistant() {
        guard model.privacyFailure == nil, model.overlaysEligible else { model.showMainWindow(); return }
        guard model.assist.isActive else {
            chooserOpen = true
            synchronize()
            return
        }
        model.sessionHidden = false
        model.layout.expand()
        synchronize()
        layoutSession()
        session?.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .expoFocusAsk, object: nil)
    }

    /// Puts the session window away; the floating bot brings it back.
    func hideAssistant() {
        model.sessionHidden = true
        synchronize()
    }

    // MARK: Session window

    private var widthKey: String { "sessionWidth.\(model.state.account?.id ?? "none")" }
    private var previousKey: String { "sessionPreviousSize.\(model.state.account?.id ?? "none")" }
    private var heightKey: String { "sessionHeight.\(model.state.account?.id ?? "none")" }

    private func saved(_ key: String, _ fallback: CGFloat, atLeast minimum: CGFloat) -> CGFloat {
        let value = UserDefaults.standard.double(forKey: key)
        return value >= minimum ? value : fallback
    }

    /// The width of the window when it is not made small.
    private var fullWidth: CGFloat { saved(widthKey, SessionFrame.defaultWidth, atLeast: SessionFrame.minimumWidth) }

    private var sessionSize: NSSize {
        if model.layout.compact { return CompactSession.size }
        return NSSize(width: fullWidth,
                      height: model.layout.chatOpen ? saved(heightKey, SessionFrame.defaultHeight, atLeast: SessionFrame.minimumHeight) : closedHeight)
    }

    private func showSessionWindow(focus: Bool) {
        let panel = session ?? makePanel(size: sessionSize, keyboard: true) { SessionView(overlays: self) }
        let wasVisible = session?.isVisible == true
        session = panel
        layoutSession(showing: true)
        if !wasVisible || focus {
            panel.makeKeyAndOrderFront(nil)
            NotificationCenter.default.post(name: .expoFocusAsk, object: nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    /// Where the full window's top-left corner is, when the window is at `frame`.
    /// The small note sits centred under the top of the full window.
    private func fullTopLeft(of frame: NSRect) -> NSPoint {
        NSPoint(x: showingCompact ? (frame.midX - fullWidth / 2).rounded() : frame.minX, y: frame.maxY)
    }

    /// Sizes the window for what it shows. The top edge stays put, so the input
    /// never moves when the chat opens or closes.
    private func layoutSession(showing: Bool = false) {
        guard let panel = session, showing || panel.isVisible else { return }
        let compact = model.layout.compact
        let size = sessionSize
        // Mid-animation the window is between two places; use where it is going.
        let current = target ?? panel.frame
        let topLeft: NSPoint
        if panel.isVisible {
            if compact == showingCompact { topLeft = NSPoint(x: current.minX, y: current.maxY) }
            else { topLeft = NSPoint(x: (current.midX - size.width / 2).rounded(), y: current.maxY) }
        } else {
            let area = NSScreen.main?.visibleFrame ?? .zero
            // Near the top of the screen, centred, until the person puts it elsewhere.
            let full = savedPoint("sessionTopLeft") ?? NSPoint(x: area.midX - fullWidth / 2, y: area.maxY - 12)
            topLeft = NSPoint(x: compact ? full.x + (fullWidth - size.width) / 2 : full.x, y: full.y)
        }
        let probe = NSRect(x: topLeft.x, y: topLeft.y - size.height, width: size.width, height: size.height)
        guard let screen = screen(containing: probe) else { return }
        let frame = SessionFrame.placed(topLeft: topLeft, size: size, within: usable(screen))
        // Already on its way there: let the animation finish.
        if frame == target && compact == showingCompact { return }
        let changesShape = panel.isVisible && frame != current
            && (compact != showingCompact || abs(frame.height - current.height) > 40)
        showingCompact = compact
        if changesShape && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            animate(panel, to: frame)
        } else {
            target = nil
            panel.setFrame(frame, display: true)
        }
        noteSize(frame.size)
    }

    /// Grows or shrinks the window smoothly.
    private func animate(_ panel: NSPanel, to frame: NSRect) {
        target = frame
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                if self?.target == frame { self?.target = nil }
            }
        }
    }

    private func noteSize(_ size: NSSize) {
        guard !model.layout.compact else { return }
        let small = SessionFrame.isSmall(size, open: model.layout.chatOpen)
        if model.sessionIsSmall != small { model.sessionIsSmall = small }
    }

    /// Switches between the small size and the size the person had before.
    func toggleSmallSize() {
        guard session != nil else { return }
        let current = CGSize(width: saved(widthKey, SessionFrame.defaultWidth, atLeast: SessionFrame.minimumWidth),
                             height: saved(heightKey, SessionFrame.defaultHeight, atLeast: SessionFrame.minimumHeight))
        let previous = savedPoint(previousKey).map { CGSize(width: $0.x, height: $0.y) }
        let next = SessionFrame.toggled(current, open: model.layout.chatOpen, previous: previous)
        if next == SessionFrame.small { save(NSPoint(x: current.width, y: current.height), previousKey) }
        UserDefaults.standard.set(Double(next.width), forKey: widthKey)
        UserDefaults.standard.set(Double(next.height), forKey: heightKey)
        layoutSession()
        if let frame = session?.frame { save(NSPoint(x: frame.minX, y: frame.maxY), "sessionTopLeft") }
    }

    /// The view reports how tall the input and toolbar are on their own.
    func setClosedHeight(_ height: CGFloat) {
        guard height > 0, abs(height - closedHeight) > 0.5 else { return }
        closedHeight = height.rounded(.up)
        if !model.layout.chatOpen && !model.layout.compact { layoutSession() }
    }

    func fitSession() { layoutSession() }

    var sessionFrame: NSRect? { session?.frame }

    /// Applies a drag on the window's edges, measured from where it began.
    func resizeSession(from start: NSRect, edges: SessionFrame.Edges, travel: CGSize) {
        guard let panel = session, let screen = screen(containing: start) else { return }
        var edges = edges
        target = nil
        // Closed, the height belongs to the content.
        if !model.layout.chatOpen { edges.remove(.bottom) }
        var frame = SessionFrame.resized(start, edges: edges, travel: travel, within: usable(screen))
        if !model.layout.chatOpen { frame.size.height = start.height; frame.origin.y = start.minY }
        panel.setFrame(frame, display: true)
        noteSize(frame.size)
    }

    /// Remembers the size and place the person chose.
    func finishResize() {
        guard let frame = session?.frame else { return }
        UserDefaults.standard.set(Double(frame.width), forKey: widthKey)
        if model.layout.chatOpen { UserDefaults.standard.set(Double(frame.height), forKey: heightKey) }
        save(NSPoint(x: frame.minX, y: frame.maxY), "sessionTopLeft")
    }

    // MARK: Moving

    private func panel(_ part: Part) -> OverlayPanel? {
        switch part {
        case .launcher: launcher
        case .chooser: chooser
        case .session: session
        }
    }

    func origin(of part: Part) -> NSPoint? { panel(part)?.frame.origin }

    func move(_ part: Part, to origin: NSPoint) {
        if part == .session { target = nil }
        panel(part)?.setFrameOrigin(origin)
    }

    /// Keeps the window on screen and remembers where it was put.
    func finishMove(_ part: Part) {
        guard let panel = panel(part) else { return }
        clamp(panel)
        switch part {
        case .launcher: save(panel.frame.origin, "launcherOrigin")
        case .session: save(fullTopLeft(of: panel.frame), "sessionTopLeft")
        case .chooser:
            // The bot returns where the open chooser was left.
            save(panel.frame.origin, "launcherOrigin")
            launcher?.setFrameOrigin(panel.frame.origin)
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

    private func showChooser() {
        let size = model.overlaysEligible ? Self.chooserSize : Self.signedOutSize
        let panel = chooser ?? makePanel(size: size) { ChooserView(overlays: self) }
        chooser = panel
        if panel.frame.size != size || !panel.isVisible {
            let wasVisible = panel.isVisible
            let old = panel.frame
            panel.setContentSize(size)
            if wasVisible {
                panel.setFrameOrigin(old.origin)
            } else if let anchor = launcher?.frame, let area = (launcher?.screen ?? NSScreen.main)?.visibleFrame {
                // Opens over the bot, extending away from the screen edge.
                let x = anchor.midX > area.midX ? anchor.maxX - size.width : anchor.minX
                panel.setFrameOrigin(NSPoint(x: x, y: anchor.minY - 2))
            }
        }
        clamp(panel)
        panel.orderFrontRegardless()
    }

    /// Anywhere on whichever screen the window is mostly on, including over the
    /// macOS Dock, but never under the menu bar.
    private func screen(containing frame: NSRect) -> NSScreen? {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main
    }

    private func usable(_ screen: NSScreen) -> NSRect {
        NSRect(x: screen.frame.minX, y: screen.frame.minY, width: screen.frame.width, height: screen.visibleFrame.maxY - screen.frame.minY)
    }

    private func clamp(_ panel: NSPanel) {
        guard let screen = screen(containing: panel.frame) else { return }
        let area = usable(screen)
        var frame = panel.frame
        frame.size.width = min(frame.width, area.width - 4)
        frame.size.height = min(frame.height, area.height - 4)
        frame.origin.x = min(max(frame.minX, area.minX + 2), area.maxX - frame.width - 2)
        frame.origin.y = min(max(frame.minY, area.minY + 2), area.maxY - frame.height - 2)
        if frame != panel.frame { panel.setFrame(frame, display: true) }
    }

    private func clampAll() {
        [launcher, chooser, session].compactMap { $0 }.forEach(clamp)
    }

    private func blankPanel(frame: NSRect, style: NSWindow.StyleMask, keyboard: Bool) -> OverlayPanel {
        let panel = OverlayPanel(contentRect: frame, styleMask: style, backing: .buffered, defer: false)
        panel.acceptsKeyboard = keyboard
        panel.plainPointer = hidden
        // Above the macOS Dock, so the controls can be placed anywhere.
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Dark glass with light text, whatever the Mac's appearance.
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        // Privacy is applied before the window is ever shown.
        protect(panel)
        return panel
    }

    private func makePanel<Content: View>(
        size: NSSize, keyboard: Bool = false, @ViewBuilder content: () -> Content
    ) -> OverlayPanel {
        let panel = blankPanel(frame: NSRect(origin: .zero, size: size), style: [.borderless, .nonactivatingPanel], keyboard: keyboard)
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
