import DesignSystem
import SwiftUI

struct PhoneRoot: View {
    @Bindable var model: PhoneModel
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    @State private var settings = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing(.spacious)) {
                    Text("YOUR LIMITS. WITHIN REACH.").font(theme.font(.title)).foregroundStyle(theme.color(.accent,scheme))
                    CompanionLimitsView(envelope: model.envelope, now: model.now,
                        emptyMessage: !model.signedIn ? "Sign in with the same Clepso account as your Mac, then enable mobile sharing on the Mac." : "Waiting for your Mac to share a reading.")
                    if let message = model.message { Text(message).font(theme.font(.supporting)) }
                    if !model.signedIn {
                        Button { settings = true } label: {
                            Text("Sign in").frame(minHeight: theme.spacing(.section))
                        }.buttonStyle(PixelButtonStyle(prominent:true))
                    }
                }.padding(theme.spacing(.spacious))
            }
            .background(theme.color(.background,scheme)).foregroundStyle(theme.color(.textPrimary,scheme))
            .navigationTitle("CLEPSO").toolbar {
                ToolbarItem(placement:.topBarTrailing) { Button("Settings") { settings = true } }
            }.refreshable { await model.refresh() }
            .sheet(isPresented:$settings) { account }
        }
    }
    private var account: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    if model.signedIn {
                        Text(model.signedInEmail ?? "Connected account")
                        Button("Sign out") { Task { await model.signOut() } }
                    } else {
                        LabeledContent("Email") {
                            TextField("you@example.com",text:$model.email).textContentType(.emailAddress).keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityLabel("Email address")
                        }
                        Button("Email sign-in link") { Task { await model.requestLink() } }.disabled(model.busy || !model.email.contains("@"))
                        if let pending = model.pendingEmail { Text("Link requested for \(pending). Open it on this iPhone.") }
                    }
                }
                Section("Expected reset reminders") {
                    Toggle("Reminders",isOn:Binding(get:{model.reminders},set:{enabled in Task{await model.setReminders(enabled)}})).toggleStyle(PixelToggleStyle())
                    Picker("Notify",selection:Binding(get:{model.leadMinutes},set:{value in Task{await model.setLead(value)}})) {
                        Text("At the reported reset").tag(0)
                        Text("5 minutes before").tag(5)
                        Text("15 minutes before").tag(15)
                    }
                    Text("Reminders describe a reported expected time, not confirmed availability. Fresh readings replace pending reminders. An offline phone may miss a cancellation. Apple Watch notification mirroring follows your system settings.")
                }
                Section("Sharing") {
                    Text("Your Mac must separately enable mobile sharing. Only aggregate provider limits and timestamps are relayed through your account. The paired Watch receives that snapshot; account credentials stay on this iPhone.")
                    if let message = model.message { Text(message) }
                    Button("Refresh reading") { Task { await model.refresh() } }.disabled(model.busy || !model.signedIn)
                }
            }.navigationTitle("Clepso settings").toolbar {
                ToolbarItem(placement:.confirmationAction) { Button("Done") { settings = false } }
            }
        }.font(theme.font(.label))
    }
}
