import Foundation
import Sync

extension AppModel {
    public var enabledSignInProviders: Set<SyncClient.Provider> { environment.sync.enabledProviders }

    /// A user action opens the configured provider's sign-in in the default browser. PKCE binds its single-use
    /// callback to this Mac; the existing clepso:// callback completes the session. Public alpha builds have no
    /// accounts project and no enabled providers, so this cannot open or contact an account service there.
    public func signIn(provider: SyncClient.Provider) async {
        guard accountsAvailable, enabledSignInProviders.contains(provider), !accountBusy else { return }
        guard let url = await environment.sync.providerURL(provider) else { return }
        accountMessage = Copy.ProviderSignIn.continueInBrowser
        environment.openLink(url)
    }
}
