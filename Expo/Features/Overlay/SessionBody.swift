import SwiftUI

/// Under the input: the answers, or the transcript while only saving it.
struct SessionBody: View {
    @Environment(AppModel.self) private var model

    private var assist: AssistController { model.assist }

    var body: some View {
        let nothingAsked = model.visibleAnswers.isEmpty && assist.pendingQuestion == nil
        VStack(spacing: 0) {
            if model.glanceMode {
                GlanceCard(answer: latest, streaming: assist.pendingQuestion != nil) { model.glanceMode = false }
            } else if !assist.autoAnswer {
                pages
                if model.showingTranscript { LiveTranscript() } else if nothingAsked { SessionEmptyState() } else { AnswerList() }
            } else if nothingAsked {
                SessionEmptyState()
            } else {
                AnswerList()
            }
        }
    }

    private var pages: some View {
        HStack(spacing: 4) {
            ForEach([(true, "Transcript"), (false, "Chat")], id: \.1) { transcript, title in
                Button(title) { model.showingTranscript = transcript }
                    .buttonStyle(ChipStyle(on: model.showingTranscript == transcript))
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.top, 9)
    }

    /// The streaming answer, otherwise the newest finished answer or suggestion.
    private var latest: String? {
        if assist.pendingQuestion != nil { return assist.streamedText }
        return model.visibleAnswers.reversed().lazy.compactMap(\.text).first
    }
}
