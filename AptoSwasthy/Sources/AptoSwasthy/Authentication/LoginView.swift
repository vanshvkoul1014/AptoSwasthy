import SwiftUI

struct LoginView: View {
    @EnvironmentObject var auth: AuthViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var showSignUp = false
    @State private var showGoogleSignIn = false
    @State private var showForgotPassword = false
    @FocusState private var focused: LoginField?

    enum LoginField { case email, password }

    var body: some View {
        ZStack {
            AnimatedGradientBackground()

            VStack(spacing: 0) {
                Spacer()

                // Logo
                VStack(spacing: 12) {
                    Image(systemName: "heart.text.clipboard.fill")
                        .font(.system(size: 56, weight: .light))
                        .foregroundStyle(LinearGradient(
                            colors: [.pearlGreen, .pearlMint],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text("AptoSwasthy")
                        .font(.pearlLargeTitle)
                        .foregroundColor(.primaryText)
                }
                .padding(.bottom, 52)

                // Form
                VStack(spacing: 14) {
                    TextField("Email", text: $email)
                        .textFieldStyle(GlassTextFieldStyle())
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .focused($focused, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focused = .password }

                    SecureField("Password", text: $password)
                        .textFieldStyle(GlassTextFieldStyle())
                        .focused($focused, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { auth.login(email: email, password: password) }

                    if let error = auth.errorMessage {
                        Text(error)
                            .font(.pearlCaption)
                            .foregroundColor(.riskHigh)
                            .multilineTextAlignment(.center)
                            .transition(.opacity)
                    }

                    // Sign In
                    Button {
                        focused = nil
                        auth.login(email: email, password: password)
                    } label: {
                        Group {
                            if auth.isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Text("Sign In")
                                    .font(.pearlHeadline)
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(maxWidth: .infinity).frame(height: 56)
                        .background(LinearGradient(colors: [.pearlGreen, .pearlMint],
                                                   startPoint: .leading, endPoint: .trailing))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .disabled(auth.isLoading)

                    // Divider
                    HStack {
                        Rectangle().frame(height: 1).foregroundColor(.quaternaryText)
                        Text("or").font(.pearlCaption).foregroundColor(.quaternaryText)
                        Rectangle().frame(height: 1).foregroundColor(.quaternaryText)
                    }
                    .padding(.vertical, 4)

                    // Google Sign In
                    Button {
                        showGoogleSignIn = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "globe")
                                .font(.system(size: 17, weight: .medium))
                            Text("Sign in with Google")
                                .font(.pearlSubheadline)
                        }
                        .foregroundColor(.secondaryText)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .glassBackground(cornerRadius: 14)
                    }

                    // Footer links
                    HStack(spacing: 0) {
                        Button("Create Account") {
                            auth.errorMessage = nil
                            showSignUp = true
                        }
                        .font(.pearlCaption)
                        .foregroundColor(.pearlGreen)

                        Text("  ·  ").font(.pearlCaption).foregroundColor(.quaternaryText)

                        Button("Forgot Password?") {
                            auth.errorMessage = nil
                            showForgotPassword = true
                        }
                        .font(.pearlCaption)
                        .foregroundColor(.tertiaryText)
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 32)

                Spacer()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: auth.errorMessage)
        .keyboardDismissable()
        // Verify email sheet (after sign-up)
        .sheet(item: pendingEmailBinding) { email in
            VerifyEmailView(email: email.value)
        }
        // Sign Up sheet
        .sheet(isPresented: $showSignUp) {
            SignUpView()
        }
        // Google sign-in (ASWebAuthenticationSession via sheet)
        .sheet(isPresented: $showGoogleSignIn) {
            GoogleSignInWebView(
                url: auth.googleSignInURL(),
                onCallback: { url in
                    showGoogleSignIn = false
                    auth.handleGoogleCallback(url: url)
                }
            )
        }
        // Forgot password sheet
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordView(prefillEmail: email)
                .environmentObject(auth)
        }
    }

    // Bridge pendingVerificationEmail (String?) to .sheet(item:)
    private var pendingEmailBinding: Binding<IdentifiableString?> {
        Binding(
            get: { auth.pendingVerificationEmail.map { IdentifiableString($0) } },
            set: { if $0 == nil { auth.pendingVerificationEmail = nil } }
        )
    }
}

// MARK: - Helpers

private struct IdentifiableString: Identifiable {
    var id: String { value }
    let value: String
    init(_ value: String) { self.value = value }
}

// MARK: - GlassTextFieldStyle (unchanged)

struct GlassTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.pearlBody)
            .foregroundColor(.primaryText)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(Color.glassBackground)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.glassBorder, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
