import SwiftUI

struct Field: View {
    var label: String
    @Binding var text: String
    var secure = false
    var multiline = false
    var disabled = false
    var digitsOnly = false
    @State private var revealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.secondary)
            HStack {
                if secure && !revealed { SecureField("", text: $text) }
                else if multiline { TextField("", text: $text, axis: .vertical).lineLimit(3...8) }
                else { TextField("", text: $text) }
                if secure {
                    Button { revealed.toggle() } label: { Image(systemName: revealed ? "eye.slash" : "eye") }
                        .buttonStyle(.plain).foregroundStyle(Theme.tertiary)
                        .accessibilityLabel(revealed ? "Hide password" : "Show password")
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 12.5))
            .padding(.horizontal, 9)
            .padding(.vertical, 6.5)
            .background(disabled ? Theme.subtle : Theme.surface, in: .rect(cornerRadius: 15))
            .overlay { RoundedRectangle(cornerRadius: 15).stroke(Theme.border) }
            .disabled(disabled)
            .accessibilityLabel(label)
            .onChange(of: text) {
                guard digitsOnly else { return }
                let digits = text.filter { $0.isASCII && $0.isNumber }
                if digits != text { text = digits }
            }
            if digitsOnly { Text(YearsRule.hint).font(.system(size: 10.5)).foregroundStyle(Theme.tertiary) }
        }
    }
}

struct ToggleRow: View {
    var title: String
    var detail: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11.5)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
    }
}
