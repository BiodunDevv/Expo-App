import SwiftUI

/// Moves one of Expo's floating windows when the person drags it. Buttons and
/// other controls inside keep working, because a drag needs a few points of travel.
struct WindowDrag: ViewModifier {
    let overlays: OverlayController
    let part: OverlayController.Part
    /// Where the window and the pointer were when the drag began, in screen points.
    @State private var start: (window: NSPoint, mouse: NSPoint)?

    func body(content: Content) -> some View {
        content
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 3, coordinateSpace: .global)
                    .onChanged { _ in
                        // Screen coordinates stay stable while the window itself moves.
                        let mouse = NSEvent.mouseLocation
                        guard let start else {
                            if let origin = overlays.origin(of: part) { self.start = (origin, mouse) }
                            return
                        }
                        overlays.move(part, to: NSPoint(x: start.window.x + mouse.x - start.mouse.x,
                                                        y: start.window.y + mouse.y - start.mouse.y))
                    }
                    .onEnded { _ in
                        if start != nil { overlays.finishMove(part) }
                        start = nil
                    }
            )
    }
}

extension View {
    func movesWindow(_ overlays: OverlayController, _ part: OverlayController.Part) -> some View {
        modifier(WindowDrag(overlays: overlays, part: part))
    }
}
