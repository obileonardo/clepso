import AppKit
import DesignSystem
import Domain
import SubscriptionCatalog
import SwiftUI
import UniformTypeIdentifiers

/// The Settings window (UX_SPEC §2.7). Tabs show only what this build does; thresholds, quiet hours and
/// diagnostics tools arrive with their increments (2.1, 1.5) rather than as inert controls.
public struct SettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        TabView(selection: $model.settingsTab) {
            GeneralTab(model: model).tabItem { Label(Copy.Settings.general, systemImage: "gearshape") }.tag(AppModel.SettingsTab.general)
            NotificationsTab(model: model).tabItem { Label(Copy.Settings.notifications, systemImage: "bell") }.tag(AppModel.SettingsTab.notifications)
            ProvidersTab(model: model).tabItem { Label(Copy.Settings.providers, systemImage: "link") }.tag(AppModel.SettingsTab.providers)
            PlanPicker(model: model).padding(theme.spacing(.spacious))
                .tabItem { Label(Copy.Settings.plan, systemImage: "person.crop.circle") }.tag(AppModel.SettingsTab.plan)
            DiagnosticsTab(model: model).tabItem { Label(Copy.Settings.diagnostics, systemImage: "stethoscope") }.tag(AppModel.SettingsTab.diagnostics)
        }
        .frame(width: SettingsMetrics.width)
        .environment(\.isFixtureData, model.snapshot.isDemo)
        .task {
            model.refreshPreview()
            await model.refreshNotificationStatus()
        }
    }
}

enum SettingsMetrics {
    static let width: CGFloat = 520
    static let sheetWidth: CGFloat = 460
    static let logHeight: CGFloat = 160
    static let diagnosticsHeight: CGFloat = 640
}

struct GeneralTab: View {
    let model: AppModel
    var body: some View {
        Form {
            Toggle(Copy.Settings.launchAtLogin, isOn: Binding(get: { model.loginItemEnabled }, set: { on in Task { await model.setLoginItem(on) } }))
            Toggle(Copy.Settings.showPercent, isOn: Binding(get: { model.showPercent }, set: { on in Task { await model.setShowPercent(on) } }))
        }
        .formStyle(.grouped)
    }
}

struct NotificationsTab: View {
    let model: AppModel
    var body: some View {
        Form {
            switch model.notificationStatus {
            case .notDetermined:
                Text(Copy.Onboarding.alertsBody).fixedSize(horizontal: false, vertical: true)
                Button(Copy.Onboarding.alertsEnable) { Task { await model.requestNotifications() } }
            case .denied:
                Text(Copy.Problem.notificationsDenied)
                Button(Copy.Problem.openSystemSettings) {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                }
            case .authorized:
                Text("Notifications are on.")
                Button(Copy.Settings.test) { Task { await model.sendTestNotification() } }
            }
        }
        .formStyle(.grouped)
    }
}

