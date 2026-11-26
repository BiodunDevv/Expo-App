import SwiftUI

struct Hairline: View {
    var body: some View { Rectangle().fill(Theme.border).frame(height: 1) }
}

/// A small status label.
struct Tag: View {
    enum Tone { case neutral, accent, success, warning, danger }
    var text: String
    var tone = Tone.neutral

    var body: some View {
        let colors: (Color, Color) = switch tone {
        case .neutral: (Theme.secondary, Theme.subtle)
        case .accent: (Theme.text, Theme.accentSoft)
        case .success: (Theme.success, Theme.successSoft)
        case .warning: (Theme.warning, Theme.warningSoft)
        case .danger: (Theme.danger, Theme.dangerSoft)
        }
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(colors.0)
            .padding(.horizontal, 8)
            .frame(height: 19)
            .background(colors.1, in: .rect(cornerRadius: 5))
    }
}

/// Content settles into place when a page appears, unless Reduce Motion is on.
private struct Rise: ViewModifier {
    var delay: Double
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 6)
            .onAppear { withAnimation(.smooth(duration: 0.3).delay(delay)) { shown = true } }
    }
}

extension View {
    func rise(_ delay: Double = 0) -> some View { modifier(Rise(delay: delay)) }
}

struct Card<Content: View>: View {
    var title: String?
    var subtitle: String?
    /// Name of an Icons8 icon shown beside the title.
    var icon: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            if let title {
                HStack(spacing: 10) {
                    if let icon { Icon8(icon, size: 26) }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.system(size: 14.5, weight: .bold))
                        if let subtitle { Text(subtitle).font(.system(size: 11.5)).foregroundStyle(Theme.secondary) }
                    }
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.surface, in: .rect(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(Theme.border) }
    }
}

struct Page<Content: View>: View {
    var title: String
    var subtitle: String
    /// A picture turns the heading into a banner.
    var art: String?
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Group {
                    if let art {
                        PageBanner(title: title, subtitle: subtitle, art: art)
                    } else {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(title).font(.system(size: 20, weight: .bold))
                            Text(subtitle).font(.system(size: 12.5)).foregroundStyle(Theme.secondary)
                        }
                        .padding(.bottom, 2)
                    }
                }
                .rise()
                content.rise(0.06)
            }
            .frame(maxWidth: 740, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 34)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
    }
}

struct StatusPill: View {
    var label: String
    var color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.secondary).lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Theme.surface, in: .capsule)
        .overlay { Capsule().stroke(Theme.border) }
    }
}

struct Logo: View {
    @Environment(AppModel.self) private var model
    var size: CGFloat = 32
    var body: some View {
        MarkImage(mark: model.mark, size: size).accessibilityHidden(true)
    }
}

struct ToastStack: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 8) {
            ForEach(model.toasts) { toast in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: toast.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(toast.isError ? Theme.danger : Theme.success)
                    Text(toast.message).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    if toast.offersPlans { Button("See plans") { model.openSettings() }.buttonStyle(.expo(.plain, compact: true)) }
                    Button { model.toasts.removeAll { $0.id == toast.id } } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).foregroundStyle(Theme.tertiary).accessibilityLabel("Dismiss")
                }
                .padding(12)
                .frame(maxWidth: 420, alignment: .leading)
                .background(Theme.surface, in: .rect(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).stroke(Theme.border) }
                .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
            }
        }
        .padding(14)
        .animation(.snappy, value: model.toasts)
    }
}
