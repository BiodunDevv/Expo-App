import SwiftUI
import ThinkingOrbsKit

/// The floating bot: click to choose what to do, drag to move anywhere.
struct LauncherView: View {
    @Environment(AppModel.self) private var model
    let overlays: OverlayController
    @State private var start: (window: NSPoint, mouse: NSPoint)?
    @State private var moved = false
    @State private var hovering = false
    /// Travel beyond this is a drag; a trackpad click wobbles less.
    private static let dragThreshold: CGFloat = 8

    var body: some View {
        RobotMark(size: 60)
            .scaleEffect(hovering ? 1.07 : 1)
            .animation(.spring(duration: 0.3, bounce: 0.45), value: hovering)
            .frame(width: 64, height: 64)
            // Barely there, so macOS gives the whole circle to Expo, not the app behind.
            .background(Circle().fill(.black.opacity(0.02)))
            .contentShape(.circle)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        // Screen coordinates stay stable while the window itself moves.
                        let mouse = NSEvent.mouseLocation
                        guard let start else {
                            if let origin = overlays.origin(of: .launcher) { self.start = (origin, mouse) }
                            return
                        }
                        let travel = NSSize(width: mouse.x - start.mouse.x, height: mouse.y - start.mouse.y)
                        guard moved || hypot(travel.width, travel.height) > Self.dragThreshold else { return }
                        moved = true
                        overlays.move(.launcher, to: NSPoint(x: start.window.x + travel.width, y: start.window.y + travel.height))
                    }
                    .onEnded { _ in
                        if moved { overlays.finishMove(.launcher) } else { overlays.openFromBot() }
                        start = nil
                        moved = false
                    }
            )
            .overlay(alignment: .topTrailing) {
                if hovering && !moved {
                    Button { overlays.hideFloatingBot() } label: {
                        Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Theme.text)
                            .frame(width: 17, height: 17)
                            .background(Theme.surface, in: .circle)
                            .overlay { Circle().stroke(Theme.border) }
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .hint("Turn the floating bot off")
                    .accessibilityLabel("Turn the floating bot off")
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .onHover { hovering = $0 }
            .contextMenu {
                Button("New Session…") { model.requestAssistStart() }
                Button("Practice") { model.open(.practice) }
                Button("Open Expo") { model.showMainWindow() }
                Divider()
                Button("Turn Off Floating Bot") { overlays.hideFloatingBot() }
            }
            .hint("Start with Expo. Drag to move.")
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Open Expo Assist")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { overlays.openFromBot() }
    }
}
