/// How much of the session window is showing: a small "meeting in progress"
/// pill, the input with its tools, or those with the chat under them.
struct SessionLayout: Equatable, Sendable {
    private(set) var compact = false
    private(set) var chatOpen = false
    /// Hidden by the person, so answers that arrive by themselves leave it shut.
    private(set) var chatDismissed = false
    /// How many answers there were when the window was made small.
    private(set) var answersAtMinimize = 0
    /// Counts the times the person asked for something, so the chat goes to it.
    private(set) var jumps = 0

    mutating func showChat() {
        compact = false
        chatOpen = true
        chatDismissed = false
    }

    mutating func hideChat() {
        chatOpen = false
        chatDismissed = true
    }

    /// The person asked something, so they want to see the reply.
    mutating func asked() {
        showChat()
        jumps += 1
    }

    mutating func minimize(answers: Int) {
        compact = true
        answersAtMinimize = answers
    }

    mutating func expand() { compact = false }

    /// An answer began without the person asking.
    mutating func answerArrived() {
        if !compact && !chatDismissed { chatOpen = true }
    }

    /// Opens or closes the space under the input for a moment, as the options
    /// do, without changing what the person chose.
    mutating func makeRoom(_ open: Bool) { chatOpen = open }
}
