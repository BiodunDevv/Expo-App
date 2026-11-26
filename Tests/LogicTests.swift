import Foundation

// Checks for the pure logic. Run with scripts/test.sh.
@main
struct LogicTests {
    nonisolated(unsafe) static var failures = 0

    static func check(_ condition: Bool, _ name: String) {
        print("\(condition ? "PASS" : "FAIL")  \(name)")
        if !condition { failures += 1 }
    }

    static func main() async throws {
        // Environment
        let parsed = AppConfig.parse("# note\nexport EXPO_API_KEY=\"abc#1\"\nEXPO_BACKEND_URL=https://x.test/ # prod\n")
        check(parsed["EXPO_API_KEY"] == "abc#1", "env: quoted value keeps #")
        check(parsed["EXPO_BACKEND_URL"] == "https://x.test/", "env: inline comment removed")
        let config = try AppConfig.load(environment: ["EXPO_BACKEND_URL": "https://x.test/"], files: [])
        check(config.backendURL.absoluteString == "https://x.test", "env: trailing slash trimmed")
        check(config.isBackendConfigured, "env: remote HTTPS works without a key")
        check((try? AppConfig.load(environment: ["EXPO_BACKEND_URL": "http://evil.test"], files: [])) == nil, "env: plain HTTP refused")
        let local = try AppConfig.load(environment: ["EXPO_BACKEND_URL": "http://localhost:3000"], files: [])
        check(!local.isBackendConfigured, "env: localhost needs a key")

        // Mixer
        let size = PCMFrameMixer.samplesPerFrame
        var mono = PCMFrameMixer(includeMicrophone: false)
        check(mono.pushSystem(Array(repeating: 1, count: size - 1)).isEmpty, "mixer: waits for a full frame")
        check(mono.pushSystem([1]).first?.count == size * 2, "mixer: mono frame is 250 ms of Int16")
        var stereo = PCMFrameMixer(includeMicrophone: true)
        _ = stereo.pushMicrophone(Array(repeating: 7, count: size))
        let frame = stereo.pushSystem(Array(repeating: 9, count: size))
        let samples = frame.first.map { data in data.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) } } ?? []
        check(samples.count == size * 2 && samples[0] == 7 && samples[1] == 9, "mixer: microphone left, computer right")
        var quiet = PCMFrameMixer(includeMicrophone: true)
        check(quiet.pushMicrophone(Array(repeating: 3, count: size * 2)).count == 1, "mixer: microphone does not wait for silent output")
        check(PCMFrameMixer.pcm([2, -2, 0, .nan]) == [32_767, -32_768, 0, 0], "mixer: clipping")
        var resampler = LinearResampler(from: 44_100)
        let total = (0..<100).reduce(0) { sum, _ in sum + resampler.process(Array(repeating: 0.5, count: 441)).count }
        check(abs(total - 48_000) <= 2, "resampler: 1 s at 44.1 kHz becomes 48 kHz")

        // Echo
        func segment(_ speaker: String, _ at: String, _ text: String) -> TranscriptSegment {
            TranscriptSegment(id: UUID().uuidString, at: at, speaker: speaker, text: text, confidence: "high")
        }
        let heard = [segment("Meeting", "00:10", "Can you tell me about your last project?")]
        check(MicrophoneEcho.matches(segment("You", "00:12", "tell me about your last project"), in: heard), "echo: repeat dropped")
        check(!MicrophoneEcho.matches(segment("You", "00:12", "Sure, it was a payments service"), in: heard), "echo: own words kept")
        check(!MicrophoneEcho.matches(segment("You", "00:40", "tell me about your last project"), in: heard), "echo: later repeat kept")

        // Wire formats
        let remote = try JSONDecoder().decode(RemoteSession.self, from: Data(#"{"id":"a","title":"T","status":"active","startedAt":"2026-01-01T10:00:00.000Z","durationSeconds":3}"#.utf8))
        var cached = remote.merged(into: nil)
        cached.transcript = heard
        check(remote.merged(into: cached).transcript == heard, "sync: summaries keep the cached transcript")
        check(ISO.date("2026-01-01T10:00:00.000Z") != nil && ISO.date("2026-01-01T10:00:00Z") != nil, "dates: both ISO forms")
        let settings = try JSONDecoder().decode(ExpoSettings.self, from: Data("{}".utf8))
        check(settings.captureMicrophone && settings.autoAnswer, "settings: defaults")
        check(CapturePrivacy.resolve(prefersHidden: true, allowed: nil) == .hidden, "privacy: hidden before sign-in")
        check(CapturePrivacy.resolve(prefersHidden: false, allowed: true) == .visible, "privacy: person can show Expo")
        check(CapturePrivacy.resolve(prefersHidden: true, allowed: false) == .unavailable, "privacy: plan can disallow hiding")
        // Years of experience
        check(YearsRule.problem("3") == nil && YearsRule.problem("3.5") != nil && YearsRule.problem("") != nil, "years: whole numbers only")

        // Audio recovery
        struct Broken: Error {}
        var attempts = 0
        let quick: [Duration] = [.zero, .zero, .zero, .zero]
        var outcome = await Recovery.run(delays: quick, shouldContinue: { true }, operation: { attempts += 1; if attempts < 3 { throw Broken() } })
        check(outcome == .restored && attempts == 3, "recovery: succeeds on a later attempt")
        attempts = 0
        outcome = await Recovery.run(delays: quick, shouldContinue: { true }, operation: { attempts += 1; throw Broken() })
        check(attempts == 5 && outcome != .restored && outcome != .abandoned, "recovery: gives up after five attempts")
        attempts = 0
        _ = await Recovery.run(delays: quick, shouldContinue: { true }, isPermanent: { _ in true }, operation: { attempts += 1; throw Broken() })
        check(attempts == 1, "recovery: stops on a permanent failure")
        attempts = 0
        outcome = await Recovery.run(delays: quick, shouldContinue: { attempts < 2 }, operation: { attempts += 1; throw Broken() })
        check(outcome == .abandoned && attempts == 2, "recovery: stops when the session pauses or ends")

        // Ready check
        var facts = Readiness.Facts(consent: true, audioTest: .passed, microphoneWanted: true, microphone: .granted,
                                    screenAllowed: false, serviceReachable: true, assistantReady: true, transcriptionReady: true)
        check(Readiness(facts).headline == "Ready to start", "ready: optional screen access never blocks")
        facts.audioTest = .never; facts.serviceReachable = false
        check(Readiness(facts).blockers.map(\.kind) == [.computerAudio, .service], "ready: lists what blocks a session")
        check(Readiness(facts).headline == "2 things need attention", "ready: counts blockers")
        facts.audioTest = .passed; facts.serviceReachable = nil
        check(Readiness(facts).isChecking && Readiness(facts).headline == "Checking…", "ready: waits while checking")
        facts.serviceReachable = true; facts.transcriptionReady = false
        check(Readiness(facts).blockers.first?.kind == .service, "ready: transcription outage blocks")
        facts.microphoneWanted = false
        check(Readiness(facts).items.first { $0.kind == .microphone }?.state == .off, "ready: microphone off is optional")

        // Glance card
        let listed = Glance("Start with **requirements**:\n- Token bucket\n- Shared store\n- Limits per user\n- Burst size\n```\ncode\n```")
        check(listed.headline == "Start with requirements", "glance: headline from the opening line")
        check(listed.points == ["Token bucket", "Shared store", "Limits per user"] && listed.truncated, "glance: three points, marks the rest")
        let plain = Glance("Say yes. Explain the timeline. Offer a follow-up.")
        check(plain.headline == "Say yes." && plain.points.count == 2 && !plain.truncated, "glance: sentences when there is no list")
        let onlyList = Glance("1. First\n2. Second")
        check(onlyList.headline == "First" && onlyList.points == ["Second"], "glance: a bare list")
        check(Glance("").headline.isEmpty && Glance("Done.").points.isEmpty, "glance: empty and single answers")
        check(Refinement.allCases.allSatisfy { $0.prompt(for: String(repeating: "a", count: 5_000)).count <= Refinement.limit }, "glance: follow-ups fit the question limit")

        // Practice
        let title = PracticeSession.title(.interview, topic: "Backend engineer\nlong description")
        check(title == "Practice · Interview: Backend engineer" && PracticeSession.isPractice(title) && !PracticeSession.isPractice("Meeting session"), "practice: marked by its title")
        check(PracticeSession.name(title) == "Interview: Backend engineer" && PracticeSession.title(.sales, topic: "  ") == "Practice · Sales call", "practice: readable names")
        check(PracticeSession.brief(.interview, topic: String(repeating: "a", count: 20_000)).count <= MeetingBrief.maxCharacters, "practice: brief fits the limit")

        // Voice orb
        check(AudioLevel.of(Data()) == 0 && AudioLevel.of(Data(count: 640)) == 0, "orb: silence is zero")
        let loud = Data((0..<320).flatMap { _ in [UInt8(0xFF), 0x7F] })
        check(AudioLevel.of(loud) == 1, "orb: loud audio is capped at one")

        // Sending what is heard
        var turn = SpeechTurn()
        check(!turn.add("um") && !turn.add("Uh, hmm.") && turn.text.isEmpty, "send: hesitation alone is not sent")
        check(turn.add("Oh, so I'm sick.") && turn.add("What is a closure"), "send: everything else is, question or not")
        let start = Date()
        check(turn.take(at: start) == "Oh, so I'm sick. What is a closure" && turn.text.isEmpty, "send: lines up to the pause go together")
        _ = turn.add("oh so im sick what is a closure")
        check(turn.take(at: start + 2) == nil, "send: an immediate echo is sent once")
        _ = turn.add("oh so im sick what is a closure")
        check(turn.take(at: start + 30) != nil, "send: said again later, it is sent again")
        _ = turn.add(String(repeating: "word ", count: 400))
        check(turn.text.count <= SpeechTurn.limit, "send: stays within the question limit")
        check((try? JSONDecoder().decode(ExpoSettings.self, from: Data("{}".utf8)))?.answerOwnQuestions == true, "send: earlier settings include own voice")
        let meetingShort = [segment("Meeting", "00:10", "I know.")]
        check(!MicrophoneEcho.matches(segment("You", "00:11", "I know how to build that service"), in: meetingShort), "echo: a short meeting line keeps a longer answer")

        check(CvRules.problem(name: "cv.txt", size: 10) != nil && CvRules.problem(name: "cv.PDF", size: 10) == nil, "cv: type rules")

        print(failures == 0 ? "All checks passed." : "\(failures) check(s) failed.")
        exit(failures == 0 ? 0 : 1)
    }
}
