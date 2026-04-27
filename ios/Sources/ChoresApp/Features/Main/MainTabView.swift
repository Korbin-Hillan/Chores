import SwiftUI

struct MainTabView: View {
    @Environment(AuthStore.self) private var authStore

    var body: some View {
        TabView {
            TodayView()
                .tabItem {
                    Label("Today", systemImage: "sun.max")
                }
            ChoreListView()
                .tabItem {
                    Label("By room", systemImage: "square.grid.2x2")
                }
            FeedView()
                .tabItem {
                    Label("Feed", systemImage: "list.bullet.below.rectangle")
                }
            LeaderboardView()
                .tabItem {
                    Label("Leaderboard", systemImage: "trophy")
                }
            RewardsView()
                .tabItem {
                    Label("Rewards", systemImage: "gift")
                }
            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.circle")
                }
        }
    }
}

#Preview {
    MainTabView()
        .environment(AuthStore())
}
