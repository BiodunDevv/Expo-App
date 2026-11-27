import SwiftUI
import ThinkingOrbsKit

/// One thing asked for in this session, with its reply.
enum AnswerEntry: Identifiable {
    case answer(AssistantMessage), suggestion(LiveSuggestion)

    var id: String {
        switch self { case .answer(let a): a.id; case .suggestion(let s): s.id }
    }
    var date: String {
        switch self { case .answer(let a): a.createdAt ?? ""; case .suggestion(let s): s.createdAt }
    }
    var text: String? {
        switch self {
        case .answer(let a): a.summary
        case .suggestion(let s): s.text.isEmpty || s.status == "failed" ? nil : s.text
        }
    }
}

extension AppModel {
    /// Everything asked in this session with its reply, oldest first.
    var visibleAnswers: [AnswerEntry] {
        guard let session = assist?.currentSession else { return [] }
        // Only suggestions the person asked for; unasked ones answered every sentence.
        let suggestions = session.liveSuggestions.filter { $0.status != "superseded" && $0.trigger != "automatic" }
        let all = session.assistantMessages.map(AnswerEntry.answer) + suggestions.map(AnswerEntry.suggestion)
        return all.sorted { $0.date < $1.date }
    }

    /// Makes the session window a small "in progress" note.
    func minimizeSession() { layout.minimize(answers: visibleAnswers.count) }
}

/// The whole conversation. It follows the newest answer as it is written, and
/// holds still once the person scrolls up to read.
struct AnswerList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let entries = model.visibleAnswers
        FollowingScroll(jump: model.layout.jumps, count: entries.count) {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(entries) { AnswerRow(entry: $0) }
                PendingAnswer()
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
        }
    }
}

/// One finished question and reply.
private struct AnswerRow: View {
    @Environment(AppModel.self) private var model
    let entry: AnswerEntry

    private var assist: AssistController { model.assist }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch entry {
            case .answer(let message):
                QuestionBubble(text: message.question, screen: message.screenContextUsed == true,
                               picture: assist.screenshots[message.id])
                MarkdownText(text: message.summary)
                AnswerActions(text: message.summary)
            case .suggestion(let suggestion):
                QuestionBubble(text: "What should I say?", screen: false, picture: nil)
                if suggestion.status == "failed" {
                    Text(suggestion.errorMessage ?? "This suggestion could not be completed.").font(.system(size: 12)).foregroundStyle(Theme.danger)
                    AsyncButton(title: "Retry", kind: .secondary, compact: true) { await assist.retrySuggestion(suggestion.id) }
                } else if suggestion.text.isEmpty {
                    ThinkingLabel(text: "Writing a suggestion", state: .composing)
                } else {
                    MarkdownText(text: suggestion.text)
                    AnswerActions(text: suggestion.text)
                }
            }
        }
    }
}

/// The answer being written. Apart from the list, so each new word redraws
/// only this.
private struct PendingAnswer: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let assist = model.assist!
        if let pending = assist.pendingQuestion {
            VStack(alignment: .leading, spacing: 10) {
                QuestionBubble(text: pending, screen: assist.pendingScreen, picture: nil)
                if assist.streamedText.isEmpty { ThinkingLabel() }
                else {
                    MarkdownText(text: assist.streamedText)
                    ThinkingLabel(text: "Writing", state: .composing)
                }
            }
        }
    }
}
