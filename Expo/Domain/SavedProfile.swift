import Foundation

/// Notes kept for a job, client or kind of meeting, picked when a session starts.
struct SavedProfile: Codable, Identifiable, Hashable, Sendable {
    static let limit = 30
    static let nameLimit = 80

    var id = UUID().uuidString.lowercased()
    var name: String
    var details: String

    /// The profile with its text within bounds, or nil when it lacks a name or notes.
    var cleaned: SavedProfile? {
        var copy = self
        copy.name = String(name.trimmed.prefix(Self.nameLimit))
        copy.details = String(details.trimmed.prefix(MeetingBrief.maxCharacters))
        return copy.name.isEmpty || copy.details.isEmpty ? nil : copy
    }
}

extension [SavedProfile] {
    /// Replaces the profile with the same id, or adds it at the top.
    /// Returns false when it is incomplete or the list is full.
    @discardableResult
    mutating func save(_ profile: SavedProfile) -> Bool {
        guard let profile = profile.cleaned else { return false }
        if let index = firstIndex(where: { $0.id == profile.id }) { self[index] = profile }
        else if count < SavedProfile.limit { insert(profile, at: 0) }
        else { return false }
        return true
    }
}
