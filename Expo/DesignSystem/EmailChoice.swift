import SwiftUI

/// Whether a session's notes and transcript are emailed, said the same way
/// everywhere it is asked.
struct EmailChoice: View {
    @Environment(AppModel.self) private var model
    @Binding var isOn: Bool
    var compact = false

    var body: some View {
        let available = model.canEmailNotes
        Toggle(isOn: Binding(get: { isOn && available }, set: { isOn = $0 })) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Email me the notes and transcript").font(.system(size: compact ? 12 : 12.5, weight: .medium))
                if !compact || !available {
                    Text(available ? "Sent to \(model.state.account?.email ?? "your account email") when the session ends."
                                   : "Emailed notes are included from the Starter plan.")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
            }
        }
        .toggleStyle(.checkbox)
        .disabled(!available)
    }
}
