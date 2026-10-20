import Foundation
import Storage
import Testing
@testable import ClepsoApp

@MainActor struct RetentionTests {
    @Test("Shorter retention persists across launches and invalid values cannot erase all history")
    func persistence() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        let clock = TestClock()
        let model = box.model(clock: clock)
        await model.start()
        var value = DataRetention()
        value.readings = 7; value.sessions = 14; value.receipts = 7; value.logs = 1
        await model.setDataRetention(value)
        model.stop()
        let reopened = box.model(clock: clock)
        await reopened.start(); defer { reopened.stop() }
        #expect(reopened.dataRetention == value)
        value.readings = -1; value.sessions = 0; value.receipts = 1_000_000; value.logs = 0
        #expect(value.validated == DataRetention())
    }

    @Test("Changing diagnostics retention removes old entries without deleting recent ones")
    func logs() {
        let box = Sandbox(); defer { box.cleanUp() }
        let clock = TestClock()
        let log = DiagnosticsLog(url: box.root.appendingPathComponent("retention.jsonl"), clock: clock)
        log.record(.listening)
        clock.advance(2 * 86_400)
        log.record(.demo(on: true))
        log.setRetention(days: 1)
        #expect(log.entries.map(\.code) == ["demo.changed"])
    }
}
