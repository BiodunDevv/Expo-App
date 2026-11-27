import SwiftUI

/// How a finished practice went: speaking numbers, feedback and each reply
/// beside the answer Expo suggested.
struct PracticeReviewCard: View {
    @Environment(AppModel.self) private var model
    var session: ExpoSession
    @State private var draft = ""
    @State private var coaching = false
    @State private var message = ""
    @State private var showAll = false

    private var feedback: String { coaching ? draft : model.state.practiceReviews?[session.id] ?? "" }

    var body: some View {
        let review = PracticeReview(session: session)
        let timing = model.state.speechTimings?[session.id]
        Card(title: "Practice review", subtitle: "Based on what your microphone heard.", icon: "practice") {
            if review.wordCount == 0 {
                Text("Nothing from your microphone was transcribed in this session, so there is nothing to review.")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
            } else {
                HStack(alignment: .top, spacing: 10) {
                    figure("\(review.wordCount)", "Words you said", "Includes questions you asked aloud")
                    figure(timing?.wordsPerMinute.map { "\($0)" } ?? "–", "Words a minute",
                           timing?.paceNote ?? "Not enough timed speech")
                    figure("\(review.fillerCount)", "Filler phrases",
                           review.fillers.isEmpty ? "None noticed" : review.fillers.prefix(3).map { "“\($0.phrase)” \($0.count)" }.joined(separator: ", "))
                }
                Text("Transcription often leaves out “um” and “uh”, so the filler count can be low.")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.tertiary)
                Hairline()
                if !feedback.isEmpty { MarkdownText(text: feedback) }
                if !message.isEmpty { Text(message).font(.system(size: 12)).foregroundStyle(Theme.danger).fixedSize(horizontal: false, vertical: true) }
                HStack(spacing: 8) {
                    Button(coaching ? "Writing feedback…" : feedback.isEmpty ? "Get feedback" : "Refresh feedback", action: coach)
                        .buttonStyle(.expo(feedback.isEmpty ? .primary : .secondary))
                        .disabled(coaching || session.status != "complete")
                    Text(session.status == "complete" ? "Counts as one answer." : "Available once the session has finished saving.")
                        .font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                }
                if !review.exchanges.isEmpty {
                    Hairline()
                    Text("Your replies beside Expo’s").font(.system(size: 12.5, weight: .bold))
                    ForEach(showAll ? review.exchanges : Array(review.exchanges.prefix(3))) { exchange in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(exchange.question).font(.system(size: 12, weight: .semibold)).lineLimit(3)
                            HStack(alignment: .top, spacing: 10) {
                                side("You said") { Text(exchange.reply).font(.system(size: 12)).textSelection(.enabled) }
                                side("Suggested") { MarkdownText(text: exchange.suggested) }
                            }
                        }
                    }
                    if review.exchanges.count > 3 {
                        Button(showAll ? "Show fewer" : "Show all \(review.exchanges.count)") { showAll.toggle() }
                            .buttonStyle(.expo(.plain, compact: true))
                    }
                }
            }
        }
    }

    private func figure(_ value: String, _ title: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.system(size: 24, weight: .bold)).monospacedDigit()
            Text(title).font(.system(size: 11.5, weight: .semibold))
            Text(note).font(.system(size: 10.5)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.subtle, in: .rect(cornerRadius: 17))
        .accessibilityElement(children: .combine)
    }

    private func side(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 10.5, weight: .bold)).foregroundStyle(Theme.tertiary)
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.subtle, in: .rect(cornerRadius: 16))
    }

    private func coach() {
        coaching = true
        draft = ""
        message = ""
        Task {
            do {
                try await model.coachPractice(session.id) { delta in
                    await MainActor.run { draft += delta }
                }
            } catch {
                message = userMessage(error, fallback: "Expo couldn't write feedback. Please try again.")
            }
            coaching = false
        }
    }
}
