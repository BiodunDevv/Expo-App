import SwiftUI

/// A selection pill that stretches like liquid as it moves between equal
/// segments. Expo's own take on the gooey effect: two blobs travel at different
/// speeds and are blurred and cut back to one shape, so they melt together.
struct GooeyPill: View {
    var index: Int
    var count: Int
    var fill: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var from = 0.0
    @State private var started = Date.distantPast

    private static let duration = 0.55

    var body: some View {
        TimelineView(.animation(paused: Date().timeIntervalSince(started) > Self.duration)) { timeline in
            let elapsed = reduceMotion ? Self.duration : timeline.date.timeIntervalSince(started)
            let lead = position(elapsed / 0.3), trail = position(elapsed / Self.duration)
            Canvas { context, size in
                let width = size.width / Double(count)
                func blob(_ place: Double) -> Path {
                    Path(roundedRect: CGRect(x: place * width, y: 0, width: width, height: size.height),
                         cornerRadius: size.height / 2, style: .continuous)
                }
                // Cutting the blurred blobs at half strength joins them smoothly.
                context.addFilter(.alphaThreshold(min: 0.5, color: fill))
                context.addFilter(.blur(radius: 7))
                context.drawLayer { layer in
                    layer.fill(blob(lead), with: .color(.black))
                    layer.fill(blob(trail), with: .color(.black))
                    // A thin neck keeps the two joined while they are apart.
                    let a = min(lead, trail) * width + width / 2, b = max(lead, trail) * width + width / 2
                    layer.fill(Path(CGRect(x: a, y: size.height * 0.3, width: b - a, height: size.height * 0.4)), with: .color(.black))
                }
            }
        }
        .onChange(of: index) { old, _ in
            from = Double(old)
            started = Date()
        }
        .task(id: started) {
            // One more pass once settled, so the timeline can pause.
            try? await Task.sleep(for: .seconds(Self.duration))
            if !Task.isCancelled { from = Double(index) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func position(_ progress: Double) -> Double {
        let t = min(1, max(0, progress))
        let eased = 1 - pow(1 - t, 3)
        return from + (Double(index) - from) * (started == .distantPast ? 1 : eased)
    }
}
