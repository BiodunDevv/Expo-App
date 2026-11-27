import SwiftUI

struct SessionRow: View {
    var session: ExpoSession
    var detail: String?
    var action: () -> Void
    @State private var hovering = false

    private var tags: [(String, Tag.Tone)] {
        var tags: [(String, Tag.Tone)] = []
        if session.deletedAt != nil { tags.append(("In trash", .danger)) }
        switch (session.status, session.notesStatus) {
        case ("active", _): tags.append(("Live", .accent))
        case ("recovered", _): tags.append(("Interrupted", .warning))
        case (_, "failed"): tags.append(("Notes failed", .danger))
        case ("processing", _), (_, "pending"): tags.append(("Preparing notes", .warning))
        default: if session.notes != nil { tags.append(("Notes ready", .success)) }
        }
        if !session.assistantMessages.isEmpty {
            let count = session.assistantMessages.count
            tags.append(("\(count) answer\(count == 1 ? "" : "s")", .neutral))
        }
        return tags
    }

    var body: some View {
        HStack(spacing: 12) {
            Icon8("chat", size: 30)
            VStack(alignment: .leading, spacing: 4) {
                (Text(PracticeSession.isPractice(session.title) ? "Practice: " : "Meeting: ").foregroundStyle(Theme.secondary)
                    + Text(PracticeSession.name(session.title)).fontWeight(.semibold))
                    .font(.system(size: 13)).lineLimit(1)
                (Text("Started: ").foregroundStyle(Theme.tertiary)
                    + Text("\(ISO.display(session.startedAt)) · \(clock(session.durationSeconds))").foregroundStyle(Theme.secondary))
                    .font(.system(size: 11.5))
                if let detail, !detail.isEmpty {
                    Text(detail).font(.system(size: 11)).foregroundStyle(Theme.tertiary).lineLimit(2)
                }
                if !tags.isEmpty {
                    HStack(spacing: 6) { ForEach(tags, id: \.0) { Tag(text: $0.0, tone: $0.1) } }.padding(.top, 3)
                }
            }
            Spacer(minLength: 8)
            Button(session.deletedAt == nil ? "View session" : "Restore", action: action)
                .buttonStyle(.expo(.secondary, compact: true))
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 8)
        .background(hovering ? Theme.subtle : .clear, in: .rect(cornerRadius: 16))
        .contentShape(.rect)
        .onTapGesture(perform: action)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
