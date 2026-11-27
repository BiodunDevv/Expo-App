import SwiftUI

// The pieces that give pages their life: Icons8 icons, page banners, figures
// and empty states.

/// An Icons8 icon from the asset catalog (`ic-<name>`).
struct Icon8: View {
    var name: String
    var size: CGFloat = 20

    init(_ name: String, size: CGFloat = 20) {
        self.name = name
        self.size = size
    }

    var body: some View {
        Image("ic-\(name)").resizable().interpolation(.high).scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A picture that drifts gently, and holds still with Reduce Motion.
struct DriftingArt: View {
    var name: String
    var size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let art = Image(name).resizable().interpolation(.high).scaledToFit().frame(width: size, height: size)
        Group {
            if reduceMotion {
                art
            } else {
                art.phaseAnimator([false, true]) { view, up in
                    view.offset(y: up ? -4 : 3).rotationEffect(.degrees(up ? -1.5 : 1.5))
                } animation: { _ in .easeInOut(duration: 2.4) }
            }
        }
        .accessibilityHidden(true)
    }
}

/// The top of a page: its name beside a picture, on a soft wash of colour.
struct PageBanner: View {
    var title: String
    var subtitle: String
    var art: String

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 22, weight: .bold))
                Text(subtitle).font(.system(size: 12.5)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            DriftingArt(name: art, size: 96)
        }
        .padding(.leading, 20).padding(.trailing, 14).padding(.vertical, 10)
        .background { Wash() }
        .clipShape(.rect(cornerRadius: 22))
        .overlay { RoundedRectangle(cornerRadius: 22).stroke(Theme.border) }
    }
}

/// Two faint pools of colour behind a banner.
struct Wash: View {
    var body: some View {
        ZStack {
            Theme.surface
            RadialGradient(colors: [Color(.sRGB, red: 0.45, green: 0.62, blue: 1).opacity(0.16), .clear], center: .topTrailing, startRadius: 0, endRadius: 320)
            RadialGradient(colors: [Color(.sRGB, red: 1, green: 0.56, blue: 0.72).opacity(0.13), .clear], center: .bottomLeading, startRadius: 0, endRadius: 300)
        }
    }
}

/// One figure about the person's own use, lifting slightly under the pointer.
struct StatTile: View {
    var icon: String
    var value: String
    var label: String
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 11) {
            Icon8(icon, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.system(size: 18, weight: .bold)).monospacedDigit().contentTransition(.numericText())
                Text(label).font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.surface, in: .rect(cornerRadius: 19))
        .overlay { RoundedRectangle(cornerRadius: 19).stroke(Theme.border) }
        .shadow(color: .black.opacity(hovering ? 0.09 : 0), radius: 8, y: 4)
        .offset(y: hovering ? -2 : 0)
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.2), value: hovering)
        .accessibilityElement(children: .combine)
    }
}

/// An illustration, a line of explanation and, when useful, a way forward.
struct EmptyScene<Action: View>: View {
    var animation: String
    var title: String
    var detail: String
    @ViewBuilder var action: Action

    var body: some View {
        VStack(spacing: 8) {
            LoopingAnimation(name: animation).frame(width: 130, height: 130)
            Text(title).font(.system(size: 14, weight: .bold))
            Text(detail).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 360)
            action
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}
