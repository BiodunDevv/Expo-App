import SwiftUI

/// Invisible grips along the sides, the bottom and the lower corners.
struct ResizeEdges: View {
    @Environment(AppModel.self) private var model
    let overlays: OverlayController
    private static let thickness: CGFloat = 7
    private static let corner: CGFloat = 16

    var body: some View {
        let open = model.layout.chatOpen
        ZStack {
            Grip(overlays: overlays, edges: .left, cursor: .resizeLeftRight)
                .frame(width: Self.thickness).frame(maxWidth: .infinity, alignment: .leading)
            Grip(overlays: overlays, edges: .right, cursor: .resizeLeftRight)
                .frame(width: Self.thickness).frame(maxWidth: .infinity, alignment: .trailing)
            if open {
                Grip(overlays: overlays, edges: .bottom, cursor: .resizeUpDown)
                    .frame(height: Self.thickness).frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.horizontal, Self.corner)
                Grip(overlays: overlays, edges: [.left, .bottom], cursor: .crosshair)
                    .frame(width: Self.corner, height: Self.corner).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                Grip(overlays: overlays, edges: [.right, .bottom], cursor: .crosshair)
                    .frame(width: Self.corner, height: Self.corner).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
    }

    private struct Grip: View {
        let overlays: OverlayController
        let edges: SessionFrame.Edges
        let cursor: NSCursor
        /// The pointer and the window when the drag began, in screen points.
        @State private var start: (mouse: NSPoint, frame: NSRect)?
        @State private var hovering = false
        @State private var pushed = false
        @Environment(AppModel.self) private var model

        var body: some View {
            Color.white.opacity(hovering || start != nil ? 0.12 : 0.001)
                .contentShape(.rect)
                .onHover { inside in
                    guard inside != hovering else { return }
                    hovering = inside
                    // Hidden from screen sharing, the pointer keeps its plain shape.
                    if inside && !model.capturePrivacy.isHidden { cursor.push(); pushed = true }
                    else if !inside && pushed { NSCursor.pop(); pushed = false }
                }
                .onDisappear { if pushed { NSCursor.pop() } }
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .global)
                        .onChanged { _ in
                            // Screen coordinates stay stable while the window changes.
                            let mouse = NSEvent.mouseLocation
                            guard let start else {
                                if let frame = overlays.sessionFrame { self.start = (mouse, frame) }
                                return
                            }
                            overlays.resizeSession(from: start.frame, edges: edges,
                                                   travel: CGSize(width: mouse.x - start.mouse.x, height: mouse.y - start.mouse.y))
                        }
                        .onEnded { _ in
                            start = nil
                            overlays.finishResize()
                        })
                .accessibilityHidden(true)
        }
    }
}
