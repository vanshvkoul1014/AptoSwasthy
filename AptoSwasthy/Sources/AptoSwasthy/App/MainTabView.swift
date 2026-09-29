import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house.fill", value: 0) {
                HomeView()
            }
            Tab("Risks", systemImage: "shield.fill", value: 1) {
                RisksView()
            }
            Tab("Pearl", systemImage: "sparkles", value: 2) {
                AITabView()
            }
            Tab("You", systemImage: "person.fill", value: 3) {
                YouTabView()
            }
        }
        .tint(.pearlGreen)
    }
}
