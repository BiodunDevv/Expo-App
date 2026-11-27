import SwiftUI
import ThinkingOrbsKit

/// The latest answer, sized to be read at a glance during a conversation.
struct GlanceCard: View {
    @Environment(AppModel.self) private var model
    /// The answer text to condense; nil before anything has been asked.
    var answer: String?
    var streaming: Bool
    var showFull: () -> Void

    private var assist: AssistController { model.assist }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let answer, !answer.isEmpty {
                let glance = Glance(answer)
                ScrollView {
                    VStack(alignment: .leading, spacing: 9) {
                        Text(glance.headline)
                            .font(.system(size: glance.headline.count > 70 ? 14.5 : 17, weight: .bold))
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(Array(glance.points.enumerated()), id: \.offset) { _, point in
                            HStack(alignment: .firstTextBaseline, spacing: 9) {
                                Circle().fill(Theme.tertiary).frame(width: 5, height: 5).offset(y: -2)
                                Text(point).font(.system(size: 13.5)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                }
                .scrollBounceBehavior(.basedOnSize)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    ForEach(Refinement.allCases) { refinement in
                        Button(refinement.rawValue) {
                            assist.submit(refinement.prompt(for: answer), label: "\(refinement.rawValue) version")
                        }
                        .buttonStyle(.expo(.secondary, compact: true))
                        .disabled(assist.isAsking)
                        .fixedSize()
                    }
                    Spacer(minLength: 4)
                    if streaming { ThinkingOrb(state: .composing, size: .px20) }
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(answer, forType: .string)
                    } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.expo(.plain, compact: true))
                        .hint("Copy the full answer").accessibilityLabel("Copy answer")
                    Button("Full answer", action: showFull)
                        .buttonStyle(.expo(.plain, compact: true))
                        .fixedSize()
                }
            } else if streaming || assist.isAsking {
                Spacer()
                VStack(spacing: 10) {
                    ThinkingOrb(state: .searching, size: .px64)
                    Text("Thinking…").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.secondary)
                }
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                Spacer()
                VStack(spacing: 8) {
                    Text("Nothing to show yet").font(.system(size: 14, weight: .semibold))
                    Button("What should I say?") { model.layout.asked(); Task { await assist.suggest() } }.buttonStyle(.expo(.primary, compact: true))
                }
                .frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
