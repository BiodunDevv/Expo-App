import CoreGraphics

/// Whether a conversation keeps itself at the newest message. Scrolling up
/// stops it; returning to the end, or asking to, starts it again.
struct ScrollFollow: Equatable, Sendable {
    /// This close to the end counts as being there.
    static let tolerance: CGFloat = 2
    /// Scrolling back down to within this distance picks the end up again.
    static let catchUp: CGFloat = 24

    private(set) var following = true

    /// The view moved while its content and size stayed the same, so the person
    /// moved it. `distance` is what is left below the visible part.
    mutating func scrolled(distanceFromEnd distance: CGFloat, towardStart: Bool) {
        if distance <= Self.tolerance { following = true }
        else if towardStart { following = false }
        else if distance <= Self.catchUp { following = true }
    }

    mutating func jump() { following = true }
}
