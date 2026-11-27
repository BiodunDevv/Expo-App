import Foundation

// Wire and storage models. Names mirror the backend JSON exactly.

enum AssistLifecycle: String, Codable, Sendable {
    case idle, preparing, connecting, listening, paused, ending
    case generatingNotes = "generating-notes"
    case completed, error
}

enum LinkState: String, Codable, Sendable { case connected, reconnecting, offline }
enum AudioState: String, Codable, Sendable { case unknown, ready, silent, unavailable, denied }
enum AudioCaptureMode: String, Codable, Sendable {
    case allSystemOutput = "all-system-output"
    case selectedApplication = "selected-application"
}

struct AssistSnapshot: Equatable, Sendable {
    var lifecycle: AssistLifecycle = .idle
    var connection: LinkState = .connected
    var audio: AudioState = .unknown
    var elapsedSeconds = 0
    var sessionId: String?
    var error: String?
    var recoveryAttempt: Int?
    var recoveryMaxAttempts: Int?
}

extension KeyedDecodingContainer {
    /// Decodes a value, falling back when it is absent so older data keeps loading.
    func value<T: Decodable>(_ key: Key, _ fallback: T) throws -> T {
        try decodeIfPresent(T.self, forKey: key) ?? fallback
    }
}

// MARK: Profile

struct WorkExperience: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var role: String
    var company: String
    var period: String
    var summary: String?
}

struct Education: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var school: String
    var qualification: String
    var period: String?
}

struct Project: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var summary: String
}

struct ProfessionalProfile: Codable, Hashable, Sendable {
    var fullName = ""
    var preferredName = ""
    var title = ""
    var company = ""
    var industry = ""
    var yearsExperience = ""
    var goals = ""
    var bio = ""
    var summary = ""
    var skills: [String] = []
    var roles: [WorkExperience] = []
    var education: [Education] = []
    var projects: [Project] = []
    var certifications: [String] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fullName = try c.value(.fullName, "")
        preferredName = try c.value(.preferredName, "")
        title = try c.value(.title, "")
        company = try c.value(.company, "")
        industry = try c.value(.industry, "")
        yearsExperience = try c.value(.yearsExperience, "")
        goals = try c.value(.goals, "")
        bio = try c.value(.bio, "")
        summary = try c.value(.summary, "")
        skills = try c.value(.skills, [])
        roles = try c.value(.roles, [])
        education = try c.value(.education, [])
        projects = try c.value(.projects, [])
        certifications = try c.value(.certifications, [])
    }
}

struct ConsentRecord: Codable, Hashable, Sendable {
    var granted = false
    var grantedAt: String?
    var revokedAt: String?
}

struct ConsentState: Codable, Hashable, Sendable {
    var cvProcessing = ConsentRecord()
    var transcriptCapture = ConsentRecord()
}

struct CvMetadata: Codable, Hashable, Sendable {
    var uploadId: String?
    var name: String
    var size: Int
    var type: String
    var uploadedAt: String
}

/// A new CV that is uploaded and read but not yet approved.
struct PendingCvReplacement: Codable, Hashable, Sendable {
    var cv: CvMetadata
    var profile: ProfessionalProfile
}

struct OnboardingDraft: Codable, Hashable, Sendable {
    var step = 0
    var profile = ProfessionalProfile()
    var cvUploadId: String?
    var cvName: String?
    var cvStatus: String?
    var pendingFilePath: String?
    var idempotencyKey: String?
    var remoteRevision: Int?
    var updatedAt: String = ISO.now()
}

// MARK: Sessions

struct TranscriptSegment: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var at: String
    var speaker: String
    var text: String
    var confidence: String
    var source: String?
    var channelIndex: Int?
}

struct ActionItem: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var text: String
    var owner: String
    var due: String
    var done: Bool
}

struct SessionNotes: Codable, Hashable, Sendable {
    var overview: String
    var decisions: [String]
    var actions: [ActionItem]
    var keyPoints: [String]
    var openQuestions: [String]
    var followUp: String
}

struct AssistantMessage: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var question: String
    var summary: String
    var suggestedResponse: String?
    var references: [String]
    var confidence: String
    var createdAt: String?
    var screenContextUsed: Bool?
}

struct LiveSuggestion: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var sessionId: String
    var trigger: String
    var sourceTurnId: String?
    var contextVersion: Int
    var reason: String?
    var instruction: String?
    var status: String
    var text: String
    var offset: Int
    var createdAt: String
    var updatedAt: String
    var errorCode: String?
    var errorMessage: String?
}

