import AppKit

/// Holds Quit for one last upload (at most 3 s) when signed in with counts not yet sent; otherwise quits at once.
@MainActor
public final class QuitHandler: NSObject, NSApplicationDelegate {
    public weak var model: AppModel?

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, model.uploadsOnQuit else { return .terminateNow }
        Task {
            _ = await model.uploadBeforeQuit()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
