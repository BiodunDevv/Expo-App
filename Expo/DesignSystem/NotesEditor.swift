import SwiftUI

/// A labelled multi-line box for session notes, kept within the server's limit.
struct NotesEditor: View {
    var label: String
    @Binding var text: String
    var height: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.secondary)
            TextEditor(text: $text)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: height)
                .background(Theme.surface, in: .rect(cornerRadius: 15))
                .overlay { RoundedRectangle(cornerRadius: 15).stroke(Theme.border) }
                .accessibilityLabel(label)
                .onChange(of: text) {
                    if text.count > MeetingBrief.maxCharacters { text = String(text.prefix(MeetingBrief.maxCharacters)) }
                }
        }
    }
}
