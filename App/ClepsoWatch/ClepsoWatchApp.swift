import DesignSystem
import Foundation
import IntegrationSnapshot
import Observation
import SwiftUI

@MainActor @Observable final class WatchModel {
    var envelope: RelayEnvelope?
    var message: String?
    let link = CompanionWatchLink()
    private let cache: URL
    init() {
        cache = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Clepso/relay.v1.json")
        if let size = (try? FileManager.default.attributesOfItem(atPath:cache.path)[.size]) as? NSNumber, size.intValue <= 128 * 1024,
           let data = try? Data(contentsOf:cache), let value = try? RelayEnvelope.decoder().decode(RelayEnvelope.self,from:data), value.valid { envelope = value }
        link.onSnapshot = { [weak self] value in
            guard let self else { return }
            self.envelope = value; self.message = nil
            if let value, let data = try? UsageSnapshot.encoder().encode(value) {
                try? FileManager.default.createDirectory(at:self.cache.deletingLastPathComponent(),withIntermediateDirectories:true)
                try? data.write(to:self.cache,options:.atomic)
            } else { try? FileManager.default.removeItem(at:self.cache) }
        }
    }
    func start() { link.start() }
    func refresh() { link.requestRefresh(); message = "Open Clepso on the paired iPhone to refresh." }
}

@main struct ClepsoWatchApp: App {
    @State private var model = WatchModel()
    init() { PixelFonts.ensureRegistered() }
    var body: some Scene {
        WindowGroup {
            WatchRoot(model:model).environment(\.theme,Theme.phosphor).task { model.start() }
        }
    }
}
struct WatchRoot: View {
    let model: WatchModel
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        TimelineView(.periodic(from:.now,by:30)) { context in
            ScrollView {
                VStack(alignment:.leading,spacing:theme.spacing(.standard)) {
                    Text("CLEPSO").font(theme.font(.title)).foregroundStyle(theme.color(.accent,scheme))
                    CompanionLimitsView(envelope:model.envelope,now:context.date,emptyMessage:"Sign in and share a reading from the paired iPhone.")
                    Button { model.refresh() } label: {
                        Text("Refresh").frame(minHeight: theme.spacing(.section))
                    }.buttonStyle(PixelButtonStyle())
                    if let message = model.message { Text(message).font(theme.font(.supporting)) }
                    Text("Expected-reset notifications mirror your iPhone’s system settings.").font(theme.font(.supporting))
                }.padding(theme.spacing(.compact))
            }.background(theme.color(.background,scheme))
        }
    }
}
