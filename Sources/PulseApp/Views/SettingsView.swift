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

/// 1.15: every sheet's frame: the theme's background, a pixel glyph and title, the body, and one footer row with the
/// safe choice first and the action last (Cancel is always the default for Escape).
struct SheetFrame<Content: View, Actions: View>: View {
    let glyph: PixelGlyph
    let title: String
    var role: ColorToken = .accent
    @ViewBuilder let content: () -> Content
    @ViewBuilder let actions: () -> Actions
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.spacious)) {
            HStack(alignment: .center, spacing: theme.spacing(.standard)) {
                PixelIcon(glyph, size: 18).foregroundStyle(theme.color(role, scheme)).accessibilityHidden(true)
                Text(title.uppercased()).font(theme.font(.title)).foregroundStyle(theme.color(.textPrimary, scheme))
                    .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: theme.spacing(.standard) + theme.spacing(.compact)) { content() }
            HStack(spacing: theme.spacing(.standard)) {
                Spacer(minLength: 0)
                actions()
            }
            .padding(.top, theme.spacing(.standard) + theme.spacing(.compact))
            .overlay(alignment: .top) { Rectangle().fill(theme.color(.separator, scheme)).frame(height: theme.stroke(.hairline)) }
        }
        .padding(theme.spacing(.spacious) + theme.spacing(.compact))
        .frame(width: SettingsMetrics.sheetWidth)
        .background(theme.color(.background, scheme))
    }
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
        SheetFrame(glyph: .people, title: Copy.Agents.confirmTitle) {
            Text(Copy.Agents.confirmBody(preview.file)).font(theme.font(.label)).foregroundStyle(theme.color(.textPrimary, scheme))
                .fixedSize(horizontal: false, vertical: true)
            Text(preview.entry).font(theme.font(.supporting)).foregroundStyle(theme.color(.textPrimary, scheme)).textSelection(.enabled)
                .padding(theme.spacing(.standard)).frame(maxWidth: .infinity, alignment: .leading)
                .background(PixelRect(step: theme.stroke(.hairline) * 2).fill(theme.color(.surfaceMuted, scheme)))
                .fixedSize(horizontal: false, vertical: true)
            Text(Copy.Agents.offBody).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                .fixedSize(horizontal: false, vertical: true)
        } actions: {
            Button(Copy.Agents.cancel) { done(nil) }.keyboardShortcut(.cancelAction).buttonStyle(PixelButtonStyle())
            Button(Copy.Agents.add) {
                working = true
                Task { done(await model.setAgentsCounting(true)) }
            }
            .buttonStyle(PixelButtonStyle(prominent: true))
            .disabled(working)
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
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SheetFrame(glyph: .trash, title: Copy.DeleteAll.title, role: .statusBlocked) {
            Text(Copy.DeleteAll.body).font(theme.font(.label)).foregroundStyle(theme.color(.textPrimary, scheme))
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(model.deleteAllItems.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.standard)) {
                        PixelIcon(.trash).foregroundStyle(theme.color(.statusBlocked, scheme))
                            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.bottom] - 1 }
                        Text(item).font(theme.font(.supporting)).foregroundStyle(theme.color(.textPrimary, scheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, theme.spacing(.compact) + theme.stroke(.hairline))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .top) {
                        if index > 0 { Rectangle().fill(theme.color(.separator, scheme).opacity(0.5)).frame(height: theme.stroke(.hairline)) }
                    }
                }
            }
            .padding(.horizontal, theme.spacing(.windowPadding))
            .padding(.vertical, theme.spacing(.standard))
            .background(PixelRect(step: theme.stroke(.hairline) * 2).fill(theme.color(.surfaceElevated, scheme)))
            .overlay(PixelRect(step: theme.stroke(.hairline) * 2).strokeBorder(theme.color(.separator, scheme), lineWidth: theme.stroke(.hairline)))
            Toggle(isOn: $includeBackups) {
                Text(Copy.DeleteAll.backups).font(theme.font(.supporting)).foregroundStyle(theme.color(.textPrimary, scheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(PixelToggleStyle())
        } actions: {
            Button(Copy.DeleteAll.cancel) { dismiss() }.keyboardShortcut(.cancelAction).buttonStyle(PixelButtonStyle())
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
            .buttonStyle(PixelButtonStyle(destructive: true))
            .disabled(working)
        }
    }
}

/// Plan picker (UX_SPEC §4 step 2, PLAN_CATALOG §4): catalog entries, `Not sure`, and the confirm toggle.
/// The PlanPill preview updates live; nothing is stored until Save.
struct PlanPicker: View {
    let model: AppModel
    var onSaved: (() -> Void)?
    var onCancel: (() -> Void)? = nil
    @State private var selection: String = ""
    @State private var confirmed = false
    @State private var loaded = false
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var plans: [PlanCatalog.Entry] { model.catalog?.claudePlans ?? [] }
    var entry: PlanCatalog.Entry? { plans.first { $0.id == selection } }
    var provenance: PlanProvenance { entry == nil ? .notSet : (confirmed ? .userConfirmed : .selectedUnverified) }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.standard) + theme.spacing(.compact)) {
            Text(Copy.Onboarding.planBody).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                .fixedSize(horizontal: false, vertical: true)
            Picker(Copy.Onboarding.planTitle, selection: $selection) {
                Text(Copy.Onboarding.planNotSure).tag("")
                ForEach(plans) { plan in Text(plan.displayName).tag(plan.id) }
            }
            .labelsHidden()
            .accessibilityLabel(Copy.Onboarding.planTitle)
            Toggle(isOn: $confirmed) {
                Text(Copy.Onboarding.planConfirmToggle).font(theme.font(.supporting)).foregroundStyle(theme.color(.textPrimary, scheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(PixelToggleStyle())
            .disabled(entry == nil)
            HStack(alignment: .center, spacing: theme.spacing(.standard)) {
                PlanPill(planName: entry.map { PopoverMetrics.shortPlan($0.displayName) }, provenance: provenance)
                Spacer()
                if let onCancel {
                    Button(Copy.DeleteAll.cancel, action: onCancel).keyboardShortcut(.cancelAction).buttonStyle(PixelButtonStyle())
                }
                Button(Copy.Settings.save) {
                    Task {
                        await model.choosePlan(entry, confirmed: confirmed && entry != nil)
                        onSaved?()
                    }
                }
                .buttonStyle(PixelButtonStyle(prominent: true))
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
