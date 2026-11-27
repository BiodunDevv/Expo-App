import SwiftUI

private struct Hint: ViewModifier {
    @Environment(AppModel.self) private var model
    var text: String

    func body(content: Content) -> some View {
        if model.capturePrivacy.isHidden { content.accessibilityHint(text) }
        else { content.help(text) }
    }
}

extension View {
    /// A tooltip in Expo's floating windows. A tooltip is a window of its own,
    /// so none is shown while Expo is hidden from screen sharing.
    func hint(_ text: String) -> some View { modifier(Hint(text: text)) }
}
