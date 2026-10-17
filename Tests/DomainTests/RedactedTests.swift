import Foundation
import Testing
@testable import Domain

struct RedactedTests {
    @Test("Redacted never shows its value: description, interpolation, dump; the fingerprint is stable")
    func neverLeaks() {
        let secret = Redacted("/Users/someone/.claude/settings.json", label: "settings_path")
        var dumped = ""
        dump(secret, to: &dumped)
        for text in [secret.description, "\(secret)", String(reflecting: secret), dumped] {
            #expect(!text.contains("someone") && !text.contains("/Users/"), "\(text)")
        }
        #expect(secret.description == "<redacted:settings_path>")
        #expect(secret.fingerprint.count == 12)
        #expect(secret.fingerprint == Redacted("/Users/someone/.claude/settings.json", label: "other").fingerprint)
        #expect(secret.unsafeReveal(reason: "test") == "/Users/someone/.claude/settings.json")
    }
}
