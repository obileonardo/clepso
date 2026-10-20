import DesignSystem
import Domain
import Foundation
import SubscriptionCatalog
import SwiftUI

struct ManualLimitsSection: View {
    @Bindable var model: AppModel
    @State private var adding = false
    @State private var editing: ManualAllowance?
    @State private var removing: ManualAllowance?
    @State private var error: String?
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        PageSection(Copy.Manual.title, Copy.Manual.subtitle) {
            VStack(alignment: .leading, spacing: theme.spacing(.spacious)) {
                if model.manualAllowances.isEmpty {
                    Text(Copy.Manual.empty).font(theme.font(.label)).foregroundStyle(theme.color(.textSecondary, scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(model.demo ? [] : model.manualAllowances) { value in
                    allowance(value)
                }
                Button(Copy.Manual.add) { adding = true }.buttonStyle(PixelButtonStyle(prominent: true)).disabled(model.demo)
                if let error {
                    Text(error).font(theme.font(.supporting)).foregroundStyle(theme.color(.statusAttention, scheme))
                }
            }
        }
        .sheet(isPresented: $adding) { ManualReadingSheet(model: model) }
        .sheet(item: $editing) { value in ManualReadingSheet(model: model, initial: value) }
        .confirmationDialog(Copy.Manual.deleteTitle, isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button(Copy.Manual.remove, role: .destructive) {
                guard let value = removing else { return }
                Task {
                    do { try await model.removeManualAllowance(value) }
                    catch { self.error = Copy.Manual.failed }
                    removing = nil
                }
            }
            Button(Copy.Manual.cancel, role: .cancel) { removing = nil }
        } message: { Text(Copy.Manual.deleteBody) }
    }

    func allowance(_ value: ManualAllowance) -> some View {
        let provider = ManualProvider.supported.first { $0.id == value.providerID }
        let now = model.environment.clock.now()
        let old = value.isStale(at: now)
        return VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
            HStack(spacing: theme.spacing(.standard)) {
                Text((provider?.name ?? value.providerID) + " · " + Copy.Manual.scope(value.window))
                    .font(theme.font(.title)).foregroundStyle(theme.color(.textPrimary, scheme))
                Spacer()
                PixelChip(text: Copy.Manual.entered.uppercased(), lit: false)
            }
            Text(value.usedPercent.map { NSDecimalNumber(decimal: $0).stringValue + "%" } ?? Copy.Manual.notReported)
                .font(theme.font(.metricMedium)).foregroundStyle(theme.color(.textPrimary, scheme))
            let age = Formatting.age(of: value.observedAt, now: now, zone: model.environment.timeZone, locale: model.environment.locale)
            Text((old ? Copy.Manual.stale + " · " : "") + age)
                .font(theme.font(.label)).foregroundStyle(theme.color(old ? .statusStale : .textSecondary, scheme))
            Text(Copy.Manual.measured + ": " + Formatting.measuredTime(value.observedAt, zone: model.environment.timeZone, locale: model.environment.locale))
                .font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
            if let reset = value.resetsAt {
                Text(value.resetPassed(at: now) ? Copy.Manual.resetPassed
                     : Copy.Limits.resets(Formatting.resetTime(reset, now: now, zone: model.environment.timeZone, locale: model.environment.locale)))
                    .font(theme.font(.label)).foregroundStyle(theme.color(.textSecondary, scheme))
            }
            if value.paidOverage, (value.usedPercent ?? 0) >= 100 {
                Text(Copy.Manual.overageNote).font(theme.font(.label)).foregroundStyle(theme.color(.statusAttention, scheme))
            }
            if let id = value.planCatalogID, let entry = (try? PlanCatalog.bundled())?.entries.first(where: { $0.id == id }) {
                Text(entry.displayName + " · " + Copy.Manual.selected).font(theme.font(.supporting))
                    .foregroundStyle(theme.color(.textSecondary, scheme))
            }
            HStack(spacing: theme.spacing(.standard)) {
                Button(Copy.Manual.update) { editing = value }.buttonStyle(PixelButtonStyle())
                if let raw = provider?.usageURL, let url = URL(string: raw) {
                    Button(Copy.Manual.open) { model.environment.openLink(url) }.buttonStyle(PixelButtonStyle())
                }
                Spacer()
                Button(Copy.Manual.remove) { removing = value }.buttonStyle(PixelButtonStyle())
            }
        }
        .padding(theme.spacing(.standard))
        .background(theme.color(.surfaceMuted, scheme))
    }
}

struct ManualReadingSheet: View {
    let model: AppModel
    var initial: ManualAllowance?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    @State private var providerID = ManualProvider.supported[0].id
    @State private var window = ManualAllowance.Window.weekly
    @State private var percent = ""
    @State private var observed = Date.distantPast
    @State private var reset = Date.distantPast
    @State private var hasReset = false
    @State private var planID = ""
    @State private var overage = false
    @State private var error: String?
    @State private var saving = false

