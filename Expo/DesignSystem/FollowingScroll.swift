import AppKit
import SwiftUI

/// A scroll view that stays at the newest content as it grows, until the person
/// scrolls up to read; then it holds still and offers the way back.
struct FollowingScroll<Content: View>: View {
    /// A change sends the view to the end, wherever the person had scrolled.
    var jump = 0
    /// How many messages there are, to say when a new one arrives out of view.
    var count = 0
    @ViewBuilder var content: Content
    @State private var following = true
    @State private var taps = 0
    @State private var seen = 0

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .background { Follower(jump: jump &+ taps, following: $following) }
        }
        .overlay(alignment: .bottom) {
            if !following {
                Button { taps += 1 } label: {
                    Label(count > seen ? "New message" : "Latest", systemImage: "arrow.down")
                }
                .buttonStyle(ChipStyle(on: true))
                .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.2), value: following)
        .onChange(of: following) { _, now in if !now { seen = count } }
    }
}

private struct Follower: NSViewRepresentable {
    var jump: Int
    @Binding var following: Bool

    func makeNSView(context: Context) -> ScrollProbe {
        let probe = ScrollProbe()
        probe.lastJump = jump
        return probe
    }

    func updateNSView(_ probe: ScrollProbe, context: Context) {
        probe.report = { value in following = value }
        probe.attach()
        if probe.lastJump != jump {
            probe.lastJump = jump
            probe.jump()
        }
    }
}

/// Watches the scroll view it sits in.
final class ScrollProbe: NSView {
    var report: (Bool) -> Void = { _ in }
    var lastJump = 0
    private(set) var follow = ScrollFollow()
    private weak var scroll: NSScrollView?
    private var contentHeight: CGFloat = 0
    private var visibleSize = NSSize.zero
    private var offset: CGFloat = 0
    private var reported = true

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // The enclosing scroll view is in place on the next turn of the run loop.
        DispatchQueue.main.async { [weak self] in self?.attach() }
    }

    func attach() {
        guard let found = enclosingScrollView, found !== scroll, let content = found.documentView else { return }
        NotificationCenter.default.removeObserver(self)
        scroll = found
        found.contentView.postsBoundsChangedNotifications = true
        found.contentView.postsFrameChangedNotifications = true
        content.postsFrameChangedNotifications = true
        let watched: [(Notification.Name, NSView)] = [
            (NSView.boundsDidChangeNotification, found.contentView),
            (NSView.frameDidChangeNotification, found.contentView),
            (NSView.frameDidChangeNotification, content),
        ]
        for (name, view) in watched {
            NotificationCenter.default.addObserver(self, selector: #selector(changed), name: name, object: view)
        }
        contentHeight = 0
        changed()
    }

    func jump() {
        follow.jump()
        pin()
        tell()
    }

    /// The furthest the view can scroll, and the nearest.
    private func limits(_ scroll: NSScrollView) -> (start: CGFloat, end: CGFloat) {
        let clip = scroll.contentView
        let height = scroll.documentView?.frame.height ?? 0
        let start = -clip.contentInsets.top
        return (start, max(start, height - clip.bounds.height + clip.contentInsets.bottom))
    }

    private func pin() {
        guard let scroll, let content = scroll.documentView else { return }
        let range = limits(scroll)
        let target = content.isFlipped ? range.end : range.start
        guard abs(scroll.contentView.bounds.origin.y - target) > 0.5 else { return }
        scroll.contentView.scroll(to: NSPoint(x: scroll.contentView.bounds.origin.x, y: target))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    @objc private func changed() {
        guard let scroll, let content = scroll.documentView else { return }
        let height = content.frame.height
        let size = scroll.contentView.bounds.size
        let now = scroll.contentView.bounds.origin.y
        if abs(height - contentHeight) > 0.5 || size != visibleSize {
            // More to show, or a different window size: not the person scrolling.
            contentHeight = height
            visibleSize = size
            offset = now
            if follow.following { pin() }
        } else if abs(now - offset) > 0.1 {
            let range = limits(scroll)
            let flipped = content.isFlipped
            let distance = flipped ? range.end - now : now - range.start
            let towardStart = flipped ? now < offset : now > offset
            offset = now
            follow.scrolled(distanceFromEnd: distance, towardStart: towardStart)
        }
        offset = scroll.contentView.bounds.origin.y
        tell()
    }

    private func tell() {
        guard follow.following != reported else { return }
        reported = follow.following
        let value = reported
        // Never during a view update.
        DispatchQueue.main.async { [weak self] in self?.report(value) }
    }

}
