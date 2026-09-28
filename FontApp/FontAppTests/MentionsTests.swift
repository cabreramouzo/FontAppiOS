import Testing
@testable import FontApp

/// The cases `web/src/lib/mentions.test.ts` and the server's `Mentions` agree on.
struct MentionsTests {
    @Test func anEmailIsNotAMention() {
        #expect(Mentions.matches(in: "escriu a hola@fontapp.net").isEmpty)
        #expect(Mentions.matches(in: "gràcies @marta_r!").map(\.name) == ["marta_r"])
    }

    @Test func theMentionBeingTypedIsTheOneAtTheCaret() {
        let text = "hola @ma i @jo"
        #expect(Mentions.typing(in: text, caret: 8)?.prefix == "ma")
        #expect(Mentions.typing(in: text, caret: 14)?.prefix == "jo")
        // Inside a word already written: suggesting there would replace untouched text.
        #expect(Mentions.typing(in: text, caret: 7) == nil)
    }

    @Test func choosingReplacesItAndLeavesASpace() {
        let text = "hola @ma"
        let typing = Mentions.typing(in: text, caret: 8)!
        let result = Mentions.insert("marta_r", in: text, at: typing)
        #expect(result.text == "hola @marta_r ")
        #expect(result.caret == 14)
    }
}
