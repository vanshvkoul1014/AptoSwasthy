import SwiftUI
import UIKit

struct SettingsView: View {
    @Binding var profile: UserProfile?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthViewModel
    @AppStorage("appColorScheme") private var appColorScheme = "system"
    @State private var showBloodTestImport = false
    @State private var showBloodTestHistory = false
    @State private var showConnectedApps = false
    @State private var showDeleteConfirm = false
    @State private var showPersonalDetails = false
    @State private var showExportAlert = false
    @State private var showPrivacyAlert = false

    var body: some View {
        ZStack {
            AnimatedGradientBackground()

            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    HStack {
                        Text("Settings").font(.pearlTitle).foregroundColor(.primaryText)
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.quaternaryText)
                        }
                    }
                    .padding(.top, 24)

                    // Display
                    SettingsSection(title: "Display") {
                        // Appearance
                        SettingsRow(icon: "circle.lefthalf.filled", title: "Appearance") {
                            Picker("", selection: $appColorScheme) {
                                Text("System").tag("system")
                                Text("Light").tag("light")
                                Text("Dark").tag("dark")
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 200)
                        }

                        if let p = profile {
                            SettingsRow(icon: "ruler", title: "Units") {
                                Picker("", selection: Binding(
                                    get: { p.unitPreference },
                                    set: { profile?.unitPreference = $0; PersistenceService.shared.save() }
                                )) {
                                    Text("Imperial").tag(UnitSystem.imperial)
                                    Text("Metric (SI)").tag(UnitSystem.si)
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 180)
                            }
                        }
                    }

                    SettingsSection(title: "Security") {
                        if let p = profile {
                            SettingsToggleRow(
                                icon: "faceid",
                                title: "Face ID Login",
                                isOn: Binding(
                                    get: { p.faceIDEnabled },
                                    set: { profile?.faceIDEnabled = $0; PersistenceService.shared.save() }
                                )
                            )
                        }
                    }

                    SettingsSection(title: "Notifications") {
                        SettingsButtonRow(icon: "bell.fill", title: "Habit Reminders") {
                            openNotificationSettings()
                        }
                        SettingsButtonRow(icon: "chart.line.uptrend.xyaxis", title: "Metric Alerts") {
                            openNotificationSettings()
                        }
                        SettingsButtonRow(icon: "sparkles", title: "Pearl Check-ins") {
                            openNotificationSettings()
                        }
                    }

                    SettingsSection(title: "Data") {
                        SettingsButtonRow(icon: "heart.text.clipboard", title: "Connected Apps") {
                            showConnectedApps = true
                        }
                        SettingsButtonRow(icon: "doc.richtext", title: "Import Blood Test") {
                            showBloodTestImport = true
                        }
                        SettingsButtonRow(icon: "chart.line.uptrend.xyaxis", title: "Blood Test History") {
                            showBloodTestHistory = true
                        }
                        SettingsButtonRow(icon: "person.crop.rectangle", title: "Personal Details") {
                            showPersonalDetails = true
                        }
                    }

                    SettingsSection(title: "Privacy") {
                        SettingsButtonRow(icon: "lock.shield", title: "Privacy & Data") {
                            showPrivacyAlert = true
                        }
                        SettingsButtonRow(icon: "square.and.arrow.up", title: "Export My Data") {
                            showExportAlert = true
                        }

                        Button {
                            showDeleteConfirm = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "trash")
                                    .foregroundColor(.riskHigh)
                                    .frame(width: 24)
                                Text("Delete Account")
                                    .font(.pearlCallout)
                                    .foregroundColor(.riskHigh)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                    }

                    Text("AptoSwasthy handles health data in compliance with HIPAA requirements. Sensitive biometric and medical data is encrypted at rest and in transit.")
                        .font(.pearlCaption)
                        .foregroundColor(.quaternaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 20)
            }
        }
        .sheet(isPresented: $showBloodTestImport) {
            BloodTestImportView()
        }
        .sheet(isPresented: $showBloodTestHistory) {
            BloodTestHistoryView()
        }
        .sheet(isPresented: $showConnectedApps) {
            ConnectedAppsView()
        }
        .sheet(isPresented: $showPersonalDetails) {
            if let p = profile {
                PersonalDetailsEditView(profile: p)
            }
        }
        .alert("Delete Account", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { deleteAccount() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all your data. This cannot be undone.")
        }
        .alert("Privacy & Data", isPresented: $showPrivacyAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("AptoSwasthy processes all health data on-device. Your data is never sold or shared with third parties. Full privacy policy available at aptoswasthy.com/privacy.")
        }
        .alert("Export My Data", isPresented: $showExportAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Data export is coming soon. You'll be able to download your health data as a CSV or PDF report.")
        }
    }

    private func deleteAccount() {
        UserDefaults.standard.removeObject(forKey: "firstSnapshotShown")
        dismiss()
        auth.logout()
    }

    private func openNotificationSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Section

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.pearlFootnote.weight(.semibold))
                .foregroundColor(.quaternaryText)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                content
            }
            .background(Color.glassBackground)
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.glassBorder, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

struct SettingsRow<Trailing: View>: View {
    let icon: String
    let title: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.pearlGreen)
                .frame(width: 24)
            Text(title).font(.pearlCallout).foregroundColor(.primaryText)
            Spacer()
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

struct SettingsToggleRow: View {
    let icon: String
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundColor(.pearlGreen).frame(width: 24)
            Text(title).font(.pearlCallout).foregroundColor(.primaryText)
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden().tint(.pearlGreen)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

struct SettingsButtonRow: View {
    let icon: String
    let title: String
    var detail: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundColor(.pearlGreen).frame(width: 24)
                Text(title).font(.pearlCallout).foregroundColor(.primaryText)
                Spacer()
                if let detail {
                    Text(detail).font(.pearlSubheadline).foregroundColor(.quaternaryText)
                }
                Image(systemName: "chevron.right").font(.system(size: 13)).foregroundColor(.quaternaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }
}
