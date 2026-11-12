import AppKit
import DesignSystem
import Domain
import IntegrationSnapshot
import SwiftUI
import UniformTypeIdentifiers
import UsageEngine

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
    @State private var newAgentName = ""
    @State private var agentNameMessage: String?
    @State private var agentSuggestions: [String]?
    @State private var mcpName = ""
    @State private var pendingMCP: String?
    @State private var confirmMobileSharing = false
    @Environment(\.theme) var theme
    @Environment(\.colorScheme) var scheme
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        PageColumn {
            group(Copy.SettingsPage.general) {
                row("circle.lefthalf.filled", Copy.SettingsPage.appearance, Copy.SettingsPage.appearanceSub) {
                    PixelSegmented(Copy.SettingsPage.appearance, options: [(AppModel.Appearance.system, Copy.SettingsPage.system),
                                                                           (.light, Copy.SettingsPage.light), (.dark, Copy.SettingsPage.dark)],
                                   selection: Binding(get: { model.appearance }, set: { value in Task { await model.setAppearance(value) } }))
                }
                row("paintpalette", Copy.SettingsPage.theme, Copy.SettingsPage.themeSub) { EmptyView() }
                ThemePicker(selection: model.themeName) { name in Task { await model.setTheme(name) } }
                    .padding(.leading, theme.spacing(.spacious) * 2.8)            // under the row's text, past its icon
                    .padding(.bottom, theme.spacing(.standard) + theme.spacing(.compact))
                row("power", Copy.Settings.launchAtLogin, Copy.SettingsPage.loginSub) {
                    toggle(model.loginItemEnabled) { on in Task { await model.setLoginItem(on) } }
                }
                row("percent", Copy.Settings.showPercent, Copy.SettingsPage.percentSub) {
                    toggle(model.showPercent) { on in Task { await model.setShowPercent(on) } }
                }
                row("clock.arrow.circlepath", Copy.SettingsPage.menuBarDisplay, Copy.SettingsPage.menuBarDisplaySub) {
                    Picker(Copy.SettingsPage.menuBarDisplay, selection: Binding(get: { model.menuBarDisplay }, set: { value in
                        Task { await model.setMenuBarDisplay(value) }
                    })) {
                        ForEach(MenuBarDisplay.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .disabled(!model.showPercent)
                }
            }
            group(Copy.SettingsPage.notifications) {
                row("bell", Copy.SettingsPage.notificationsTitle, notificationLine) { notificationControl }
                row("gauge.with.dots.needle.50percent", Copy.Alerts.toggle, alertsLine) {
                    HStack(spacing: theme.spacing(.standard)) {
                        if model.alertsEnabled, model.notificationStatus == .authorized {
                            if snoozed {
                                Button(Copy.Alerts.unsnooze) { Task { await model.snoozeAlerts(for: nil) } }.buttonStyle(PixelButtonStyle())
                            } else {
                                Button(Copy.Alerts.snooze) { Task { await model.snoozeAlerts(for: 3600) } }.buttonStyle(PixelButtonStyle())
                            }
                        }
                        toggle(model.alertsEnabled) { on in Task { await model.setAlertsEnabled(on) } }
                            .disabled(model.notificationStatus != .authorized)
                    }
                }
                row("clock", Copy.Alerts.quietHours, Copy.Alerts.quietHoursSub) {
                    toggle(model.quietHours.enabled) { on in setQuiet { $0.enabled = on } }
                        .disabled(model.notificationStatus != .authorized)
                }
                if model.quietHours.enabled {
                    HStack(spacing: theme.spacing(.spacious)) {
                        timeStepper(Copy.Alerts.quietFrom, minute: model.quietHours.start) { minute in setQuiet { $0.start = minute } }
                        timeStepper(Copy.Alerts.quietTo, minute: model.quietHours.end) { minute in setQuiet { $0.end = minute } }
                    }
                    .disabled(model.notificationStatus != .authorized)
                    .opacity(model.notificationStatus == .authorized ? 1 : 0.4)
                    .padding(.leading, theme.spacing(.spacious) * 2.8)            // under the row's text, past its icon
                    .padding(.bottom, theme.spacing(.standard) + theme.spacing(.compact))
                }
                row("clock.arrow.circlepath", Copy.Alerts.reminders, Copy.Alerts.remindersSub) { EmptyView() }
                PixelSegmented(Copy.Alerts.reminders,
                               options: [(0, Copy.Alerts.remindersOff)] + ReminderPlanner.leads.map { ($0, Copy.Alerts.leadShort($0)) },
                               selection: Binding(get: { model.reminderLead ?? 0 },
                                                  set: { minutes in MainActor.assumeIsolated { setLead(minutes) } }))
                    .disabled(model.notificationStatus != .authorized)
                    .opacity(model.notificationStatus == .authorized ? 1 : 0.4)
                    .padding(.leading, theme.spacing(.spacious) * 2.8)
                    .padding(.bottom, theme.spacing(.standard) + theme.spacing(.compact))
            }
            group("Updates") {
                row("arrow.triangle.2.circlepath", "Check for updates", "Updates are signed, verified and notarized before installation. This alpha channel includes preview releases.") {
                    Button("Check now…") { model.checkForUpdates() }.buttonStyle(PixelButtonStyle())
                        .disabled(!model.updatesAvailable)
                }
                row("clock", "Automatic update checks", "Check the Clepso update feed once a day. You can turn this off at any time.") {
                    toggle(model.updateChecksEnabled) { model.setUpdateChecks($0) }.disabled(!model.updatesAvailable)
                }
                row("square.and.arrow.down", "Download and install automatically", "Allow verified updates to install when Clepso quits. Sparkle asks before interrupting active use.") {
                    toggle(model.updateDownloadsEnabled) { model.setUpdateDownloads($0) }
                        .disabled(!model.updatesAvailable || !model.updateChecksEnabled)
                }
            }
            group(Copy.SettingsPage.claudeCode) {
                row("link", Copy.SettingsPage.connection, connectionLine) {
                    if model.preview.installed {
                        Button(Copy.Settings.remove) { confirmRemove = true }.buttonStyle(PixelButtonStyle())
                    } else {
                        Button(Copy.Home.connect) {
                            model.onboardingStep = .consent
                            NSApp.activate(ignoringOtherApps: true)
                            openWindow(id: ClepsoScenes.onboardingID)
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
                if model.environment.features.claudeMod {
                    row("chevron.left.forwardslash.chevron.right", Copy.ClaudeMod.toggle, claudeModLine) {
                        toggle(model.claudeModOn) { on in
                            if on { model.confirmingClaudeMod = true } else { Task { message = Self.message(await model.setClaudeMod(false)) } }
                        }
                        .disabled(!model.preview.installed && !model.claudeModOn)
                    }
                }
                row("person.crop.circle.badge.checkmark", Copy.Agents.namesTitle, Copy.Agents.namesSub) {
                    Button(Copy.Agents.findNames) { agentSuggestions = model.suggestedAgentNames() }.buttonStyle(PixelButtonStyle())
                }
                agentNames
                if let message { note(message) }
            }
            group(Copy.SettingsPage.codex) {
                row("terminal", Copy.Codex.toggle, codexLine) {
                    toggle(model.codexEnabled) { on in Task { await model.setCodexEnabled(on) } }
                        .disabled(!model.codexInstalled && !model.codexEnabled)
                }
            }
            group("Gemini CLI") {
                row("terminal", "Read recorded token activity", "Read counters and timestamps from the newest Gemini CLI recordings on this Mac. Those files also contain conversations; content is discarded. Reading stays on this Mac; disabling clears the temporary file cache. No credentials are read or telemetry enabled.") {
                    toggle(model.geminiEnabled) { on in Task { await model.setGeminiEnabled(on) } }
                        .disabled(model.geminiChanging || (!model.geminiInstalled && !model.geminiEnabled))
                }
                note(model.geminiInstalled ? "Gemini recordings found. Tokens do not establish your subscription quota or reset time." : "No Gemini CLI recordings found. Run Gemini CLI on this Mac first; web chat is separate.")
                if let message = model.geminiMessage { note(message) }
            }
            group("Integrations") {
                row("iphone", "iPhone and Apple Watch", "Share aggregate limits through your Clepso account. The phone can plan expected-reset reminders and pass readings to your paired Watch.") {
                    toggle(model.mobileSharingEnabled) { enabled in
                        if enabled { confirmMobileSharing = true }
                        else { Task { await model.setMobileSharing(false) } }
                    }.disabled(model.mobileSharingBusy || !model.accountsAvailable)
                }
                if let message = model.mobileSharingMessage { note(message) }
                row("square.grid.2x2", "Desktop widgets", "Share limits with Clepso’s small and medium widgets. Widgets refresh on macOS’s schedule and label old readings.") {
                    toggle(model.widgetsEnabled) { value in Task { await model.setWidgetsEnabled(value) } }
                        .disabled(model.widgetSharingBusy)
                }
                row("link", "Clepso MCP", "Share read-only limits and reader health with a client you choose. Your client may send these readings to its AI provider.") { EmptyView() }
                ForEach(model.mcpClients, id: \.self) { client in
                    row("checkmark.shield", client, "Allowed on this Mac") {
                        Button("Copy setup") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(model.mcpConfiguration(client: client), forType: .string)
                        }.buttonStyle(PixelButtonStyle())
                        Button("Revoke") { Task { await model.setMCPClient(client, allowed: false) } }.buttonStyle(PixelButtonStyle())
                    }
                }
                row("plus", "Allow a client", "Name it using lowercase letters, numbers and hyphens. No client settings are changed automatically.") {
                    TextField("e.g. claude-desktop", text: $mcpName)
                        .textFieldStyle(.plain).font(theme.font(.label)).autocorrectionDisabled()
                        .padding(theme.spacing(.standard)).background(theme.color(.surfaceMuted, scheme))
                        .frame(maxWidth: theme.spacing(.spacious) * 9).accessibilityLabel("MCP client name")
                        .onSubmit { if SnapshotFile.validClient(mcpName) { pendingMCP = mcpName } }
                    Button("Allow…") { pendingMCP = mcpName }.buttonStyle(PixelButtonStyle())
                        .disabled(!SnapshotFile.validClient(mcpName))
                }
                if let message = model.integrationMessage { note(message) }
            }
            group(Copy.SettingsPage.data) {
                retentionControls
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
                row("waveform.path.ecg", Copy.Diagnostics.receiving, nil) {
                    Button(showLog ? Copy.SettingsPage.hideLog : Copy.SettingsPage.showLog) { showLog.toggle() }.buttonStyle(PixelButtonStyle())
                }
                FigureStrip(items: receivingFigures, summary: receivingLine)
                    .padding(.leading, theme.spacing(.spacious) * 2.8)
                    .padding(.bottom, theme.spacing(.standard) + theme.spacing(.compact))
                if showLog { log }
            }
        }
        .task {
            model.refreshPreview()
            await model.refreshNotificationStatus()
            await model.refreshIngestHealth()
            await model.refreshClaudeModStatus()
        }
        .sheet(isPresented: $confirmAgents) {
            AgentsConsentSheet(model: model) { outcome in
                confirmAgents = false
                if let outcome { message = Self.message(outcome) }
            }
        }
        .sheet(isPresented: $model.confirmingClaudeMod) {
            ClaudeModConsentSheet(model: model) { outcome in
                model.confirmingClaudeMod = false
                if let outcome { message = Self.message(outcome) }
                Task { await model.refreshClaudeModStatus() }
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
        .confirmationDialog("Share usage with this MCP client?", isPresented: Binding(get: { pendingMCP != nil }, set: { if !$0 { pendingMCP = nil } })) {
            Button("Allow read-only usage") {
                if let client = pendingMCP { Task { await model.setMCPClient(client, allowed: true) } }
                pendingMCP = nil; mcpName = ""
            }
        } message: {
            Text("Shares provider names, usage percentages, reset times, freshness and manual/automatic provenance. No prompts, replies, paths, session IDs or account details. Your client may forward readings to an AI service. Local processes under your Mac account can read the shared file. Revoke access here at any time.")
        }
        .confirmationDialog("Share limits with your iPhone?", isPresented: $confirmMobileSharing) {
            Button("Enable mobile sharing") { Task { await model.setMobileSharing(true) } }
        } message: {
            Text("Uploads the latest provider, window, percentage, source, state and observation/reset times through your existing Clepso account. No conversations, paths, model/session IDs or credentials. Your phone signs in separately and can send that reading to its paired Watch. Sharing starts off. Disable here to stop uploads and remove the server reading when online. Server readings expire after 15 minutes; an offline phone may retain an old reading or reminder. Reported reset times do not confirm renewed quota.")
        }
    }

    // MARK: - Approved agent names

    /// The approved names, one per line with its Remove button, the field to add one, and suggestions once asked for.
    var agentNames: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
            if model.approvedAgentNames.isEmpty {
                Text(Copy.Agents.noNames).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
            }
            ForEach(model.approvedAgentNames, id: \.self) { name in
                HStack(spacing: theme.spacing(.standard)) {
                    Text(name).font(theme.font(.label)).foregroundStyle(theme.color(.textPrimary, scheme)).textSelection(.enabled)
                    Spacer(minLength: theme.spacing(.standard))
                    Button(Copy.Agents.removeNameShort) { Task { await model.removeApprovedAgentName(name) } }
                        .buttonStyle(PixelButtonStyle()).accessibilityLabel(Copy.Agents.removeName(name))
                }
            }
            HStack(spacing: theme.spacing(.standard)) {
                TextField(Copy.Agents.namePlaceholder, text: $newAgentName)
                    .textFieldStyle(.plain).font(theme.font(.label)).padding(theme.spacing(.standard))
                    .background(theme.color(.surfaceMuted, scheme))
                    .autocorrectionDisabled()
                    .accessibilityLabel(Copy.Agents.namesTitle)
                    .onSubmit { addAgentName(newAgentName) }
                Button(Copy.Agents.addName) { addAgentName(newAgentName) }
                    .buttonStyle(PixelButtonStyle(prominent: true)).fixedSize()
                    .disabled(newAgentName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let agentNameMessage { note(agentNameMessage) }
            if let suggestions = agentSuggestions {
                Text(suggestions.isEmpty ? Copy.Agents.noSuggestions : Copy.Agents.suggestionsNote)
                    .font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(suggestions, id: \.self) { name in
                    HStack(spacing: theme.spacing(.standard)) {
                        Text(name).font(theme.font(.label)).foregroundStyle(theme.color(.textSecondary, scheme))
                        Spacer(minLength: theme.spacing(.standard))
                        Button(Copy.Agents.addName) { addAgentName(name) }
                            .buttonStyle(PixelButtonStyle()).accessibilityLabel(Copy.Agents.addSuggested(name))
                    }
                }
            }
        }
        .padding(.leading, theme.spacing(.spacious) * 2.8)            // under the row's text, past its icon
        .padding(.bottom, theme.spacing(.standard) + theme.spacing(.compact))
        #if DEBUG
        .onAppear { if ProbeOverrides.agentSuggestions { agentSuggestions = model.suggestedAgentNames() } }
        #endif
    }

    func addAgentName(_ name: String) {
        Task {
            let outcome = await model.approveAgentName(name)
            agentNameMessage = switch outcome {
            case .added: nil
            case .invalid: Copy.Agents.nameInvalid
            case .builtIn: Copy.Agents.nameBuiltIn
            case .duplicate: Copy.Agents.nameDuplicate
            case .full: Copy.Agents.nameFull
            }
            if outcome == .added {
                if name == newAgentName { newAgentName = "" }
                agentSuggestions = agentSuggestions?.filter { $0 != name }
            }
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

    var snoozed: Bool { model.alertsSnoozedUntil.map { $0 > model.environment.clock.now() } ?? false }

    /// What the alerts switch does, or why it can't yet.
    var alertsLine: String {
        guard model.notificationStatus == .authorized else { return Copy.SettingsPage.alertsNeedPermission }
        if snoozed, let until = model.alertsSnoozedUntil {
            return Copy.Alerts.snoozed(Formatting.resetTime(until, now: model.environment.clock.now(),
                                                             zone: model.environment.timeZone, locale: model.environment.locale))
        }
        return Copy.Alerts.toggleSub
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

    var receivingFigures: [(value: String, label: String)] {
        let h = model.socketHealth
        return [("\(h.accepted)", Copy.Diagnostics.received), ("\(h.rejectedFrame)", Copy.Diagnostics.malformed),
                ("\(h.oversize)", Copy.Diagnostics.tooLarge), ("\(h.rateLimited)", Copy.Diagnostics.rateLimited),
                ("\(h.rejectedPeer)", Copy.Diagnostics.otherUser)]
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
                                PixelIcon(symbol: entry.level == .info ? "info.circle" : "exclamationmark.triangle")
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

    /// What the Codex switch would do, or why it can't.
    var codexLine: String {
        if !model.codexInstalled { return Copy.Codex.notFound }
        if model.codexEnabled && model.snapshot.codex == nil { return Copy.Codex.waiting }
        return Copy.Codex.toggleSublabel
    }

    // MARK: - Building blocks

    /// 1.14: a page section, like Account: the group's name and a line on the left, its rows on the right.
    func group(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        let rows = content()
        return PageSection(title, Copy.SettingsPage.groupLine(title)) {
            VStack(alignment: .leading, spacing: 0) { rows }
        }
    }

    func row(_ symbol: String, _ title: String, _ subtitle: String?, danger: Bool = false, @ViewBuilder control: () -> some View) -> some View {
        HStack(alignment: .center, spacing: theme.spacing(.spacious)) {
            PixelIcon(symbol: symbol).font(theme.font(.label))
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

    /// Quiet hours' start or end, in half-hour steps: the time between pixel "−" and "+" buttons, one adjustable
    /// element for VoiceOver.
    func timeStepper(_ label: String, minute: Int, set: @escaping @MainActor (Int) -> Void) -> some View {
        let text = Formatting.clock(Date(timeIntervalSince1970: TimeInterval(minute * 60)), zone: TimeZone(identifier: "UTC")!,
                                    locale: model.environment.locale)
        return HStack(spacing: theme.spacing(.standard)) {
            Text(label.uppercased()).font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
            Button(Copy.Alerts.stepEarlier) { set(minute - 30) }.buttonStyle(PixelButtonStyle())
            Text(text).font(theme.font(.label)).monospacedDigit().foregroundStyle(theme.color(.textPrimary, scheme))
            Button(Copy.Alerts.stepLater) { set(minute + 30) }.buttonStyle(PixelButtonStyle())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(text)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: set(minute + 30)
            case .decrement: set(minute - 30)
            @unknown default: break
            }
        }
    }

    func setLead(_ minutes: Int) {
        Task { await model.setReminderLead(minutes == 0 ? nil : minutes) }
    }

    func setQuiet(_ change: (inout QuietHours) -> Void) {
        var value = model.quietHours
        change(&value)
        let normalized = QuietHours(enabled: value.enabled, start: value.start, end: value.end)
        Task { await model.setQuietHours(normalized) }
    }

    /// SwiftUI calls a binding's setter on the main actor; saying so keeps strict concurrency checking quiet and true.
    func toggle(_ value: Bool, _ set: @escaping @MainActor @Sendable (Bool) -> Void) -> some View {
        Toggle("", isOn: Binding(get: { value }, set: { new in MainActor.assumeIsolated { set(new) } }))
            .labelsHidden().toggleStyle(PixelToggleStyle())
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

    /// The mod row's line (mod-bridge.md §8): what it does, whether it has reported yet, or that it needs the connection.
    var claudeModLine: String {
        guard model.preview.installed || model.claudeModOn else { return Copy.ClaudeMod.needsConnection }
        guard model.claudeModOn else { return Copy.ClaudeMod.toggleSublabel }
        guard let last = model.claudeModLastReading else { return Copy.ClaudeMod.waiting }
        return Copy.ClaudeMod.lastReading(Copy.Inspector.ago(model.environment.clock.now().timeIntervalSince(last)))
    }

    static func message(_ outcome: AppModel.ClaudeModOutcome) -> String {
        switch outcome {
        case .added: Copy.ClaudeMod.added
        case .removedExactly: Copy.ClaudeMod.removedExact
        case .removedEntries: Copy.ClaudeMod.removedEntries
        case .alreadyGone: Copy.ClaudeMod.alreadyGone
        case .failed(let reason): Copy.ClaudeMod.failed(reason)
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
