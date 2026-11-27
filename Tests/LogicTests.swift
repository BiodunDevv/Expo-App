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

        check(AnswerStyle.standard.instruction(plainEnglish: false) == nil, "style: the default says nothing extra")
        check(AnswerStyle.bullets.instruction(plainEnglish: true)?.contains("bullet") == true
              && AnswerStyle.bullets.instruction(plainEnglish: true)?.contains("simple") == true, "style: style and simple English combine")
        check(AnswerStyle.allCases.allSatisfy { ($0.instruction(plainEnglish: true) ?? "").count <= 300 }, "style: fits the server limit")
        check((try? JSONDecoder().decode(ExpoSettings.self, from: Data(#"{"answerStyle":"later"}"#.utf8)))?.answerStyle == .standard, "style: unknown value falls back")

        let migrated = try? JSONDecoder().decode(ExpoSettings.self, from: Data(#"{"savedBrief":"Panel interview"}"#.utf8))
        check(migrated?.profiles.map(\.details) == ["Panel interview"] && migrated?.lastProfileID == migrated?.profiles.first?.id, "profiles: the old saved brief becomes a profile")
        let again = migrated.flatMap { try? JSONDecoder().decode(ExpoSettings.self, from: JSONEncoder().encode($0)) }
        check(again?.profiles == migrated?.profiles, "profiles: survive saving")
        var profiles: [SavedProfile] = []
        check(!profiles.save(SavedProfile(name: " ", details: "x")) && !profiles.save(SavedProfile(name: "x", details: "")), "profiles: need a name and notes")
        var first = SavedProfile(name: "Acme", details: "Role")
        profiles.save(first); first.details = "New role"; profiles.save(first)
        check(profiles.count == 1 && profiles[0].details == "New role", "profiles: saving again replaces")
        for n in 0..<40 { profiles.save(SavedProfile(name: "\(n)", details: "d")) }
        check(profiles.count == SavedProfile.limit, "profiles: the list is bounded")

        let began = ISO.now(), base = ISO.date(began)!
        var practised = ExpoSession(id: "p", title: "Practice · Interview", startedAt: began, status: "complete")
        practised.transcript = [
            segment("You", "00:02", "Tell me about yourself"),
            segment("You", "00:12", "Um, I basically build apps, you know, you know"),
            segment("Meeting", "00:15", "Interesting"),
            segment("You", "00:40", "My strength is focus"),
        ]
        practised.assistantMessages = [
            AssistantMessage(id: "a", question: "Tell me about yourself", summary: "I am a developer.", references: [], confidence: "medium", createdAt: ISO.string(base + 5)),
            AssistantMessage(id: "b", question: "What is your strength", summary: "Focus.", references: [], confidence: "medium", createdAt: ISO.string(base + 30)),
        ]
        let review = PracticeReview(session: practised)
        check(review.wordCount == 17, "review: counts only your words")
        check(review.fillers.first == .init(phrase: "you know", count: 2) && review.fillerCount == 4, "review: counts filler phrases")
        check(review.exchanges.map(\.reply) == ["Um, I basically build apps, you know, you know", "My strength is focus"], "review: pairs replies with answers")
        check(SpeechTiming(seconds: 30, words: 70).wordsPerMinute == 140 && SpeechTiming(seconds: 3, words: 9).wordsPerMinute == nil, "review: pace needs enough speech")
        check(PracticeReview.coachingRequest.count <= 1_000 && PracticeReview.coachingFormat.count <= 300, "review: feedback request fits the limits")

        check(!Recovery.captureStalled(outputChanged: false, microphone: false, secondsSinceSystem: 600, secondsSinceMicrophone: 600), "audio: a quiet Mac is not a fault")
        check(!Recovery.captureStalled(outputChanged: false, microphone: true, secondsSinceSystem: 600, secondsSinceMicrophone: 0.2), "audio: speaking into a quiet Mac is not a fault")
        check(Recovery.captureStalled(outputChanged: false, microphone: true, secondsSinceSystem: 20, secondsSinceMicrophone: 20), "audio: a dead microphone and output rebuild capture")
        check(Recovery.captureStalled(outputChanged: true, microphone: false, secondsSinceSystem: 0, secondsSinceMicrophone: 0), "audio: new speakers rebuild capture")
        let now = Date()
        check(Recovery.shouldAnnounce(last: nil, now: now) && !Recovery.shouldAnnounce(last: now - 30, now: now) && Recovery.shouldAnnounce(last: now - 400, now: now), "audio: one alert per outage")

        let fenced = MarkdownBlock.parse("Intro\n1. Step\n   ```js\n   if (a) {\n     b()\n   }\n   ```\nAfter")
        check(fenced == [.paragraph("Intro"), .bullet(mark: "1.", text: "Step"), .code(language: "js", text: "if (a) {\n  b()\n}"), .paragraph("After")], "markdown: code keeps its language and indentation")
        check(MarkdownBlock.parse("```\nx") == [.code(language: "", text: "x")], "markdown: a streaming fence is code")
        let source = "const a = \"hi // not\" // note\nfoo(42) it's"
        let spans = CodeHighlighter.spans(source, language: "js")
        check(spans.map(\.text).joined() == source, "code: colouring never changes the text")
        func kind(_ text: String) -> CodeHighlighter.Kind? { spans.first { $0.text == text }?.kind }
        check(kind("const") == .keyword && kind("\"hi // not\"") == .string && kind("// note") == .comment && kind("foo") == .call && kind("42") == .number, "code: names the parts")
        check(CodeHighlighter.spans("# a\nx = 1", language: "python").first == .init(text: "# a", kind: .comment), "code: hash comments")
        for edge in ["\"", "/* open", "'a\\", "`t", ""] {
            check(CodeHighlighter.spans(edge, language: "ts").map(\.text).joined() == edge, "code: unfinished input \(edge.debugDescription)")
        }

        let reply = "**1. What is JavaScript?**\nA language.\n2. **var, let and const**\n```js\n# not a title\n```\n### 3. Types"
        check(ScreenAnswer.titles(reply) == ["1. What is JavaScript?", "2. var, let and const", "3. Types"], "screen: finds the questions answered")
        check(ScreenAnswer.transcriptNote(source: "the entire screen", answer: reply).hasPrefix("Captured the entire screen and answered it. 1."), "screen: transcript line")
        check(ScreenAnswer.request.count <= 1_000 && ScreenAnswer.format(plainEnglish: true).count <= 300, "screen: request fits the limits")
        check(SeeThrough.allCases.allSatisfy { $0.card >= 0.75 }, "glass: cards stay readable")

        let area = CGRect(x: 0, y: 0, width: 1_400, height: 900), box = CGRect(x: 300, y: 350, width: 690, height: 500)
        func drag(_ edges: SessionFrame.Edges, _ x: CGFloat, _ y: CGFloat) -> CGRect { SessionFrame.resized(box, edges: edges, travel: CGSize(width: x, height: y), within: area) }
        check(drag(.right, 100, 40) == CGRect(x: 300, y: 350, width: 790, height: 500), "window: right edge widens only")
        check(drag(.left, -100, 0) == CGRect(x: 200, y: 350, width: 790, height: 500), "window: left edge keeps the right side")
        check(drag(.bottom, 80, -100) == CGRect(x: 300, y: 250, width: 690, height: 600), "window: bottom edge keeps the top")
        check(drag([.right, .bottom], 100, -50) == CGRect(x: 300, y: 300, width: 790, height: 550), "window: a corner does both")
        check(drag(.right, -900, 0).width == SessionFrame.minimumWidth && drag(.left, 900, 0).maxX == box.maxX && drag(.left, 900, 0).width == SessionFrame.minimumWidth, "window: never narrower than the tools")
        check(drag(.bottom, 0, 900).height == SessionFrame.minimumHeight && drag(.bottom, 0, 900).maxY == box.maxY, "window: never shorter than the minimum")
        check(drag(.right, 5_000, 0).maxX == area.maxX && drag(.bottom, 0, -5_000).minY == 0, "window: stays on screen")
        let placed = SessionFrame.placed(topLeft: CGPoint(x: 1_300, y: 60), size: CGSize(width: 690, height: 500), within: area)
        check(area.contains(placed) && placed.size == CGSize(width: 690, height: 500), "window: a remembered place off screen is brought back")
        check(SessionFrame.placed(topLeft: .zero, size: CGSize(width: 3_000, height: 3_000), within: area) == area, "window: never larger than the screen")

        check(SessionFrame.toggled(SessionFrame.usual, open: true, previous: nil) == SessionFrame.small, "size: shrinks to small")
        check(SessionFrame.toggled(SessionFrame.small, open: true, previous: CGSize(width: 900, height: 700)) == CGSize(width: 900, height: 700), "size: restores the size from before")
        check(SessionFrame.toggled(SessionFrame.small, open: true, previous: nil) == SessionFrame.usual && SessionFrame.toggled(SessionFrame.small, open: true, previous: SessionFrame.small) == SessionFrame.usual, "size: with nothing to restore, the usual size")
        check(SessionFrame.isSmall(CGSize(width: 560, height: 900), open: false) && !SessionFrame.isSmall(CGSize(width: 560, height: 900), open: true), "size: closed, only the width counts")
        check((try? JSONDecoder().decode(ExpoSettings.self, from: Data("{}".utf8)))?.emailNotes == true, "email: on unless turned off")
        check((try? JSONDecoder().decode(ExpoSettings.self, from: Data(#"{"emailNotes":false}"#.utf8)))?.emailNotes == false, "email: the choice is kept")
        check(!BillingSummary(features: nil, plan: "free", enforced: false, periodEnd: nil, usage: nil).emailsNotes && BillingSummary(features: nil, plan: "starter", enforced: false, periodEnd: nil, usage: nil).emailsNotes, "email: included on paid plans")

        var view = SessionLayout()
        check(!view.chatOpen && !view.compact, "session: begins as the input alone")
        view.answerArrived()
        check(view.chatOpen, "session: a first answer opens the chat")
        view.hideChat(); view.answerArrived()
        check(!view.chatOpen, "session: a hidden chat stays hidden when answers arrive")
        view.asked()
        check(view.chatOpen && view.jumps == 1, "session: asking opens the chat at the newest message")
        view.minimize(answers: 3); view.answerArrived()
        check(view.compact && view.answersAtMinimize == 3, "session: made small, answers do not open it")
        view.expand()
        check(!view.compact && view.chatOpen, "session: expanding returns to how it was")
        view.minimize(answers: 0); view.showChat()
        check(!view.compact && view.chatOpen, "session: show chat opens it from small")
        view.makeRoom(false); view.answerArrived()
        check(view.chatOpen, "session: options closing does not count as hiding the chat")

        var follow = ScrollFollow()
        check(follow.following, "scroll: follows from the start")
        follow.scrolled(distanceFromEnd: 6, towardStart: true)
        check(!follow.following, "scroll: the smallest scroll up stops following")
        follow.scrolled(distanceFromEnd: 300, towardStart: false)
        check(!follow.following, "scroll: scrolling down part of the way does not resume")
        follow.scrolled(distanceFromEnd: 12, towardStart: false)
        check(follow.following, "scroll: returning near the end resumes")
        follow.scrolled(distanceFromEnd: -20, towardStart: true)
        check(follow.following, "scroll: a bounce at the end keeps following")
        follow.scrolled(distanceFromEnd: 200, towardStart: true); follow.jump()
        check(follow.following, "scroll: Latest resumes")

        print(failures == 0 ? "All checks passed." : "\(failures) check(s) failed.")
        exit(failures == 0 ? 0 : 1)
    }
}
