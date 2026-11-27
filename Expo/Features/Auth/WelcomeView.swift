import SwiftUI

/// Shown the first time Expo opens, before there is an account.
struct WelcomeView: View {
    private struct Page {
        var title: String
        var body: String
        var points: [(symbol: String, title: String, detail: String)]
    }

    private static let pages = [
        Page(title: "Meet Expo",
             body: "A copilot that sits beside your meetings, interviews and calls, and helps when you ask.",
             points: [("waveform", "Follows the conversation", "A live transcript, only while Assist is on"),
                      ("sparkles", "Answers in the moment", "Short enough to use while someone is talking"),
                      ("doc.text", "Writes it up", "Notes, decisions and follow-ups afterwards")]),
        Page(title: "How a session works",
             body: "Three steps, and you stay in control of each one.",
             points: [("1.circle", "Start Assist", "Say what the meeting is about, or skip that"),
                      ("2.circle", "Ask with ⌘↩", "Use ⇧⌘↩ to ask about what is on your screen"),
                      ("3.circle", "End Assist", "Your notes are ready in History")]),
        Page(title: "Your screen, your choice",
             body: "Decide whether Expo’s windows appear when you share your screen. You can change this at any time.",
             points: []),
        Page(title: "Ready when you are",
             body: "macOS asks for each permission the first time it is needed.",
             points: [("speaker.wave.2", "Computer audio", "To hear the other people on the call"),
                      ("mic", "Microphone", "To include what you say. You can turn it off"),
                      ("rectangle.on.rectangle", "Screen recording", "Only if you ask about your screen")]),
    ]

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var forward = true

    private var page: Page { Self.pages[index] }
    private var isLast: Bool { index == Self.pages.count - 1 }

    var body: some View {
        HStack(spacing: 0) {
            artwork
                .frame(width: 330)
                .frame(maxHeight: .infinity)
                .background(Theme.sidebar)
            Rectangle().fill(Theme.border).frame(width: 1)
            content
        }
    }

    private var artwork: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Logo(size: 24)
                Text("Expo").font(.system(size: 14, weight: .bold))
                Spacer()
            }
            ZStack {
                switch index {
                case 0: LoopingAnimation(name: "auth-hero")
                case 1: shortcutArt
                case 2: Image(model.capturePrivacy.isHidden ? "privacy-hidden" : "privacy-visible")
                        .resizable().scaledToFit().frame(width: 150, height: 150)
                        .id(model.capturePrivacy.isHidden)
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                default: Logo(size: 132)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(index == 2 ? 2 : index)
            .transition(.opacity)
            .animation(.snappy(duration: 0.25), value: model.capturePrivacy)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 24)
        .padding(.top, 40)
        .padding(.bottom, 24)
    }

    /// The two shortcuts, drawn as keys.
    private var shortcutArt: some View {
        VStack(spacing: 18) {
            keys(["⌘", "↩"], "Ask Expo")
            keys(["⇧", "⌘", "↩"], "Ask about your screen")
        }
    }

    private func keys(_ symbols: [String], _ caption: String) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(symbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 22, weight: .medium))
                        .frame(width: 54, height: 52)
                        .background(Theme.surface, in: .rect(cornerRadius: 17))
                        .overlay { RoundedRectangle(cornerRadius: 17).strokeBorder(Theme.border) }
                        .shadow(color: .black.opacity(0.08), radius: 0, y: 3)
                }
            }
            Text(caption).font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                if !isLast { Button("Skip") { finish(register: false) }.buttonStyle(.expo(.plain, compact: true)) }
            }
            .frame(height: 30)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(page.title).font(.system(size: 22, weight: .bold)).accessibilityAddTraits(.isHeader)
                    Text(page.body).font(.system(size: 12.5)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(page.points, id: \.title) { point in
                    HStack(alignment: .top, spacing: 11) {
                        Image(systemName: point.symbol)
                            .font(.system(size: 13))
                            .frame(width: 30, height: 30)
                            .background(Theme.subtle, in: .rect(cornerRadius: 13))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(point.title).font(.system(size: 12.5, weight: .semibold))
                            Text(point.detail).font(.system(size: 11.5)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                if index == 2 {
                    PrivacyRow()
                    Text("macOS treats this as a request. Check what your meeting app shows before you rely on it.")
                        .font(.system(size: 11)).foregroundStyle(Theme.tertiary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .id(index)
            .transition(reduceMotion ? .opacity : .asymmetric(
                insertion: .offset(x: forward ? 24 : -24).combined(with: .opacity), removal: .opacity))
            Spacer(minLength: 0)
            footer
        }
        .padding(.horizontal, 36)
        .padding(.top, 16)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if isLast {
                Button { finish(register: true) } label: { Text("Create account").frame(maxWidth: .infinity) }
                    .buttonStyle(.expo).keyboardShortcut(.defaultAction)
                Button { finish(register: false) } label: { Text("I already have an account").frame(maxWidth: .infinity) }
                    .buttonStyle(.expo(.secondary))
            }
            HStack {
                Button("Back") { move(-1) }.buttonStyle(.expo(.secondary, compact: true))
                    .opacity(index == 0 ? 0 : 1).disabled(index == 0)
                Spacer()
                HStack(spacing: 6) {
                    ForEach(Self.pages.indices, id: \.self) { dot in
                        Capsule().fill(dot == index ? Theme.accent : Theme.border).frame(width: dot == index ? 18 : 6, height: 6)
                    }
                }
                .accessibilityElement()
                .accessibilityLabel("Page \(index + 1) of \(Self.pages.count)")
                Spacer()
                Button("Next") { move(1) }.buttonStyle(.expo(.primary, compact: true))
                    .keyboardShortcut(isLast ? nil : .defaultAction)
                    .opacity(isLast ? 0 : 1).disabled(isLast)
            }
        }
    }

    private func move(_ step: Int) {
        forward = step > 0
        withAnimation(.snappy(duration: 0.3)) { index = min(Self.pages.count - 1, max(0, index + step)) }
    }

    private func finish(register: Bool) {
        model.finishWelcome(register: register)
    }
}
