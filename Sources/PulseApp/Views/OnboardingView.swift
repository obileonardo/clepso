import AppKit
import DesignSystem
import Domain
import SwiftUI

/// Onboarding (UX_SPEC §4). Two permission moments only: the settings write at Consent (no OS prompt) and
/// notification authorisation at Alerts, which appears only after a real observation.
public struct OnboardingView: View {
    let model: AppModel
    @State private var installError: String?
    @State private var installing = false
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismissWindow) private var dismissWindow

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.spacious)) {
            content
        }
        .padding(theme.spacing(.spacious) + theme.spacing(.standard))
        .frame(width: OnboardingMetrics.width, alignment: .topLeading)
        .environment(\.isFixtureData, model.snapshot.isDemo)
        .task { model.refreshPreview() }
    }

    @ViewBuilder var content: some View {
        switch model.onboardingStep {
        case .welcome:
            title(Copy.Onboarding.welcomeTitle)
            body(Copy.Onboarding.welcomeBody)
            primary(Copy.Onboarding.continue) { go(.plan) }

        case .plan:
            title(Copy.Onboarding.planTitle)
            PlanPicker(model: model) { go(.provider) }
            secondary(Copy.Onboarding.continue) { go(.provider) }

        case .provider:
            if model.preview.claudeDetected {
                title(Copy.Onboarding.providerDetected(model.snapshot.provider?.sourceVersion))
                primary(Copy.Onboarding.continue) { go(model.preview.installed ? .firstReading : .consent) }
            } else {
                body(Copy.Onboarding.providerNotDetected)
                secondary(Copy.Onboarding.providerManualOnly) { go(.done) }
            }

        case .consent:
            consent

        case .firstReading:
            if let at = model.firstRealReadingAt {
                title(Copy.Onboarding.firstReadingReceived(clock(at)))
                primary(Copy.Onboarding.continue) { go(.alerts) }
            } else {
                body(Copy.Onboarding.firstReadingWaiting)
                HStack {
                    Button(Copy.Onboarding.firstReadingDemo) { Task { await model.setDemo(true) } }
                    Spacer()
                    Button(Copy.Onboarding.continue) { go(.done) }
                }
            }

        case .alerts:
            // §4 step 6: only after a real observation; demo data does not count.
            if model.firstRealReadingAt != nil {
                title(Copy.Onboarding.alertsTitle)
                body(Copy.Onboarding.alertsBody)
                HStack(spacing: theme.spacing(.standard)) {
                    Button(Copy.Onboarding.alertsEnable) { Task { await model.requestNotifications(); go(.done) } }
                    Button(Copy.Onboarding.alertsSkip) { go(.done) }      // equal weight: both bordered, neither default
                }
                .buttonStyle(PixelButtonStyle())
            } else {
                Color.clear.frame(height: 0).onAppear { go(.done) }
            }

        case .done:
            title(doneLine)
            Toggle(Copy.Settings.launchAtLogin, isOn: Binding(get: { model.loginItemEnabled }, set: { on in Task { await model.setLoginItem(on) } }))
            primary(Copy.Onboarding.doneOpen) {
                Task {
                    await model.completeOnboarding()
                    dismissWindow(id: PulseScenes.onboardingID)
                }
            }
        }
    }

    var doneLine: String {
        if let seen = model.firstRealReadingAt { return Copy.Onboarding.doneConnected(clock(seen)) }
        if model.preview.installed { return Copy.Onboarding.doneWaiting }
        return Copy.Empty.noProviderTitle
    }

    // MARK: - Consent (UX_SPEC §2.2): real paths and the user's command, verbatim; nothing written before Install.

    @ViewBuilder var consent: some View {
        let preview = model.preview
        let existing = preview.existingCommand
        title(Copy.Explainer.title)
        // Plain wrapping text, not a scroll view: in a content-sized window a scroll view collapses to zero
        // height, and this paragraph is the disclosure the user consents to.
        Text(existing == nil ? Copy.Explainer.bodyNoExisting : Copy.Explainer.bodyExisting)
            .font(theme.font(.label)).foregroundStyle(theme.color(.textPrimary, scheme))
            .fixedSize(horizontal: false, vertical: true)
        VStack(alignment: .leading, spacing: theme.spacing(.compact)) {
            detail(Copy.Explainer.file(preview.settingsPath))
            detail(Copy.Explainer.backup(preview.backupsDir))
            if let existing { detail(Copy.Explainer.existingCommand(existing)) }
        }
        if let refusal = preview.refusal {
            Banner(text: Copy.Explainer.installFailed(AppModel.reason(refusal)), action: nil) {}
        } else if let installError {
            Banner(text: Copy.Explainer.installFailed(installError), action: nil) {}
        }
        HStack(spacing: theme.spacing(.standard)) {
            Button(Copy.Explainer.cancel) { go(.done) }.buttonStyle(PixelButtonStyle())
            Spacer()
            Button(existing == nil ? Copy.Explainer.ctaNoExisting : Copy.Explainer.ctaExisting) {
                installing = true
                Task {
                    switch await model.install() {
                    case .installed: installError = nil; go(.firstReading)
                    case .failed(let reason): installError = reason
                    }
                    installing = false
                }
            }
            .buttonStyle(PixelButtonStyle(prominent: true))
            .disabled(preview.refusal != nil || installing)
        }
    }

    // MARK: - Pieces

    func go(_ step: AppModel.OnboardingStep) { model.onboardingStep = step }

    func clock(_ date: Date) -> String { Formatting.clock(date, zone: model.environment.timeZone, locale: model.environment.locale) }

    func title(_ text: String) -> some View {
        Text(text).font(theme.font(.metricMedium)).foregroundStyle(theme.color(.textPrimary, scheme)).fixedSize(horizontal: false, vertical: true)
    }

    func body(_ text: String) -> some View {
        Text(text).font(theme.font(.label)).foregroundStyle(theme.color(.textSecondary, scheme)).fixedSize(horizontal: false, vertical: true)
    }

    func detail(_ text: String) -> some View {
        Text(text).font(theme.font(.supporting).monospaced()).foregroundStyle(theme.color(.textSecondary, scheme)).textSelection(.enabled)
    }

    func primary(_ label: String, action: @escaping () -> Void) -> some View {
        Button(label, action: action).buttonStyle(PixelButtonStyle(prominent: true)).keyboardShortcut(.defaultAction)
    }

    func secondary(_ label: String, action: @escaping () -> Void) -> some View {
        Button(label, action: action).buttonStyle(PixelButtonStyle())
    }
}

enum OnboardingMetrics {
    static let width: CGFloat = 480
}
