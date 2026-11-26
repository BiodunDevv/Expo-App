import SwiftUI

struct ExpoButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, danger, plain }
    var kind = Kind.primary
    var compact = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 11.5 : 12.5, weight: .semibold))
            .padding(.horizontal, compact ? 12 : 18)
            .frame(height: compact ? 28 : 34)
            .foregroundStyle(kind == .primary || kind == .danger ? Theme.onAccent : (kind == .plain ? Theme.accent : Theme.text))
            .background {
                let shape = RoundedRectangle(cornerRadius: compact ? 8 : 10)
                switch kind {
                case .primary: shape.fill(Theme.accent)
                case .danger: shape.fill(Theme.danger)
                case .secondary: shape.fill(Theme.surface).overlay { shape.stroke(Theme.border) }
                case .plain: shape.fill(.clear)
                }
            }
            .opacity(enabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
            .contentShape(.rect)
    }
}

extension ButtonStyle where Self == ExpoButtonStyle {
    static var expo: ExpoButtonStyle { ExpoButtonStyle() }
    static func expo(_ kind: ExpoButtonStyle.Kind, compact: Bool = false) -> ExpoButtonStyle { ExpoButtonStyle(kind: kind, compact: compact) }
}

/// A button that shows progress while its async action runs.
struct AsyncButton: View {
    var title: String
    var busyTitle: String?
    var kind = ExpoButtonStyle.Kind.primary
    var compact = false
    var action: () async -> Void
    @State private var busy = false

    var body: some View {
        Button {
            busy = true
            Task { await action(); busy = false }
        } label: {
            HStack(spacing: 6) {
                if busy { ProgressView().controlSize(.small) }
                Text(busy ? (busyTitle ?? title) : title)
            }
        }
        .buttonStyle(.expo(kind, compact: compact))
        .disabled(busy)
    }
}