struct ExpoSession: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var startedAt: String
    var endedAt: String?
    var durationSeconds = 0
    /// active | processing | complete | recovered
    var status: String
    var transcript: [TranscriptSegment] = []
    var transcriptCursor: String?
    var assistantMessages: [AssistantMessage] = []
    var liveSuggestions: [LiveSuggestion] = []
    var notes: SessionNotes?
    /// pending | ready | failed
    var notesStatus: String?
    var notesError: String?
    var deletedAt: String?
    var contextVersion: Int?
    var profileContextEnabled: Bool?
    var prepNotes: String?
    /// Whether the notes and transcript are emailed when the session ends.
    var emailNotes: Bool?
}

struct ExpoSettings: Codable, Hashable, Sendable {
    var launchAtLogin = false
    var openMaximized = false
    var minimizeOnStart = true
    var answerStyle = AnswerStyle.standard
    var plainEnglish = false
    var seeThrough = SeeThrough.clear
    /// The choice a new session starts with.
    var emailNotes = true
    var useCvContext = true
    var warnOnSilence = true
    var autoAnswer = true
    var listenOnly = false
    /// Also answer questions heard on the person's own microphone.
    var answerOwnQuestions = true
    var audioCaptureMode = AudioCaptureMode.allSystemOutput
    var captureMicrophone = true
    var audioSourceBundleID: String?
    var audioSourceName: String?
    var profiles: [SavedProfile] = []
    /// The profile used last, pre-selected for the next session.
    var lastProfileID: String?
    var uiZoom = 1.0

    private enum LegacyKeys: String, CodingKey { case savedBrief }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        launchAtLogin = try c.value(.launchAtLogin, false)
        openMaximized = try c.value(.openMaximized, false)
        minimizeOnStart = try c.value(.minimizeOnStart, true)
        answerStyle = AnswerStyle(rawValue: try c.value(.answerStyle, "")) ?? .standard
        plainEnglish = try c.value(.plainEnglish, false)
        emailNotes = try c.value(.emailNotes, true)
        seeThrough = SeeThrough(rawValue: try c.value(.seeThrough, "")) ?? .clear
        useCvContext = try c.value(.useCvContext, true)
        warnOnSilence = try c.value(.warnOnSilence, true)
        autoAnswer = try c.value(.autoAnswer, true)
        listenOnly = try c.value(.listenOnly, false)
        answerOwnQuestions = try c.value(.answerOwnQuestions, true)
        audioCaptureMode = try c.value(.audioCaptureMode, .allSystemOutput)
        captureMicrophone = try c.value(.captureMicrophone, true)
        audioSourceBundleID = try c.decodeIfPresent(String.self, forKey: .audioSourceBundleID)
        audioSourceName = try c.decodeIfPresent(String.self, forKey: .audioSourceName)
        profiles = try c.value(.profiles, [])
        lastProfileID = try c.decodeIfPresent(String.self, forKey: .lastProfileID)
        // The single remembered brief of earlier versions becomes the first profile.
        let old = try decoder.container(keyedBy: LegacyKeys.self).value(.savedBrief, "")
        if profiles.isEmpty, profiles.save(SavedProfile(name: "My meetings", details: old)) { lastProfileID = profiles[0].id }
        uiZoom = try c.value(.uiZoom, 1.0)
    }
}

struct UserAccount: Codable, Hashable, Sendable {
    var id: String
    var email: String
    var firstName: String
    var lastName: String
    var fullName: String { "\(firstName) \(lastName)".trimmed }
}

struct PersistedState: Codable, Sendable {
    var version = 1
    var account: UserAccount?
    var authenticated = false
    var onboardingComplete = false
    var onboardingDraft: OnboardingDraft?
    var profile = ProfessionalProfile()
    var cv: CvMetadata?
    var pendingCvReplacement: PendingCvReplacement?
    var consent = ConsentState()
    var settings = ExpoSettings()
    var sessions: [ExpoSession] = []
    var activeSessionId: String?
    /// Last answer from the plan and admin setting; nil until the backend has said.
    var screenHidingAllowed: Bool?
    /// Speaking time and AI feedback for practice sessions, kept on this Mac.
    var speechTimings: [String: SpeechTiming]?
    var practiceReviews: [String: String]?
}

/// Whether Expo's windows appear in screenshots, recordings and screen shares.
enum CapturePrivacy: Equatable, Sendable {
    case hidden, visible
    /// The plan or administrator does not allow hiding, so Expo is visible.
    case unavailable

    /// The person's choice applies unless the account is not allowed to hide.
    static func resolve(prefersHidden: Bool, allowed: Bool?) -> CapturePrivacy {
        if allowed == false { return .unavailable }
        return prefersHidden ? .hidden : .visible
    }

    var isHidden: Bool { self == .hidden }
    var title: String { isHidden ? "Hidden" : "Visible" }
    var detail: String {
        switch self {
        case .hidden: "Hidden from screen sharing"
        case .visible: "Visible in screen shares"
        case .unavailable: "Visible in screen shares. Hiding is not available on this account."
        }
    }
}

// MARK: Billing

