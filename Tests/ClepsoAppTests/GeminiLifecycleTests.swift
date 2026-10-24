import Foundation
import Testing
@testable import ClepsoApp

@MainActor @Suite("Gemini consent lifecycle", .serialized) struct GeminiLifecycleTests {
    @Test func optInPersistsOptOutClearsAndDemoDoesNotRead() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        let clock = TestClock(), first = box.model(clock: clock)
        let chats = box.home.appendingPathComponent(".gemini/tmp/p/chats")
        try FileManager.default.createDirectory(at: chats, withIntermediateDirectories: true)
        let date = clock.now().formatted(.iso8601)
        let recording = """
        {"sessionId":"session-test","messages":[{"id":"message-test","type":"gemini","timestamp":"\(date)","content":"NEVER RETAIN THIS","tokens":{"input":10,"output":5,"cached":2,"total":15}}]}
        """
        try Data(recording.utf8).write(to: chats.appendingPathComponent("session-test.json"))
        await first.start()
        #expect(!first.geminiEnabled && first.geminiUsage == nil)
        #expect(await first.setGeminiEnabled(true))
        #expect(first.geminiUsage?.total == 15)
        #expect(!String(describing: first.geminiUsage).contains("NEVER RETAIN"))
        first.stop()
        let second = box.model(clock: clock); await second.start(); defer { second.stop() }
        #expect(second.geminiEnabled)
        await second.setDemo(true)
        await second.pollGemini()
        #expect(second.geminiUsage == nil)
        await second.setDemo(false)
        await second.pollGemini()
        #expect(second.geminiUsage?.total == 15)
        #expect(await second.setGeminiEnabled(false))
        #expect(second.geminiUsage == nil)
        await second.pollGemini()
        #expect(second.geminiUsage == nil)
    }
    @Test func deletingDataDropsTheReaderAndItsConsent() async throws {
        let box = Sandbox(); defer { box.cleanUp() }
        let model = box.model(clock: TestClock()); await model.start(); defer { model.stop() }
        #expect(await model.setGeminiEnabled(true))
        let report = await model.deleteAll(includeBackups: false, relaunch: false)
        #expect(report.failure == nil && !model.geminiEnabled && model.geminiUsage == nil)
    }
}
