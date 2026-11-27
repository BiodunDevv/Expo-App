import SwiftUI

/// Where saved profiles are added, changed and removed.
struct SavedProfilesCard: View {
    @Environment(AppModel.self) private var model
    @State private var editing: SavedProfile?
    @State private var deleting: SavedProfile?

    var body: some View {
        Card(title: "Job and client profiles",
             subtitle: "Expo is given the one marked In use when you start a meeting. Saved on this Mac.",
             icon: "chat") {
            ForEach(model.state.settings.profiles) { profile in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.name).font(.system(size: 12.5, weight: .semibold))
                        Text(profile.details).font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    let inUse = model.state.settings.lastProfileID == profile.id
                    Button { model.updateSettings { $0.lastProfileID = inUse ? nil : profile.id } } label: {
                        if inUse { Label("In use", systemImage: "checkmark") } else { Text("Use") }
                    }
                    .buttonStyle(.expo(inUse ? .primary : .secondary, compact: true))
                    .hint(inUse ? "Stop using this for new meetings" : "Use this for new meetings")
                    Button("Edit") { editing = profile }.buttonStyle(.expo(.secondary, compact: true))
                    Button("Delete") { deleting = profile }.buttonStyle(.expo(.plain, compact: true))
                }
                Hairline()
            }
            if model.state.settings.profiles.count < SavedProfile.limit {
                Button("New profile") { editing = SavedProfile(name: "", details: "") }.buttonStyle(.expo(.secondary))
            }
        }
        .sheet(item: $editing) { ProfileEditor(profile: $0) }
        .confirmationDialog("Delete “\(deleting?.name ?? "")”?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { profile in
            Button("Delete profile", role: .destructive) {
                model.updateSettings { $0.profiles.removeAll { $0.id == profile.id } }
            }
        } message: { _ in
            Text("Past sessions are not affected.")
        }
    }
}
