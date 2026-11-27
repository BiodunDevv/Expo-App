import SwiftUI

/// The answer style and language level, as used in Settings and onboarding.
struct AnswerSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Answer style", selection: Binding(
                get: { model.state.settings.answerStyle },
                set: { value in model.updateSettings { $0.answerStyle = value } })) {
                ForEach(AnswerStyle.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(model.state.settings.answerStyle.detail).font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
            Hairline()
            ToggleRow(title: "Simple English", detail: "Everyday words and short sentences.", isOn: Binding(
                get: { model.state.settings.plainEnglish },
                set: { value in model.updateSettings { $0.plainEnglish = value } }))
        }
    }
}