    var plans: [PlanCatalog.Entry] {
        let publisher = ManualProvider.supported.first { $0.id == providerID }?.publisher ?? ""
        return (try? PlanCatalog.bundled())?.subscriptionPlans(publisher: publisher) ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.spacious)) {
            Text(Copy.Manual.add.uppercased()).font(theme.font(.title)).foregroundStyle(theme.color(.textPrimary, scheme))
            Text(Copy.Manual.empty).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                .fixedSize(horizontal: false, vertical: true)
            Picker(Copy.Manual.provider, selection: $providerID) {
                ForEach(ManualProvider.supported) { Text($0.name).tag($0.id) }
            }.onChange(of: providerID) { _, _ in
                if !plans.contains(where: { $0.id == planID }) { planID = "" }
            }
            PixelSegmented(Copy.Manual.window, options: ManualAllowance.Window.allCases.map { ($0, Copy.Manual.scope($0)) }, selection: $window)
            Picker(Copy.Manual.plan, selection: $planID) {
                Text(Copy.Manual.unknown).tag("")
                ForEach(plans) { Text($0.displayName + " · " + Copy.Manual.selected).tag($0.id) }
            }
            Text(Copy.Manual.used).font(theme.font(.label))
            TextField("0–100", text: $percent).textFieldStyle(.roundedBorder).accessibilityLabel(Copy.Manual.used)
            DatePicker(Copy.Manual.measured, selection: $observed, in: ...model.environment.clock.now(), displayedComponents: [.date, .hourAndMinute])
            Toggle(Copy.Manual.hasReset, isOn: $hasReset).toggleStyle(PixelToggleStyle())
            if hasReset { DatePicker(Copy.Manual.reset, selection: $reset, displayedComponents: [.date, .hourAndMinute]) }
            Toggle(Copy.Manual.overage, isOn: $overage).toggleStyle(PixelToggleStyle())
            if let error {
                Text(error).font(theme.font(.supporting)).foregroundStyle(theme.color(.statusAttention, scheme))
                    .fixedSize(horizontal: false, vertical: true).accessibilityLabel(error)
            }
            HStack {
                Button(Copy.Manual.cancel) { dismiss() }.buttonStyle(PixelButtonStyle()).keyboardShortcut(.cancelAction)
                Spacer()
                Button(Copy.Manual.save) { save() }.buttonStyle(PixelButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction).disabled(saving)
            }
        }
        .font(theme.font(.label)).foregroundStyle(theme.color(.textPrimary, scheme))
        .padding(theme.spacing(.spacious)).frame(width: SettingsMetrics.sheetWidth)
        .background(theme.color(.background, scheme))
        .onAppear {
            observed = model.environment.clock.now()
            reset = observed
            if let initial {
                providerID = initial.providerID; window = initial.window
                percent = initial.usedPercent.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
                hasReset = initial.resetsAt != nil; reset = initial.resetsAt ?? observed
                planID = initial.planCatalogID ?? ""; overage = initial.paidOverage
            }
        }
    }

    func save() {
        let text = percent.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = text.isEmpty ? nil : ManualAllowance.parsePercent(text, locale: model.environment.locale)
        guard text.isEmpty || value != nil else { error = Copy.Manual.error; return }
        saving = true
        Task {
            defer { saving = false }
            do {
                try await model.saveManualAllowance(providerID: providerID, window: window, usedPercent: value,
                                                    resetsAt: hasReset ? reset : nil, observedAt: observed,
                                                    planID: planID.isEmpty ? nil : planID, paidOverage: overage)
                dismiss()
            } catch is ManualAllowance.Invalid { self.error = Copy.Manual.error }
            catch { self.error = Copy.Manual.failed }
        }
    }
}
