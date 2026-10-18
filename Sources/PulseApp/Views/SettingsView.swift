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
    /// Everything starts ticked (founder review, 18 Oct 2026): one list of checkboxes instead of a trash icon per line.
    @State private var chosen = Set(AppModel.DeleteItem.allCases)
    @State private var includeBackups = false
    @State private var working = false
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    var everything: Bool { chosen.count == AppModel.DeleteItem.allCases.count }

    var body: some View {
        SheetFrame(glyph: .trash, title: Copy.DeleteAll.title, role: .statusBlocked) {
            HStack(alignment: .firstTextBaseline) {
                Text(Copy.DeleteAll.body).font(theme.font(.label)).foregroundStyle(theme.color(.textPrimary, scheme))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: theme.spacing(.standard))
                Button(everything ? Copy.DeleteAll.selectNone : Copy.DeleteAll.selectAll) {
                    chosen = everything ? [] : Set(AppModel.DeleteItem.allCases)
                }
                .buttonStyle(PixelQuietButtonStyle()).fixedSize()
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(model.deleteItems.enumerated()), id: \.offset) { index, entry in
                    Toggle(isOn: Binding(get: { chosen.contains(entry.item) },
                                         set: { if $0 { chosen.insert(entry.item) } else { chosen.remove(entry.item) } })) {
                        Text(entry.label).font(theme.font(.supporting)).foregroundStyle(theme.color(.textPrimary, scheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .toggleStyle(PixelCheckboxStyle())
                    .padding(.vertical, theme.spacing(.compact) + theme.stroke(.hairline))
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
            Button(everything ? Copy.DeleteAll.confirm : Copy.DeleteAll.confirmSome(chosen.count), role: .destructive) {
                working = true
                let items = chosen
                Task {
                    let report = await model.delete(items, includeBackups: includeBackups)
                    var message = report.failure ?? (items.count == AppModel.DeleteItem.allCases.count ? Copy.DeleteAll.done : Copy.DeleteAll.deletedSome(items.count))
                    if !report.leftovers.isEmpty { message += " " + Copy.DeleteAll.leftovers(report.leftovers) }
                    done(message)
                    working = false
                    dismiss()
                }
            }
            .buttonStyle(PixelButtonStyle(destructive: true))
            .disabled(working || chosen.isEmpty)
        }
    }
}

/// Plan picker: catalog entries, `Not sure`, and the confirm toggle.
/// The PlanPill preview updates live; nothing is stored until Save.
struct PlanPicker: View {
    let model: AppModel
    var onSaved: (() -> Void)?
    var onCancel: (() -> Void)? = nil
    /// Onboarding: a quiet "Skip for now" at the left of the action row.
    var onSkip: (() -> Void)? = nil
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
            HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.standard)) {
                PlanPill(planName: entry.map { PopoverMetrics.shortPlan($0.displayName) }, provenance: provenance)
                if let entry {
                    Text(Copy.Settings.lastChecked(entry.checkedAt) + (entry.verified ? "" : " · " + Copy.Settings.notVerified))
                        .font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // One ruled action row: the way out or aside on the left, Save on the right.
            HStack(spacing: theme.spacing(.standard)) {
                if let onSkip { Button(Copy.Onboarding.planSkip, action: onSkip).buttonStyle(PixelQuietButtonStyle()) }
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
            .padding(.top, theme.spacing(.standard) + theme.spacing(.compact))
            .overlay(alignment: .top) { Rectangle().fill(theme.color(.separator, scheme)).frame(height: theme.stroke(.hairline)) }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            selection = model.plan?.catalogID ?? ""
            confirmed = model.plan?.evidence == .userConfirmed
        }
    }
}
