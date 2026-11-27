import SwiftUI

/// Short rows under the input, only while they apply: what will be captured, a
/// listening problem, an error, or a used-up allowance.
struct SessionNotices: View {
    @Environment(AppModel.self) private var model
    @Bindable var composer: Composer

    private var assist: AssistController { model.assist }
    private var snapshot: AssistSnapshot { assist.snapshot }

    var body: some View {
        VStack(spacing: 0) {
            if composer.capturing { CaptureRow(composer: composer) }
            if let problem { row("exclamationmark.triangle.fill", Theme.warning, problem.message) { problem.fix } }
            if let toast = model.toasts.last {
                row(toast.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill", toast.isError ? Theme.danger : Theme.success, toast.message) {
                    HStack(spacing: 6) {
                        if toast.offersPlans { Button("See plans") { model.openSettings() }.buttonStyle(ChipStyle()) }
                        Button { model.toasts.removeAll { $0.id == toast.id } } label: { Image(systemName: "xmark") }
                            .buttonStyle(.plain).foregroundStyle(Theme.secondary).accessibilityLabel("Dismiss")
                    }
                }
            }
            if model.billing?.answersUsedUp == true {
                row("lock.fill", Theme.warning, "Smart answers paused: your monthly answers are used up.") { EmptyView() }
            }
        }
    }

    private var problem: (message: String, fix: AnyView)? {
        if snapshot.lifecycle == .paused {
            return ("Listening is paused.", fix("Resume") { await model.resumeAssist() })
        }
        let broken = snapshot.lifecycle == .error || snapshot.connection == .offline || snapshot.audio == .unavailable || snapshot.audio == .denied
        guard broken else {
            return snapshot.connection == .reconnecting ? ("Reconnecting…", AnyView(EmptyView())) : nil
        }
        return (snapshot.error ?? "Expo is not hearing audio.", fix("Retry") { await assist.retryListening() })
    }

    private func fix(_ title: String, _ action: @escaping () async -> Void) -> AnyView {
        AnyView(AsyncButton(title: title, kind: .secondary, compact: true) { await action() })
    }

    private func row(_ symbol: String, _ colour: Color, _ message: String, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).foregroundStyle(colour)
            Text(message).font(.system(size: 11.5)).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            trailing()
        }
        .padding(.horizontal, 14).padding(.vertical, 7)
        .background(Color.white.opacity(0.05))
    }
}

/// What will be captured. Its own view, so the session clock never redraws the
/// open list.
private struct CaptureRow: View {
    @Bindable var composer: Composer

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                Button("Entire screen") { composer.sourceID = nil }
                let displays = composer.sources.filter { $0.kind == .display }.count
                let others = composer.sources.filter { $0.kind == .window || displays > 1 }
                if !others.isEmpty {
                    Divider()
                    ForEach(others) { item in Button(item.name) { composer.sourceID = item.id } }
                }
                Divider()
                Button("Refresh list") { Task { await composer.loadSources(prompt: true) } }
            } label: {
                Label(composer.source?.name ?? "Entire screen", systemImage: composer.source?.kind == .window ? "macwindow" : "display").lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .font(.system(size: 11.5, weight: .medium))
            .frame(maxWidth: 220)
            .fixedSize()
            .accessibilityLabel("What to capture")
            Text("Press return to capture and answer")
                .font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(1)
            Spacer(minLength: 0)
            Button { composer.setCapturing(false) } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).foregroundStyle(Theme.secondary).accessibilityLabel("Turn screen capture off")
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Color.white.opacity(0.05))
    }
}