struct ProvidersTab: View {
    let model: AppModel
    @State private var confirmRemove = false
    @State private var removeResult: String?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Form {
            Section("Claude Code") {
                LabeledContent("Status", value: status)
                if model.preview.installed {
                    Button(Copy.Settings.remove) { confirmRemove = true }
                } else {
                    Button(Copy.Empty.noProviderCTA) {
                        model.onboardingStep = .consent
                        NSApp.activate(ignoringOtherApps: true)
                        openWindow(id: PulseScenes.onboardingID)
                    }
                }
                if let removeResult { Text(removeResult).foregroundStyle(.secondary) }
                Toggle(isOn: Binding(get: { model.forwardCost }, set: { on in Task { await model.setForwardCost(on) } })) {
                    Text(Copy.Settings.forwardCost)
                    Text(Copy.Settings.forwardCostSublabel)
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(Copy.Settings.remove, isPresented: $confirmRemove) {
            Button("Remove", role: .destructive) {
                Task {
                    removeResult = switch await model.uninstall() {
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

    var status: String {
        let snapshot = model.snapshot
        if !snapshot.isDemo, let seen = snapshot.updatedAt {
            return Copy.Settings.providerConnected(Formatting.clock(seen, zone: model.environment.timeZone, locale: model.environment.locale))
        }
        return model.preview.installed ? Copy.Settings.providerInstalled : Copy.Settings.providerNotInstalled
    }
}

/// Settings › Diagnostics (UX_SPEC §2.7, PRIVACY_AND_SECURITY §5–§8): recent events, update counts, export,
/// delete-all, and the demo switch.
struct DiagnosticsTab: View {
    @Bindable var model: AppModel
    @State private var exportMessage: String?
    @State private var deleteMessage: String?
    @Environment(\.theme) private var theme

    var body: some View {
        Form {
            Section(Copy.Diagnostics.log) {
                if model.diagnostics.entries.isEmpty {
                    Text(Copy.Diagnostics.empty).foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: theme.spacing(.compact)) {
                            ForEach(model.diagnostics.entries.suffix(200).reversed()) { entry in
                                HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.standard)) {
                                    Text(entry.at.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, timeZone: model.environment.timeZone)))
                                        .foregroundStyle(.secondary).monospacedDigit()
                                    Image(systemName: entry.level == .info ? "info.circle" : "exclamationmark.triangle")
                                        .accessibilityLabel(entry.level.rawValue)
                                    Text(entry.text).textSelection(.enabled)
                                }
                                .font(theme.font(.supporting))
                            }
                        }
                    }
                    .frame(height: SettingsMetrics.logHeight)
                }
                Button(Copy.Diagnostics.clear) { model.diagnostics.clear() }.disabled(model.diagnostics.entries.isEmpty)
            }
            Section(Copy.Diagnostics.receiving) {
                let h = model.socketHealth
                Text(Copy.Diagnostics.health((h.accepted, h.rejectedPeer, h.rejectedFrame, h.oversize, h.rateLimited)))
                    .font(theme.font(.supporting))
            }
            Section {
                Button(Copy.Export.button) { exportData() }
                if let exportMessage { Text(exportMessage).font(theme.font(.supporting)) }
                Button(Copy.Diagnostics.deleteAll, role: .destructive) { model.confirmingDeleteAll = true }
                if let deleteMessage { Text(deleteMessage).font(theme.font(.supporting)) }
            }
            Section {
                Toggle(Copy.Settings.demoToggle, isOn: Binding(get: { model.demo }, set: { on in Task { await model.setDemo(on) } }))
                if model.demo { Text(Copy.Demo.header).foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
        .frame(height: SettingsMetrics.diagnosticsHeight)          // tall enough that Export and Delete are never below the fold
        .task { await model.refreshIngestHealth() }
        .sheet(isPresented: $model.confirmingDeleteAll) {
            DeleteAllSheet(model: model) { message in deleteMessage = message }
        }
    }

    func exportData() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(Product.name) export \(Date.now.formatted(.iso8601.year().month().day())).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            exportMessage = switch await model.export(to: url) {
            case .success(let summary): Copy.Export.done(summary.rows, summary.scrubbed)
            case .failure(let failure): failure.reason
            }
        }
    }
}

/// Delete-all confirmation (§8 step 1): names every item; the backups box is off by default; Cancel is the default button.
struct DeleteAllSheet: View {
    let model: AppModel
    let done: (String) -> Void
    @State private var includeBackups = false
    @State private var working = false
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
            Text(Copy.DeleteAll.title).font(theme.font(.title))
            Text(Copy.DeleteAll.body).font(theme.font(.label)).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: theme.spacing(.compact)) {
                ForEach(model.deleteAllItems, id: \.self) { item in
                    Label(item, systemImage: "trash").font(theme.font(.supporting)).fixedSize(horizontal: false, vertical: true)
                }
            }
            Toggle(Copy.DeleteAll.backups, isOn: $includeBackups)
            HStack {
                Spacer()
                Button(Copy.DeleteAll.cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(Copy.DeleteAll.confirm, role: .destructive) {
                    working = true
                    Task {
                        let report = await model.deleteAll(includeBackups: includeBackups)
                        var message = report.failure ?? Copy.DeleteAll.done
                        if !report.leftovers.isEmpty { message += " " + Copy.DeleteAll.leftovers(report.leftovers) }
                        done(message)
                        working = false
                        dismiss()
                    }
                }
                .disabled(working)
            }
        }
        .padding(theme.spacing(.spacious))
        .frame(width: SettingsMetrics.sheetWidth)
    }
}

/// Plan picker (UX_SPEC §4 step 2, PLAN_CATALOG §4): catalog entries, `Not sure`, and the confirm toggle.
/// The PlanPill preview updates live; nothing is stored until Save.
struct PlanPicker: View {
    let model: AppModel
    var onSaved: (() -> Void)?
    @State private var selection: String = ""
    @State private var confirmed = false
    @State private var loaded = false
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var plans: [PlanCatalog.Entry] { model.catalog?.claudePlans ?? [] }
    var entry: PlanCatalog.Entry? { plans.first { $0.id == selection } }
    var provenance: PlanProvenance { entry == nil ? .notSet : (confirmed ? .userConfirmed : .selectedUnverified) }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
            Text(Copy.Onboarding.planBody).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                .fixedSize(horizontal: false, vertical: true)
            Picker(Copy.Onboarding.planTitle, selection: $selection) {
                Text(Copy.Onboarding.planNotSure).tag("")
                ForEach(plans) { plan in Text(plan.displayName).tag(plan.id) }
            }
            Toggle(Copy.Onboarding.planConfirmToggle, isOn: $confirmed).disabled(entry == nil)
            HStack(spacing: theme.spacing(.standard)) {
                PlanPill(planName: entry.map { PopoverMetrics.shortPlan($0.displayName) }, provenance: provenance)
                Spacer()
                Button(Copy.Settings.save) {
                    Task {
                        await model.choosePlan(entry, confirmed: confirmed && entry != nil)
                        onSaved?()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
            if let entry {
                Text(Copy.Settings.lastChecked(entry.checkedAt) + (entry.verified ? "" : " · " + Copy.Settings.notVerified))
                    .font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            selection = model.plan?.catalogID ?? ""
            confirmed = model.plan?.evidence == .userConfirmed
        }
    }
}
