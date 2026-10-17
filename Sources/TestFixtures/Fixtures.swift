import Foundation

/// The fixture corpus (format: docs/fixtures/README.md in the Tokone docs folder).
/// `manifest.json` lists every fixture ID, active or deferred to the stage that owns it.
public enum Fixtures {
    public static let claudeCodeRoot: URL = {
        guard let resources = Bundle.module.url(forResource: "Resources", withExtension: nil) else {
            fatalError("TestFixtures resources missing from the bundle")
        }
        return resources.appendingPathComponent("claude-code")
    }()
}
