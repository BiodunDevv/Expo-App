import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct ProfileView: View {
    @Environment(AppModel.self) private var model
    @State private var profile = ProfessionalProfile()
    @State private var skills = ""

    var body: some View {
        Page(title: "Professional context", subtitle: "Control what Expo can use when it is relevant.", art: "art-work") {
            Card(title: "Personal information", icon: "profile") {
                HStack { Field(label: "Full name", text: $profile.fullName, disabled: true); Field(label: "Preferred name", text: $profile.preferredName) }
                HStack { Field(label: "Role or title", text: $profile.title); Field(label: "Company", text: $profile.company) }
                HStack { Field(label: "Industry", text: $profile.industry); Field(label: "Years of experience", text: $profile.yearsExperience, digitsOnly: true) }
                Field(label: "Goals", text: $profile.goals, multiline: true)
                Field(label: "Professional summary", text: $profile.summary, multiline: true)
                Field(label: "Skills (comma separated)", text: $skills, multiline: true)
                AsyncButton(title: "Save profile", busyTitle: "Saving…") {
                    var updated = profile
                    updated.skills = OnboardingView.split(skills)
                    if await model.attempt({ try await model.saveProfile(updated) }) { model.notify("Profile saved.") }
                }
            }
            Card(title: "CV / Résumé", icon: "resume") {
                CvReplaceSection()
                ProfileHighlights(profile: model.state.profile)
            }
            SavedProfilesCard()
        }
        .onAppear(perform: load)
        .onChange(of: model.state.cv) { load() }
    }

    private func load() {
        profile = model.state.profile
        skills = profile.skills.joined(separator: ", ")
    }
}
