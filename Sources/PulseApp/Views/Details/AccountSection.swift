import DesignSystem
import SwiftUI

/// Increment 1.10e: the profile (the name Home greets), the plan, the year, and where sign-in will go
/// (ACCOUNTS_AND_SYNC; not active yet, and said so).
struct AccountSection: View {
    @Bindable var model: AppModel
    @State private var name = ""
    @State private var choosingPlan = false
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.spacious)) {
            if let file = model.statsFile, let summary = model.statsSummary(.allTime) {
                let years = StatsCalendar.years(firstDay: file.firstSessionDate, today: summary.today)
                let year = years.last ?? 0
                PixelPanel {
                    VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
                        Text("\(Copy.Account.year) · \(String(year))").font(theme.font(.title)).foregroundStyle(theme.color(.accent, scheme))
                        FittedCalendar(grid: StatsCalendar.year(year, stats: file, levels: summary.heatmap, today: summary.today, firstDay: file.firstSessionDate))
                        CalendarLegend()
                    }
                }
            }
            HStack(alignment: .top, spacing: theme.spacing(.spacious)) {
                PixelPanel {
                    VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
                        Text(Copy.Account.profile).font(theme.font(.title)).foregroundStyle(theme.color(.accent, scheme))
                        Text(Copy.Account.name).font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
                        TextField(Copy.Account.namePlaceholder, text: $name)
                            .textFieldStyle(.plain).font(theme.font(.metricMedium)).foregroundStyle(theme.color(.textPrimary, scheme))
                            .padding(theme.spacing(.standard))
                            .background(theme.color(.surfaceMuted, scheme))
                            .onSubmit { Task { await model.setProfileName(name) } }
                            .onChange(of: name) { _, new in Task { await model.setProfileName(new) } }
                        Text(model.greeting).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                PixelPanel {
                    VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
                        Text(Copy.Account.plan).font(theme.font(.title)).foregroundStyle(theme.color(.accent, scheme))
                        PixelChip(text: (model.plan?.displayName ?? Copy.Account.planNotSet).uppercased(), lit: model.plan != nil)
                        Button(Copy.Account.change) { choosingPlan = true }.buttonStyle(PixelButtonStyle())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            PixelPanel { AccountCard(model: model) }
        }
        .onAppear { name = model.profileName ?? "" }
        .task { model.loadStats() }
        .sheet(isPresented: $choosingPlan) {
            PlanPicker(model: model) { choosingPlan = false }
                .padding(theme.spacing(.spacious))
                .frame(width: SettingsMetrics.sheetWidth)
        }
    }
}

/// ROADMAP 2.0: sign in with an email link, see what's uploaded, upload now, sign out, delete the account.
struct AccountCard: View {
    @Bindable var model: AppModel
    @State private var email = ""
    @State private var confirmDelete = false
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
            Text(Copy.Sync.title).font(theme.font(.title)).foregroundStyle(theme.color(.accent, scheme))
            switch model.account {
            case .signedOut:
                Text(Copy.Sync.explainer).font(theme.font(.label)).foregroundStyle(theme.color(.textPrimary, scheme))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: theme.spacing(.standard)) {
                    TextField(Copy.Sync.emailPlaceholder, text: $email)
                        .textFieldStyle(.plain).font(theme.font(.label)).textContentType(.emailAddress)
                        .padding(theme.spacing(.standard)).background(theme.color(.surfaceMuted, scheme))
                        .frame(maxWidth: DetailsMetrics.sideColumn * 1.5)
                        .onSubmit { Task { await model.emailSignInLink(email) } }
                    Button(Copy.Sync.emailMe) { Task { await model.emailSignInLink(email) } }
                        .buttonStyle(PixelButtonStyle(prominent: true)).disabled(model.accountBusy || email.isEmpty)
                }
                Text(Copy.Sync.providersSoon).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
            case .linkSent(let address):
                Text(Copy.Sync.linkSent(address)).font(theme.font(.label)).foregroundStyle(theme.color(.textPrimary, scheme))
                    .fixedSize(horizontal: false, vertical: true)
                Button(Copy.Sync.differentEmail) { Task { await model.cancelSignIn() } }.buttonStyle(PixelButtonStyle())
            case .signedIn(let address):
                Text(Copy.Sync.signedInAs(address)).font(theme.font(.label)).foregroundStyle(theme.color(.textPrimary, scheme))
                Text(model.lastSync.map { Copy.Sync.lastSynced(Formatting.age(of: $0, now: model.environment.clock.now(),
                                                                            zone: model.environment.timeZone, locale: model.environment.locale)) }
                     ?? Copy.Sync.neverSynced)
                    .font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                if model.snapshot.isDemo {
                    Text(Copy.Sync.demoNote).font(theme.font(.supporting)).foregroundStyle(theme.color(.statusAttention, scheme))
                }
                HStack(spacing: theme.spacing(.standard)) {
                    Button(Copy.Sync.syncNow) { Task { await model.syncNow() } }.buttonStyle(PixelButtonStyle(prominent: true))
                        .disabled(model.accountBusy || model.snapshot.isDemo)
                    Button(Copy.Sync.signOut) { Task { await model.signOut() } }.buttonStyle(PixelButtonStyle())
                    Button(Copy.Sync.deleteAccount) { confirmDelete = true }.buttonStyle(PixelButtonStyle())
                }
                Text(Copy.Sync.explainer).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let message = model.accountMessage {
                Text(message).font(theme.font(.supporting)).foregroundStyle(theme.color(.accent, scheme)).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await model.refreshAccount() }
        .confirmationDialog(Copy.Sync.deleteTitle, isPresented: $confirmDelete) {
            Button(Copy.Sync.deleteConfirm, role: .destructive) { Task { await model.deleteAccount() } }
        } message: {
            Text(Copy.Sync.deleteBody)
        }
    }
}

