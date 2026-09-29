import SwiftUI
import AuthenticationServices

/// Opens Cognito's hosted UI for Google sign-in via ASWebAuthenticationSession.
/// Requires Google to be added as a federated IdP in the Cognito User Pool.
struct GoogleSignInWebView: View {
    let url: URL?
    let onCallback: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var sessionHolder = WebAuthHolder()

    var body: some View {
        ZStack {
            AnimatedGradientBackground()
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "globe")
                    .font(.system(size: 48))
                    .foregroundColor(.quaternaryText)
                Text("Signing in with Google...")
                    .font(.pearlSubheadline)
                    .foregroundColor(.tertiaryText)
                ProgressView().tint(.pearlGreen)
                Spacer()
            }
        }
        .onAppear { startSession() }
    }

    private func startSession() {
        guard let url else { dismiss(); return }

        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: "aptoswasthy"
        ) { callbackURL, error in
            if let callbackURL {
                onCallback(callbackURL)
            } else {
                dismiss()
            }
        }
        session.presentationContextProvider = sessionHolder
        session.prefersEphemeralWebBrowserSession = false
        sessionHolder.session = session
        session.start()
    }
}

/// Holds the ASWebAuthenticationSession to keep it alive and provides presentation context.
@MainActor
private class WebAuthHolder: NSObject, ASWebAuthenticationPresentationContextProviding, ObservableObject {
    var session: ASWebAuthenticationSession?

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.keyWindow ?? ASPresentationAnchor()
    }
}
