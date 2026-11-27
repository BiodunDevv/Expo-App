import SwiftUI
import UniformTypeIdentifiers

/// Replace or add the CV. Nothing the assistant uses changes until approval.
struct CvReplaceSection: View {
    @Environment(AppModel.self) private var model
    @State private var picking = false
    @State private var confirmReplace = false
    @State private var confirmRemove = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let cv = model.state.cv {
                Label("\(cv.name) · added \(ISO.date(cv.uploadedAt)?.formatted(date: .abbreviated, time: .omitted) ?? "")", systemImage: "doc.text")
                    .font(.system(size: 12))
            } else {
                Text("No CV added. Add one to improve career-related suggestions.").font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
            HStack {
                Button(model.cvBusy ? "Reading your CV…" : model.state.cv == nil ? "Add a CV" : "Replace CV") {
                    if model.state.cv == nil { picking = true } else { confirmReplace = true }
                }
                .buttonStyle(.expo(.secondary, compact: true))
                .disabled(!model.state.consent.cvProcessing.granted || model.cvBusy)
                if model.cvBusy { ProgressView().controlSize(.small) }
                if model.state.cv != nil {
                    Button("Remove CV") { confirmRemove = true }.buttonStyle(.expo(.plain, compact: true)).disabled(model.cvBusy)
                }
                if !model.state.consent.cvProcessing.granted {
                    Text("Give CV processing consent in Settings first.").font(.system(size: 12)).foregroundStyle(Theme.warning)
                }
            }
            if let pending = model.state.pendingCvReplacement { review(pending) }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.pdf, UTType(filenameExtension: "docx") ?? .data]) { result in
            guard case .success(let url) = result else { return }
            Task { _ = await model.attempt { try await model.replaceCv(url) } }
        }
        .confirmationDialog("Replace your CV?", isPresented: $confirmReplace) {
            Button("Choose new CV") { picking = true }
        } message: {
            Text("Expo will read the new CV and show you what it found. Nothing changes until you approve it.")
        }
        .confirmationDialog("Remove this CV?", isPresented: $confirmRemove) {
            Button("Remove CV", role: .destructive) { Task { _ = await model.attempt { try await model.removeCv() } } }
        } message: {
            Text("Expo will delete the uploaded CV only. Your editable profile fields will stay.")
        }
    }

    private func review(_ pending: PendingCvReplacement) -> some View {
        let found = pending.profile
        let rows = [
            ("Headline", found.title),
            ("Experience", found.yearsExperience.isEmpty ? "" : "\(found.yearsExperience) years"),
            ("Summary", found.summary),
            ("Skills", found.skills.prefix(15).joined(separator: ", ")),
            ("Roles", found.roles.isEmpty ? "" : "\(found.roles.count) found"),
        ].filter { !$0.1.isEmpty }
        return VStack(alignment: .leading, spacing: 8) {
            Text("New CV ready to review: \(pending.cv.name)").font(.system(size: 12.5, weight: .bold))
            Text("Expo is still using your previous CV. If you don’t approve this one, Expo keeps answering from the old one.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
            ForEach(rows, id: \.0) { row in
                HStack(alignment: .firstTextBaseline) {
                    Text(row.0).font(.system(size: 11.5, weight: .semibold)).frame(width: 80, alignment: .leading)
                    Text(row.1).font(.system(size: 11.5)).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                AsyncButton(title: "Use this CV", busyTitle: "Switching…", compact: true) {
                    if await model.attempt({ try await model.approveCvReplacement() }) { model.notify("Expo is now using your new CV.") }
                }
                AsyncButton(title: "Keep my current CV", busyTitle: "Removing…", kind: .secondary, compact: true) {
                    await model.discardCvReplacement()
                    model.notify("Kept your current CV.")
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accentSoft, in: .rect(cornerRadius: 18))
    }
}
