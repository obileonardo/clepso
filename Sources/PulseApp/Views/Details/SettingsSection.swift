import AppKit
import DesignSystem
import Domain
import SwiftUI
import UniformTypeIdentifiers

/// Settings, inside the Dashboard (increment 1.11; layout after the founder's Linear and Wise picks): one centred
/// column of groups; each row a round icon, a title, one line of explanation, and its control on the right.
/// Replaces the separate Settings window, which didn't follow the pixel style.
struct SettingsSection: View {
    @Bindable var model: AppModel
    @State private var confirmAgents = false
    @State private var confirmRemove = false
    @State private var message: String?
    @State private var exportMessage: String?
    @State private var deleteMessage: String?
    @State private var showLog = false
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.spacious) * 1.5) {
            group(Copy.SettingsPage.general) {
                row("power", Copy.Settings.launchAtLogin, Copy.SettingsPage.loginSub) {
                    toggle(model.loginItemEnabled) { on in Task { await model.setLoginItem(on) } }
                }
                row("percent", Copy.Settings.showPercent, Copy.SettingsPage.percentSub) {
                    toggle(model.showPercent) { on in Task { await model.setShowPercent(on) } }
                }
            }
            group(Copy.SettingsPage.notifications) {
                row("bell", Copy.SettingsPage.notificationsTitle, notificationLine) { notificationControl }
            }
            group(Copy.SettingsPage.claudeCode) {
                row("link", Copy.SettingsPage.connection, connectionLine) {
                    if model.preview.installed {
                        Button(Copy.Settings.remove) { confirmRemove = true }.buttonStyle(PixelButtonStyle())
                    } else {
                        Button(Copy.Home.connect) {
                            model.onboardingStep = .consent
                            NSApp.activate(ignoringOtherApps: true)
                            openWindow(id: PulseScenes.onboardingID)
                        }
                        .buttonStyle(PixelButtonStyle(prominent: true))
                    }
                }
                row("dollarsign", Copy.Settings.forwardCost, Copy.Settings.forwardCostSublabel) {
                    toggle(model.forwardCost) { on in Task { await model.setForwardCost(on) } }
                }
                row("chart.bar.xaxis", Copy.Stats.toggle, Copy.Stats.toggleSublabel) {
                    toggle(model.statsEnabled) { on in Task { await model.setStatsEnabled(on) } }
                }
                row("person.3", Copy.Agents.toggle, model.preview.installed || model.agentsCounting ? Copy.Agents.toggleSublabel : Copy.Agents.needsConnection) {
                    toggle(model.agentsCounting) { on in
                        if on { confirmAgents = true } else { Task { message = Self.message(await model.setAgentsCounting(false)) } }
                    }
                    .disabled(!model.preview.installed && !model.agentsCounting)
                }
                if let message { note(message) }
            }
            group(Copy.SettingsPage.data) {
                row("square.and.arrow.up", Copy.Export.button, Copy.SettingsPage.exportSub) {
                    Button(Copy.SettingsPage.exportAction) { exportData() }.buttonStyle(PixelButtonStyle())
                }
                if let exportMessage { note(exportMessage) }
                row("theatermasks", Copy.Settings.demoToggle, Copy.SettingsPage.demoSub) {
                    toggle(model.demo) { on in Task { await model.setDemo(on) } }
                }
                row("trash", Copy.Diagnostics.deleteAll, Copy.SettingsPage.deleteSub, danger: true) {
                    Button(Copy.SettingsPage.deleteAction) { model.confirmingDeleteAll = true }.buttonStyle(PixelButtonStyle())
                }
                if let deleteMessage { note(deleteMessage) }
            }
            group(Copy.SettingsPage.diagnostics) {
                row("waveform.path.ecg", Copy.Diagnostics.receiving, receivingLine) {
                    Button(showLog ? Copy.SettingsPage.hideLog : Copy.SettingsPage.showLog) { showLog.toggle() }.buttonStyle(PixelButtonStyle())
                }
                if showLog { log }
            }
        }
        .frame(maxWidth: DetailsMetrics.settingsColumn, alignment: .leading)
        .frame(maxWidth: .infinity)                                   // centred column, like the references
        .task {
            model.refreshPreview()
            await model.refreshNotificationStatus()
            await model.refreshIngestHealth()
        }
        .sheet(isPresented: $confirmAgents) {
            AgentsConsentSheet(model: model) { outcome in
                confirmAgents = false
                if let outcome { message = Self.message(outcome) }
            }
        }
        .sheet(isPresented: $model.confirmingDeleteAll) {
            DeleteAllSheet(model: model) { text in deleteMessage = text }
        }
        .confirmationDialog(Copy.Settings.remove, isPresented: $confirmRemove) {
            Button("Remove", role: .destructive) {
                Task {
                    message = switch await model.uninstall() {
                    case .restoredExactly: Copy.Explainer.restoreExact
                    case .removedOurEntryOnly: Copy.Explainer.restoreSurgical
                    case .nothingToRemove: Copy.Settings.providerNotInstalled
                    case .failed(let reason): reason
                    }
                }
            }
        } message: {
            Text(Copy.Explainer.restoreExact + " " + Copy.Explainer.restoreSurgical)
        }
    }

    // MARK: - Lines

    var connectionLine: String {
        let snapshot = model.snapshot
        if !snapshot.isDemo, let seen = snapshot.updatedAt {
            return Copy.Settings.providerConnected(Formatting.clock(seen, zone: model.environment.timeZone, locale: model.environment.locale))
        }
        return model.preview.installed ? Copy.Settings.providerInstalled : Copy.Settings.providerNotInstalled
    }

    var notificationLine: String {
        switch model.notificationStatus {
        case .authorized: Copy.SettingsPage.allowed
        case .denied: Copy.Problem.notificationsDenied
        case .notDetermined: Copy.SettingsPage.notAllowed
        }
    }

    @ViewBuilder var notificationControl: some View {
        switch model.notificationStatus {
        case .authorized:
            Button(Copy.Settings.test) { Task { await model.sendTestNotification() } }.buttonStyle(PixelButtonStyle())
        case .denied:
            Button(Copy.Problem.openSystemSettings) {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
            }
            .buttonStyle(PixelButtonStyle())
        case .notDetermined:
            Button(Copy.SettingsPage.allow) { Task { await model.requestNotifications() } }.buttonStyle(PixelButtonStyle(prominent: true))
        }
    }

    var receivingLine: String {
        let h = model.socketHealth
        return Copy.Diagnostics.health((h.accepted, h.rejectedPeer, h.rejectedFrame, h.oversize, h.rateLimited))
    }

    var log: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.compact)) {
            if model.diagnostics.entries.isEmpty {
                Text(Copy.Diagnostics.empty).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: theme.spacing(.compact)) {
                        ForEach(model.diagnostics.entries.suffix(200).reversed()) { entry in
                            HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.standard)) {
                                Text(entry.at.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, timeZone: model.environment.timeZone)))
                                    .foregroundStyle(theme.color(.textSecondary, scheme)).monospacedDigit()
                                Image(systemName: entry.level == .info ? "info.circle" : "exclamationmark.triangle")
                                    .foregroundStyle(theme.color(entry.level == .info ? .textSecondary : .statusAttention, scheme))
                                    .accessibilityLabel(entry.level.rawValue)
                                Text(entry.text).textSelection(.enabled).foregroundStyle(theme.color(.textPrimary, scheme))
                            }
                            .font(theme.font(.supporting))
                        }
                    }
                }
                .frame(height: SettingsMetrics.logHeight)
                Button(Copy.Diagnostics.clear) { model.diagnostics.clear() }.buttonStyle(PixelButtonStyle())
            }
        }
        .padding(theme.spacing(.standard))
        .background(theme.color(.surfaceMuted, scheme))
        .padding(.vertical, theme.spacing(.standard))
    }

    // MARK: - Building blocks

    func group(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        let rows = content()
        return VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
            Text(title).font(theme.font(.title)).foregroundStyle(theme.color(.accent, scheme)).accessibilityAddTraits(.isHeader)
            PixelPanel {
                VStack(alignment: .leading, spacing: 0) { rows }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    func row(_ symbol: String, _ title: String, _ subtitle: String?, danger: Bool = false, @ViewBuilder control: () -> some View) -> some View {
        HStack(alignment: .center, spacing: theme.spacing(.spacious)) {
            Image(systemName: symbol).font(theme.font(.label))
                .foregroundStyle(theme.color(danger ? .statusBlocked : .accent, scheme))
                .frame(width: theme.spacing(.spacious) * 1.8, height: theme.spacing(.spacious) * 1.8)
                .background(PixelRect(step: theme.stroke(.hairline) * 2).fill(theme.color(.surfaceMuted, scheme)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: theme.spacing(.compact) / 2) {
                Text(title).font(theme.font(.label)).foregroundStyle(theme.color(danger ? .statusBlocked : .textPrimary, scheme))
                if let subtitle {
                    Text(subtitle).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: theme.spacing(.spacious))
            control()
        }
        .padding(.vertical, theme.spacing(.standard) + theme.spacing(.compact))
        .accessibilityElement(children: .contain)
    }

    func note(_ text: String) -> some View {
        Text(text).font(theme.font(.supporting)).foregroundStyle(theme.color(.accent, scheme))
            .fixedSize(horizontal: false, vertical: true).padding(.bottom, theme.spacing(.standard))
    }

    func toggle(_ value: Bool, _ set: @escaping (Bool) -> Void) -> some View {
        Toggle("", isOn: Binding(get: { value }, set: set)).labelsHidden().toggleStyle(PixelToggleStyle())
    }

    func exportData() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(Product.name) export \(model.environment.clock.now().formatted(.iso8601.year().month().day())).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            exportMessage = switch await model.export(to: url) {
            case .success(let summary): Copy.Export.done(summary.rows, summary.scrubbed)
            case .failure(let failure): failure.reason
            }
        }
    }

    static func message(_ outcome: AppModel.AgentsOutcome) -> String {
        switch outcome {
        case .added: Copy.Agents.added
        case .removedExactly: Copy.Agents.removedExact
        case .removedEntries: Copy.Agents.removedEntries
        case .alreadyGone: Copy.Agents.alreadyGone
        case .failed(let reason): Copy.Agents.failed(reason)
        }
    }
}
