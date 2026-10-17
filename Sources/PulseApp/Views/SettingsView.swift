import AppKit
import DesignSystem
import Domain
import SubscriptionCatalog
import SwiftUI
import UniformTypeIdentifiers

/// Increment 1.11 (founder review): settings live in the Dashboard window (SettingsSection), in the pixel style.
/// What remains here is shared by it and onboarding: the plan picker and the agents and delete-all sheets.
enum SettingsMetrics {
    static let width: CGFloat = 520
    static let sheetWidth: CGFloat = 460
    static let logHeight: CGFloat = 160
    static let diagnosticsHeight: CGFloat = 640
}

/// Agents per task consent (increment 1.9): names the file and shows the exact entry before anything is written.
/// Cancel is the default button.
struct AgentsConsentSheet: View {
    let model: AppModel
    let done: (AppModel.AgentsOutcome?) -> Void
    @State private var working = false
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let preview = model.agentsPreview
        VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
            Text(Copy.Agents.confirmTitle).font(theme.font(.title))
            Text(Copy.Agents.confirmBody(preview.file)).font(theme.font(.label)).fixedSize(horizontal: false, vertical: true)
            Text(preview.entry).font(theme.font(.supporting)).textSelection(.enabled)
                .padding(theme.spacing(.standard)).frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.color(.surfaceMuted, scheme))
                .fixedSize(horizontal: false, vertical: true)
            Text(Copy.Agents.offBody).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(Copy.Agents.cancel) { done(nil) }.keyboardShortcut(.cancelAction)
                Button(Copy.Agents.add) {
                    working = true
                    Task { done(await model.setAgentsCounting(true)) }
                }
                .disabled(working)
            }
        }
        .padding(theme.spacing(.spacious))
        .frame(width: SettingsMetrics.sheetWidth)
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
                    PixelLabel(item, symbol: "trash").font(theme.font(.supporting)).fixedSize(horizontal: false, vertical: true)
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
