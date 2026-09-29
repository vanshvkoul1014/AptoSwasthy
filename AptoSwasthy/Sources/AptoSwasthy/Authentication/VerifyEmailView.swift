import SwiftUI

struct VerifyEmailView: View {
    @EnvironmentObject var auth: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    let email: String
    @State private var code = ""
    @State private var cooldownRemaining = 0
    @FocusState private var isFocused: Bool

    private let cooldownTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            AnimatedGradientBackground()

            VStack(spacing: 0) {
                // Header with back button so the user isn't trapped in
                // code-entry if they mistyped their email or changed their mind.
                HStack {
                    if !auth.verificationSucceeded {
                        Button {
                            auth.dismissVerification()
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.tertiaryText)
                                .frame(width: 44, height: 44)
                        }
                        .disabled(auth.isLoading)
                    } else {
                        Color.clear.frame(width: 44, height: 44)
                    }
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)

                Spacer()

                VStack(spacing: 20) {
                    if auth.verificationSucceeded {
                        successContent
                    } else {
                        codeEntryContent
                    }
                }
                .padding(.horizontal, 32)

                Spacer()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: auth.verificationSucceeded)
        .animation(.easeInOut(duration: 0.2), value: auth.errorMessage)
        .keyboardDismissable()
        .onAppear {
            auth.errorMessage = nil
            if !auth.verificationSucceeded { isFocused = true }
            updateCooldown()
        }
        .onReceive(cooldownTimer) { _ in updateCooldown() }
        .presentationDetents([.large])
        .interactiveDismissDisabled(auth.isLoading)
    }

    // MARK: - Code entry

    private var codeEntryContent: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.pearlGreen.opacity(0.15))
                    .frame(width: 88, height: 88)
                Image(systemName: "envelope.badge.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(LinearGradient(colors: [.pearlGreen, .pearlMint],
                                                    startPoint: .topLeading, endPoint: .bottomTrailing))
            }

            VStack(spacing: 8) {
                Text("Check your email")
                    .font(.pearlTitle2)
                    .foregroundColor(.primaryText)

                Text("We sent a 6-digit code to\n\(email)")
                    .font(.pearlSubheadline)
                    .foregroundColor(.tertiaryText)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 14) {
                TextField("123456", text: $code)
                    .textFieldStyle(GlassTextFieldStyle())
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .focused($isFocused)
                    .onChange(of: code) { _, new in
                        code = String(new.filter { $0.isNumber }.prefix(6))
                        if code.count == 6 { verify() }
                    }

                if let error = auth.errorMessage {
                    Text(error)
                        .font(.pearlCaption)
                        .foregroundColor(.riskHigh)
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                }

                Button {
                    verify()
                } label: {
                    Group {
                        if auth.isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Text("Verify")
                                .font(.pearlHeadline)
                                .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity).frame(height: 56)
                    .background(LinearGradient(colors: [.pearlGreen, .pearlMint],
                                               startPoint: .leading, endPoint: .trailing))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .disabled(code.count < 6 || auth.isLoading)

                Button {
                    auth.resendCode(email: email)
                    updateCooldown()
                } label: {
                    Text(cooldownRemaining > 0 ? "Resend code in \(cooldownRemaining)s" : "Resend code")
                        .font(.pearlCaption)
                        .foregroundColor(cooldownRemaining > 0 ? .quaternaryText : .tertiaryText)
                }
                .disabled(cooldownRemaining > 0)
            }
            .transition(.opacity)
        }
    }

    // MARK: - Success

    private var successContent: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.pearlGreen.opacity(0.15))
                    .frame(width: 104, height: 104)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(LinearGradient(colors: [.pearlGreen, .pearlMint],
                                                    startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .padding(.bottom, 6)

            Text("Email verified!")
                .font(.pearlTitle2)
                .foregroundColor(.primaryText)

            Text("Your account is ready. You can now sign in and start using AptoSwasthy.")
                .font(.pearlSubheadline)
                .foregroundColor(.tertiaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            Button {
                auth.dismissVerification()
                dismiss()
            } label: {
                Text("Sign In")
                    .font(.pearlHeadline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity).frame(height: 56)
                    .background(LinearGradient(colors: [.pearlGreen, .pearlMint],
                                               startPoint: .leading, endPoint: .trailing))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(.top, 8)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    // MARK: - Helpers

    private func verify() {
        guard code.count == 6 else { return }
        auth.errorMessage = nil
        auth.verifyEmail(code: code, email: email)
    }

    private func updateCooldown() {
        guard let until = auth.resendCooldownUntil else {
            cooldownRemaining = 0
            return
        }
        let remaining = Int(until.timeIntervalSinceNow.rounded(.up))
        cooldownRemaining = max(0, remaining)
    }
}
