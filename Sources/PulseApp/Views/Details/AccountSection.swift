import DesignSystem
import SwiftUI

/// Account (1.10e, reworked in 1.12 after the founder's Twenty, Rive and GitBook picks): one centred column of sections,
/// each with its name and a line of explanation on the left and its content on the right; sign-in methods as rows; a
/// danger zone at the end.
struct AccountSection: View {
    @Bindable var model: AppModel
    @State private var name = ""
    @State private var email = ""
    @State private var choosingPlan = false
    @State private var confirmDelete = false
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var signedIn: Bool { if case .signedIn = model.account { true } else { false } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            section(Copy.AccountPage.profile, Copy.AccountPage.profileSub) {
                VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
                    Text(Copy.Account.name).font(theme.font(.micro)).foregroundStyle(theme.color(.textSecondary, scheme))
                    TextField(Copy.Account.namePlaceholder, text: $name)
                        .textFieldStyle(.plain).font(theme.font(.title)).foregroundStyle(theme.color(.textPrimary, scheme))
                        .padding(theme.spacing(.standard)).background(theme.color(.surfaceMuted, scheme))
                        .onChange(of: name) { _, new in Task { await model.setProfileName(new) } }
                    Text(model.greeting).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                }
            }
            section(Copy.AccountPage.plan, Copy.AccountPage.planSub) {
                HStack(spacing: theme.spacing(.standard)) {
                    PixelChip(text: (model.plan?.displayName ?? Copy.Account.planNotSet).uppercased(), lit: model.plan != nil)
                    Spacer()
                    Button(Copy.Account.change) { choosingPlan = true }.buttonStyle(PixelButtonStyle())
                }
            }
            section(Copy.AccountPage.signIn, Copy.AccountPage.signInSub) { signInMethods }
            if signedIn {
                section(Copy.AccountPage.sync, Copy.Sync.explainer) {
                    HStack(spacing: theme.spacing(.standard)) {
                        Text(model.lastSync.map { Copy.Sync.lastSynced(Formatting.age(of: $0, now: model.environment.clock.now(),
                                                                                    zone: model.environment.timeZone, locale: model.environment.locale)) }
                             ?? Copy.Sync.neverSynced)
                            .font(theme.font(.label)).foregroundStyle(theme.color(.textPrimary, scheme))
                        Spacer()
                        Button(Copy.Sync.syncNow) { Task { await model.syncNow() } }.buttonStyle(PixelButtonStyle(prominent: true))
                            .disabled(model.accountBusy || model.snapshot.isDemo)
                    }
                }
            }
            if let file = model.statsFile, let summary = model.statsSummary(.allTime) {
                let year = StatsCalendar.years(firstDay: file.firstSessionDate, today: summary.today).last ?? 0
                section("\(Copy.AccountPage.year) \(String(year))", Copy.AccountPage.yearSub) {
                    VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
                        // Sized from the column's known width: the section's right side is the column minus the label side.
                        let grid = StatsCalendar.year(year, stats: file, levels: summary.heatmap, today: summary.today, firstDay: file.firstSessionDate)
                        CalendarGridView(grid: grid, cell: CalendarGridView.cell(fitting: DetailsMetrics.settingsColumn - theme.spacing(.spacious) * 2,
                                                                                weeks: grid.weeks.count, theme: theme), showDayNumbers: false)
                        CalendarLegend()
                    }
                }
            }
            if let message = model.accountMessage {
                Text(message).font(theme.font(.supporting)).foregroundStyle(theme.color(.accent, scheme))
                    .fixedSize(horizontal: false, vertical: true).padding(.vertical, theme.spacing(.standard))
            }
            dangerZone.padding(.top, theme.spacing(.spacious))
        }
        .frame(maxWidth: DetailsMetrics.settingsColumn + DetailsMetrics.sideColumn, alignment: .leading)
        .frame(maxWidth: .infinity)
        .onAppear { name = model.profileName ?? "" }
        .task {
            model.loadStats()
            await model.refreshAccount()
        }
        .sheet(isPresented: $choosingPlan) {
            PlanPicker(model: model) { choosingPlan = false }.padding(theme.spacing(.spacious)).frame(width: SettingsMetrics.sheetWidth)
        }
        .confirmationDialog(Copy.Sync.deleteTitle, isPresented: $confirmDelete) {
            Button(Copy.Sync.deleteConfirm, role: .destructive) { Task { await model.deleteAccount() } }
        } message: {
            Text(Copy.Sync.deleteBody)
        }
    }

    /// Rive's layout: the section's name and a line on the left, its content on the right.
    func section(_ title: String, _ subtitle: String, @ViewBuilder _ content: () -> some View) -> some View {
        let body = content()
        return HStack(alignment: .top, spacing: theme.spacing(.spacious) * 1.5) {
            VStack(alignment: .leading, spacing: theme.spacing(.compact)) {
                Text(title.uppercased()).font(theme.font(.title)).foregroundStyle(theme.color(.accent, scheme)).accessibilityAddTraits(.isHeader)
                Text(subtitle).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme)).fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: DetailsMetrics.sideColumn, alignment: .leading)
            body.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, theme.spacing(.spacious))
        .overlay(alignment: .top) { Rectangle().fill(theme.color(.separator, scheme)).frame(height: theme.stroke(.hairline)) }
    }

    /// GitBook's sign-in rows: each method with its state and one action.
    var signInMethods: some View {
        VStack(alignment: .leading, spacing: 0) {
            methodRow("envelope", Copy.AccountPage.emailLink, emailState) {
                switch model.account {
                case .signedOut:
                    EmptyView()
                case .linkSent:
                    Button(Copy.Sync.differentEmail) { Task { await model.cancelSignIn() } }.buttonStyle(PixelButtonStyle())
                case .signedIn:
                    PixelChip(text: Copy.AccountPage.connected, lit: true)
                }
            }
            if case .signedOut = model.account {
                // The address on its own line under the method, so the field and button keep their size.
                HStack(spacing: theme.spacing(.standard)) {
                    TextField(Copy.Sync.emailPlaceholder, text: $email)
                        .textFieldStyle(.plain).font(theme.font(.label)).padding(theme.spacing(.standard))
                        .background(theme.color(.surfaceMuted, scheme))
                        .onSubmit { Task { await model.emailSignInLink(email) } }
                    Button(Copy.Sync.emailMe) { Task { await model.emailSignInLink(email) } }
                        .buttonStyle(PixelButtonStyle(prominent: true)).fixedSize().disabled(model.accountBusy || email.isEmpty)
                }
                .padding(.leading, theme.spacing(.spacious) * 1.6 + theme.spacing(.standard))
                .padding(.bottom, theme.spacing(.standard))
            }
            methodRow("letter:A", "Apple", Copy.AccountPage.soonSub) { soon }
            methodRow("letter:G", "Google", Copy.AccountPage.soonSub) { soon }
            methodRow("letter:GH", "GitHub", Copy.AccountPage.soonSub) { soon }
        }
    }

    var emailState: String {
        switch model.account {
        case .signedOut: Copy.AccountPage.emailSub
        case .linkSent(let address): Copy.Sync.linkSent(address)
        case .signedIn(let address): Copy.Sync.signedInAs(address)
        }
    }

    var soon: some View { Button(Copy.AccountPage.soon) {}.buttonStyle(PixelButtonStyle()).disabled(true) }

    func methodRow(_ symbol: String, _ title: String, _ subtitle: String, @ViewBuilder control: () -> some View) -> some View {
        HStack(alignment: .center, spacing: theme.spacing(.standard)) {
            // Providers as pixel monograms rather than their logos.
            Group {
                if symbol.hasPrefix("letter:") { Text(symbol.dropFirst(7)).font(theme.font(.title)) } else { PixelIcon(symbol: symbol) }
            }
            .frame(width: theme.spacing(.spacious) * 1.6, height: theme.spacing(.spacious) * 1.6)
                .foregroundStyle(theme.color(.accent, scheme))
                .background(PixelRect(step: theme.stroke(.hairline) * 2).fill(theme.color(.surfaceMuted, scheme))).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(theme.font(.label)).foregroundStyle(theme.color(.textPrimary, scheme))
                Text(subtitle).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: theme.spacing(.standard))
            control()
        }
        .padding(.vertical, theme.spacing(.standard))
        .accessibilityElement(children: .contain)
    }

    /// Twenty's danger zone, with GitBook's account actions.
    var dangerZone: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.standard)) {
            Text(Copy.AccountPage.danger).font(theme.font(.title)).foregroundStyle(theme.color(.statusBlocked, scheme))
            if signedIn {
                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(Copy.Sync.signOut).font(theme.font(.label)).foregroundStyle(theme.color(.textPrimary, scheme))
                        Text(Copy.AccountPage.signOutSub).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                    }
                    Spacer()
                    Button(Copy.Sync.signOut) { Task { await model.signOut() } }.buttonStyle(PixelButtonStyle())
                }
                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(Copy.AccountPage.deleteTitle).font(theme.font(.label)).foregroundStyle(theme.color(.statusBlocked, scheme))
                        Text(Copy.Sync.deleteBody).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button(Copy.Sync.deleteAccount) { confirmDelete = true }.buttonStyle(PixelButtonStyle())
                }
            } else {
                Text(Copy.AccountPage.dangerSignedOut).font(theme.font(.supporting)).foregroundStyle(theme.color(.textSecondary, scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(theme.spacing(.windowPadding))
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(PixelRect(step: theme.stroke(.hairline) * 2).strokeBorder(theme.color(.statusBlocked, scheme).opacity(0.6), lineWidth: theme.stroke(.hairline)))
    }
}
