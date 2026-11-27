import SwiftUI

/// Fills a session's notes from a saved profile, and saves them back.
struct SavedProfilePicker: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: String?
    @Binding var notes: String
    /// Offered as the name of a new profile.
    var suggestedName = ""
    var onPick: (SavedProfile) -> Void = { _ in }
    @State private var editing: SavedProfile?

    private var profiles: [SavedProfile] { model.state.settings.profiles }
    private var chosen: SavedProfile? { profiles.first { $0.id == selection } }

    var body: some View {
        HStack(spacing: 8) {
            if !profiles.isEmpty {
                Picker("Saved profile", selection: Binding(get: { chosen?.id }, set: choose)) {
                    Text("None").tag(String?.none)
                    ForEach(profiles) { Text($0.name).tag(String?.some($0.id)) }
                }
                .font(.system(size: 12))
                .frame(maxWidth: 260)
            }
            Spacer(minLength: 0)
            if let chosen, chosen.details != notes.trimmed, !notes.trimmed.isEmpty {
                Button("Update profile") {
                    var updated = chosen
                    updated.details = notes
                    model.updateSettings { $0.profiles.save(updated) }
                }
                .buttonStyle(.expo(.plain, compact: true))
            }
            if !notes.trimmed.isEmpty && chosen?.details != notes.trimmed && profiles.count < SavedProfile.limit {
                Button("Save as new profile") { editing = SavedProfile(name: suggestedName, details: notes) }
                    .buttonStyle(.expo(.plain, compact: true))
            }
        }
        .sheet(item: $editing) { profile in
            ProfileEditor(profile: profile) { saved in
                selection = saved.id
                notes = saved.details
            }
        }
    }

    private func choose(_ id: String?) {
        let previous = chosen
        selection = id
        guard let profile = profiles.first(where: { $0.id == id }) else {
            // Notes the person changed or typed are theirs to keep.
            if notes == previous?.details { notes = "" }
            return
        }
        notes = profile.details
        onPick(profile)
    }
}

/// Names a profile and edits its notes.
struct ProfileEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var profile: SavedProfile
    var onSave: (SavedProfile) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Job or client profile").font(.system(size: 17, weight: .bold))
            Field(label: "Name, such as “Frontend role at Acme”", text: $profile.name)
            NotesEditor(label: "Job description, client background, goals and your talking points", text: $profile.details, height: 180)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.expo(.secondary)).keyboardShortcut(.cancelAction)
                Button("Save") {
                    guard let saved = profile.cleaned else { return }
                    model.updateSettings { $0.profiles.save(saved) }
                    onSave(saved)
                    dismiss()
                }
                .buttonStyle(.expo)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(profile.cleaned == nil)
            }
        }
        .padding(22)
        .frame(width: 460)
        .background(Theme.background)
    }
}
