import SwiftUI

struct SignUpView: View {
    @EnvironmentObject var auth: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var passwordMismatch = false
    @FocusState private var focused: Field?

    enum Field { case name, email, password, confirm }

    var body: some View {
        ZStack {
            AnimatedGradientBackground()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 26))
                            .foregroundColor(.quaternaryText)
                    }
                    Spacer()
                    Text("Create Account")
                        .font(.pearlHeadline)
                        .foregroundColor(.primaryText)
                    Spacer()
                    Color.clear.frame(width: 26, height: 26)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 32)

                VStack(spacing: 14) {
                    TextField("Full name", text: $name)
                        .textFieldStyle(GlassTextFieldStyle())
                        .textContentType(.name)
                        .focused($focused, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focused = .email }

                    TextField("Email", text: $email)
                        .textFieldStyle(GlassTextFieldStyle())
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .focused($focused, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focused = .password }

                    SecureField("Password (8+ characters)", text: $password)
                        .textFieldStyle(GlassTextFieldStyle())
                        .focused($focused, equals: .password)
                        .submitLabel(.next)
                        .onSubmit { focused = .confirm }

                    SecureField("Confirm password", text: $confirmPassword)
                        .textFieldStyle(GlassTextFieldStyle())
                        .focused($focused, equals: .confirm)
                        .submitLabel(.go)
                        .onSubmit { attemptSignUp() }

                    if passwordMismatch {
                        Text("Passwords don't match.")
                            .font(.pearlCaption)
                            .foregroundColor(.riskHigh)
                            .transition(.opacity)
                    }

                    if let error = auth.errorMessage {
                        Text(error)
                            .font(.pearlCaption)
                            .foregroundColor(.riskHigh)
                            .multilineTextAlignment(.center)
                            .transition(.opacity)
                    }

                    Button {
                        focused = nil
                        attemptSignUp()
                    } label: {
                        Group {
                            if auth.isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Text("Create Account")
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

                    Text("By creating an account you agree to our Terms of Service and Privacy Policy.")
                        .font(.pearlCaption2)
                        .foregroundColor(.quaternaryText)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 32)

                Spacer()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: passwordMismatch)
        .animation(.easeInOut(duration: 0.2), value: auth.errorMessage)
        .keyboardDismissable()
        .onAppear { auth.errorMessage = nil }
        .sheet(item: pendingEmailBinding) { item in
            VerifyEmailView(email: item.value)
        }
        .onChange(of: auth.pendingVerificationEmail) { _, new in
            if new == nil { dismiss() } // email verified, dismiss sign-up too
        }
    }

    private func attemptSignUp() {
        passwordMismatch = false
        auth.errorMessage = nil

        guard password.count >= 8,
              password.contains(where: \.isUppercase),
              password.contains(where: \.isLowercase),
              password.contains(where: \.isNumber) else {
            auth.errorMessage = "Password must be 8+ characters with uppercase, lowercase, and a number."
            return
        }
        guard password == confirmPassword else {
            passwordMismatch = true
            return
        }
        auth.signUp(email: email, password: password, name: name)
    }

    private var pendingEmailBinding: Binding<IdentifiableString?> {
        Binding(
            get: { auth.pendingVerificationEmail.map { IdentifiableString($0) } },
            set: { if $0 == nil { auth.pendingVerificationEmail = nil } }
        )
    }
}

private struct IdentifiableString: Identifiable {
    var id: String { value }
    let value: String
    init(_ value: String) { self.value = value }
}
