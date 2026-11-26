import AVFoundation
import SwiftUI

/// A muted, looping illustration with a transparent background (HEVC with alpha).
/// With Reduce Motion on, its still poster is shown instead.
struct LoopingAnimation: View {
    var name: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if !reduceMotion, let url = Bundle.main.url(forResource: name, withExtension: "mp4")
                ?? Bundle.main.url(forResource: name, withExtension: "mov") {
                PlayerView(url: url)
            } else if let url = Bundle.main.url(forResource: "\(name)-poster", withExtension: "png"), let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFit()
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

private struct PlayerView: NSViewRepresentable {
    var url: URL

    func makeNSView(context: Context) -> LoopingPlayerView { LoopingPlayerView(url: url) }
    func updateNSView(_ view: LoopingPlayerView, context: Context) {}
    static func dismantleNSView(_ view: LoopingPlayerView, coordinator: ()) { view.stop() }
}

final class LoopingPlayerView: NSView {
    let player = AVQueuePlayer()
    let playerLayer = AVPlayerLayer()
    private var looper: AVPlayerLooper?
    private var observer: NSObjectProtocol?

    init(url: URL) {
        super.init(frame: .zero)
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.allowsExternalPlayback = false
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        // A format with an alpha channel keeps the background transparent.
        playerLayer.pixelBufferAttributes = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        playerLayer.backgroundColor = .clear
        wantsLayer = true
        layer?.addSublayer(playerLayer)
    }

    /// Decoration only: clicks and drags belong to the SwiftUI view around it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    /// Plays only while the window can actually be seen.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        guard let window else { player.pause(); return }
        observer = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.matchVisibility() }
        }
        player.play()
    }

    private func matchVisibility() {
        if window?.occlusionState.contains(.visible) == true { player.play() } else { player.pause() }
    }

    func stop() {
        player.pause()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        looper?.disableLooping()
    }
}
