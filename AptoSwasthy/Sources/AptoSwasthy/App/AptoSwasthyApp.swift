import SwiftUI
import SwiftData

@main
struct AptoSwasthyApp: App {
    @State private var authViewModel = AuthViewModel()
    @AppStorage("appColorScheme") private var appColorScheme = "system"
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // If the app was deleted and reinstalled, Keychain items survive but
        // UserDefaults doesn't - this clears stale tokens so the user must
        // sign in again on a fresh install.
        KeychainService.shared.clearTokensIfFreshInstall()
    }

    private var preferredScheme: ColorScheme? {
        switch appColorScheme {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil  // follow system
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authViewModel)
                .modelContainer(PersistenceService.shared.container)
                .preferredColorScheme(preferredScheme)
                .task {
                    await HealthKitService.shared.syncIfAuthorized()
                    _ = await NotificationService.shared.requestAuthorization()
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .background:
                        NotificationService.shared.scheduleReEngagementNotification()
                    case .active:
                        NotificationService.shared.cancelReEngagementNotification()
                    default: break
                    }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var auth: AuthViewModel
    @Environment(\.modelContext) private var context
    @State private var showSplash = true
    @State private var authReady = false

    var body: some View {
        ZStack {
            Group {
                if auth.isAuthenticated {
                    MainTabView()
                } else {
                    LoginView()
                }
            }
            .animation(.easeInOut(duration: 0.4), value: auth.isAuthenticated)

            if showSplash {
                SplashScreenView(isShowing: $showSplash, authReady: $authReady)
                    .ignoresSafeArea()
                    .zIndex(100)
                    .transition(.opacity)
            }
        }
        .task {
            await auth.attemptAutoLogin()
            authReady = true
        }
    }
}