struct BillingSummary: Decodable, Sendable, Equatable {
    struct Usage: Decodable, Sendable, Equatable {
        var answersUsed: Int
        var answersLimit: Int
        var notesUsed: Int
        var notesLimit: Int?
    }
    struct Features: Decodable, Sendable, Equatable { var autoAnswer: Bool? }
    var features: Features?
    var plan: String
    var enforced: Bool?
    var periodEnd: String?
    var usage: Usage?

    /// The server emails notes only on paid plans.
    var emailsNotes: Bool { plan != "free" }
    var smartAnswersLocked: Bool { enforced == true && features?.autoAnswer == false }
    var answersUsedUp: Bool {
        guard enforced == true, features?.autoAnswer == true, let usage else { return false }
        return usage.answersUsed >= usage.answersLimit
    }
}

struct PlanCard: Identifiable, Sendable {
    let id: String
    let name: String
    let monthly: Int
    let yearly: Int
    let points: [String]

    static let all = [
        PlanCard(id: "free", name: "Free", monthly: 0, yearly: 0, points: ["30 AI answers a month", "Live transcript and notes", "Personalise with your CV"]),
        PlanCard(id: "starter", name: "Starter", monthly: 30_000, yearly: 300_000, points: ["200 answers a month", "Screen questions", "Listen-only mode", "5 emailed meeting notes"]),
        PlanCard(id: "pro", name: "Pro", monthly: 67_500, yearly: 675_000, points: ["Hidden from screen sharing", "500 answers a month", "Smart answers, or pause in one click", "Unlimited emailed notes"]),
        PlanCard(id: "max", name: "Max", monthly: 105_000, yearly: 1_050_000, points: ["Hidden from screen sharing", "1,000 answers a month", "Long-term memory", "Everything in Pro"]),
    ]
}

// MARK: Dates

enum ISO {
    static func now() -> String { string(Date()) }
    static func string(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }
    static func date(_ text: String) -> Date? {
        (try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
            ?? (try? Date(text, strategy: Date.ISO8601FormatStyle()))
    }
    static func display(_ text: String) -> String {
        date(text)?.formatted(date: .abbreviated, time: .shortened) ?? text
    }
}

func clock(_ seconds: Int) -> String {
    String(format: "%02d:%02d", seconds / 60, seconds % 60)
}

/// Speakers leak into the microphone, so the same words arrive on both channels.
enum MicrophoneEcho {
    static let hold = Duration.milliseconds(1_200)

    static func matches(_ segment: TranscriptSegment, in transcript: some Sequence<TranscriptSegment>) -> Bool {
        func words(_ text: String) -> Set<String> {
            Set(text.lowercased().filter { $0.isLetter || $0.isNumber || $0.isWhitespace }.split(whereSeparator: \.isWhitespace).map(String.init))
        }
        func seconds(_ at: String) -> Int { at.split(separator: ":").reduce(0) { $0 * 60 + (Int($1) ?? 0) } }
        guard segment.speaker == "You" else { return false }
        let heard = words(segment.text)
        guard !heard.isEmpty else { return false }
        // Only the person's words that the meeting also said, moments around
        // them, count as an echo. A short meeting line such as "I know" must not
        // remove a longer sentence that happens to contain it.
        let nearby = transcript.filter { $0.speaker == "Meeting" && abs(seconds($0.at) - seconds(segment.at)) <= 8 }
        guard !nearby.isEmpty else { return false }
        if heard.count < 3 { return nearby.contains { words($0.text) == heard } }
        let said = nearby.reduce(into: Set<String>()) { $0.formUnion(words($1.text)) }
        return Double(heard.intersection(said).count) / Double(heard.count) >= 0.75
    }
}

func isBackendID(_ value: String) -> Bool { UUID(uuidString: value) != nil }

enum MeetingBrief {
    /// Longest brief the backend accepts; room for a pasted job description.
    static let maxCharacters = 12_000
}

/// Main window zoom steps, 1 being the normal size.
enum UIZoom {
    static let steps = [0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2]
    static func index(_ value: Double) -> Int {
        steps.indices.min { abs(steps[$0] - value) < abs(steps[$1] - value) } ?? 2
    }
}

/// Plain copy for anything shown to a person.
func userMessage(_ error: Error, fallback: String = "Something went wrong. Please try again.") -> String {
    // Expo's own errors are already written for people; system errors are not.
    if error is any LocalizedError, let text = (error as? LocalizedError)?.errorDescription { return text }
    return fallback
}

enum YearsRule {
    static let hint = "Whole numbers only, for example 3."
    static func problem(_ text: String) -> String? {
        let value = text.trimmed
        return !value.isEmpty && value.allSatisfy({ $0.isASCII && $0.isNumber }) ? nil : "Years of experience must be a whole number, for example 3."
    }
}
