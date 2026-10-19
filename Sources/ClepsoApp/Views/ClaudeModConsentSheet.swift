import DesignSystem
import SwiftUI

/// The Claude Code mod's consent (v0.3, docs/specs/mod-bridge.md §10): names the file, shows the two entries exactly as
/// they are written, and says what the mod can do, before anything is written. Cancel is the default button.
struct ClaudeModConsentSheet: View {
    let model: AppModel
    let done: (AppModel.ClaudeModOutcome?) -> Void
    @State private var working = false
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let preview = model.claudeModPreview
        SheetFrame(glyph: .code, title: Copy.ClaudeMod.confirmTitle) {
            Text(Copy.ClaudeMod.confirmBody(preview.file)).font(theme.font(.label)).foregroundStyle(theme.color(.textPrimary, scheme))
                .fixedSize(horizontal: false, vertical: true)
            Text(preview.entries).font(theme.font(.supporting)).foregroundStyle(theme.color(.textPrimary, scheme)).textSelection(.enabled)
                .padding(theme.spacing(.standard)).frame(maxWidth: .infinity, alignment: .leading)
                .background(PixelRect(step: theme.stroke(.hairline) * 2).fill(theme.color(.surfaceMuted, scheme)))
                .fixedSize(horizontal: false, vertical: true)
            Text(Copy.ClaudeMod.scopeBody(preview.folder)).font(theme.font(.supporting)).foregroundStyle(theme.color(.textPrimary, scheme))
                .fixedSize(horizontal: false, vertical: true)
            Text(Copy.ClaudeMod.offBody).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                .fixedSize(horizontal: false, vertical: true)
        } actions: {
            Button(Copy.ClaudeMod.cancel) { done(nil) }.keyboardShortcut(.cancelAction).buttonStyle(PixelButtonStyle())
            Button(Copy.ClaudeMod.add) {
                working = true
                Task { done(await model.setClaudeMod(true)) }
            }
            .buttonStyle(PixelButtonStyle(prominent: true))
            .disabled(working)
        }
    }
}
