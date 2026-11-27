import CoreGraphics

/// Where the session window goes when its edges are dragged. Coordinates are the
/// screen's, so y grows upward and the top edge stays where it is.
enum SessionFrame {
    static let minimumWidth: CGFloat = 520
    static let defaultWidth: CGFloat = 690
    static let minimumHeight: CGFloat = 300
    static let defaultHeight: CGFloat = 500
    static let smallWidth: CGFloat = 560
    static let smallHeight: CGFloat = 360

    static var small: CGSize { CGSize(width: smallWidth, height: smallHeight) }
    static var usual: CGSize { CGSize(width: defaultWidth, height: defaultHeight) }

    /// Whether a window is already at, or under, the small size. Closed, only
    /// the width counts, as the height belongs to the content.
    static func isSmall(_ size: CGSize, open: Bool) -> Bool {
        size.width <= smallWidth + 1 && (!open || size.height <= smallHeight + 1)
    }

    /// What the size button switches to: the small size, or back to the size
    /// from before (the usual one when there was none).
    static func toggled(_ size: CGSize, open: Bool, previous: CGSize?) -> CGSize {
        guard isSmall(size, open: open) else { return small }
        guard let previous, !isSmall(previous, open: true) else { return usual }
        return previous
    }

    struct Edges: OptionSet, Sendable {
        let rawValue: Int
        static let left = Edges(rawValue: 1)
        static let right = Edges(rawValue: 2)
        static let bottom = Edges(rawValue: 4)
    }

    /// `travel` is how far the pointer has moved since the drag began at `start`.
    static func resized(_ start: CGRect, edges: Edges, travel: CGSize, within area: CGRect) -> CGRect {
        var left = start.minX, right = start.maxX, bottom = start.minY
        let top = start.maxY
        if edges.contains(.left) {
            left = min(max(start.minX + travel.width, area.minX), right - minimumWidth)
        }
        if edges.contains(.right) {
            right = max(min(start.maxX + travel.width, area.maxX), left + minimumWidth)
        }
        if edges.contains(.bottom) {
            bottom = min(max(start.minY + travel.height, area.minY), top - minimumHeight)
        }
        return CGRect(x: left, y: bottom, width: right - left, height: top - bottom)
    }

    /// A window of this size with its top-left corner as near as possible to the
    /// remembered one while staying wholly on screen.
    static func placed(topLeft: CGPoint, size: CGSize, within area: CGRect) -> CGRect {
        let width = min(size.width, area.width), height = min(size.height, area.height)
        let x = min(max(topLeft.x, area.minX), area.maxX - width)
        let top = max(min(topLeft.y, area.maxY), area.minY + height)
        return CGRect(x: x, y: top - height, width: width, height: height)
    }
}
