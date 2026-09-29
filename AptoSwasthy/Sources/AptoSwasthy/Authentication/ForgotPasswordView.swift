import SwiftUI

struct ForgotPasswordView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    let prefillEmail: String

    @State private var email: String
    @State private var codeSent = false
    @State private var code = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var showSuccess = false

    init(prefillEmail: String) {
        self.prefillEmail = prefillEmail
        _email = State(initialValue: prefillEmail)
    }

    private var passwordsMatch: Bool { newPassword == confirmPassword }
    private var newPasswordValid: Bool {
        newPassword.count >= 8 &&
        newPassword.contains(where: \.isUppercase) &&
        newPassword.contains(where: \.isLowercase) &&
        newPassword.contains(where: \.isNumber)
    }
    private var canReset: Bool {
        code.count == 6 && code.allSatisfy(\.isNumber) && newPasswordValid && passwordsMatch
    }

    var body: some View {
        ZStack {
            AnimatedGradientBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 6) {
                        Text(codeSent ? "Enter Reset Code" : "Reset Password")
                            .font(.pearlTitle2)
                            .foregroundColor(.primaryText)
                        Text(codeSent
                             ? "Enter the 6-digit code sent to \(email) and choose a new password."
                             : "We'll send a reset code to your email address.")
                            .font(.pearlSubheadline)
                            .foregroundColor(.tertiaryText)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 32)

                    if !codeSent {
                        // Step 1: collect email and send code
                        VStack(spacing: 16) {
                            TextField("Email", text: $email)
                                .textFieldStyle(GlassTextFieldStyle())
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()

                            if let msg = auth.errorMessage {
                                Text(msg)
                                    .font(.pearlCaption)
                                    .foregroundColor(.riskHigh)
                                    .multilineTextAlignment(.center)
                            }

                            Button {
                                auth.forgotPassword(email: email)
                                codeSent = true
                            } label: {
                                if auth.isLoading {
                                    ProgressView().tint(.black)
                                        .frame(maxWidth: .infinity).frame(height: 52)
                                } else {
                                    Text("Send Reset Code")
                                        .font(.pearlHeadline).foregroundColor(.black)
                                        .frame(maxWidth: .infinity).frame(height: 52)
                                }
                            }
                            .background(LinearGradient(colors: [.pearlGreen, .pearlMint], startPoint: .leading, endPoint: .trailing))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .disabled(email.isEmpty || auth.isLoading)
                        }
                    } else {
                        // Step 2: enter code + new password
                        VStack(spacing: 14) {
                            TextField("6-digit code", text: $code)
                                .textFieldStyle(GlassTextFieldStyle())
                                .keyboardType(.numberPad)

                            SecureField("New password", text: $newPassword)
                                .textFieldStyle(GlassTextFieldStyle())

                            SecureField("Confirm new password", text: $confirmPassword)
                                .textFieldStyle(GlassTextFieldStyle())

                            // Password hints
                            VStack(alignment: .leading, spacing: 4) {
                                PasswordHint(text: "At least 8 characters", met: newPassword.count >= 8)
                                PasswordHint(text: "Uppercase letter", met: newPassword.contains(where: \.isUppercase))
                                PasswordHint(text: "Lowercase letter", met: newPassword.contains(where: \.isLowercase))
                                PasswordHint(text: "Number", met: newPassword.contains(where: \.isNumber))
                                if !confirmPassword.isEmpty {
                                    PasswordHint(text: "Passwords match", met: passwordsMatch)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            if let msg = auth.errorMessage {
                                Text(msg)
                                    .font(.pearlCaption)
                                    .foregroundColor(.riskHigh)
                                    .multilineTextAlignment(.center)
                            }

                            Button {
                                Task {
                                    let ok = await auth.confirmForgotPassword(
                                        email: email, code: code, newPassword: newPassword)
                                    if ok { showSuccess = true }
                                }
                            } label: {
                                if auth.isLoading {
                                    ProgressView().tint(.black)
                                        .frame(maxWidth: .infinity).frame(height: 52)
                                } else {
                                    Text("Reset Password")
                                        .font(.pearlHeadline).foregroundColor(.black)
                                        .frame(maxWidth: .infinity).frame(height: 52)
                                }
                            }
                            .background(LinearGradient(
                                colors: [canReset ? .pearlGreen : Color.glassBackground,
                                         canReset ? .pearlMint  : Color.glassBackground],
                                startPoint: .leading, endPoint: .trailing))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .disabled(!canReset || auth.isLoading)

                            Button {
                                auth.forgotPassword(email: email)
                            } label: {
                                Text("Resend code")
                                    .font(.pearlCaption)
                                    .foregroundColor(.tertiaryText)
                            }
                        }
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 32)
            }
        }
        .alert("Password Reset", isPresented: $showSuccess) {
            Button("Sign In") { dismiss() }
        } message: {
            Text("Your password has been reset. Sign in with your new password.")
        }
        .keyboardDismissable()
        .onAppear { auth.errorMessage = nil }
    }
}

private struct PasswordHint: View {
    let text: String
    let met: Bool
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 12))
                .foregroundColor(met ? .pearlGreen : .quaternaryText)
            Text(text)
                .font(.pearlCaption)
                .foregroundColor(met ? .secondaryText : .quaternaryText)
        }
    }
}
