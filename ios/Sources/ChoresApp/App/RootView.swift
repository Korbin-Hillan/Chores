import SwiftUI

struct RootView: View {
    @Environment(AuthStore.self) private var authStore

    var body: some View {
        switch authStore.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .unauthenticated:
            WelcomeView()

        case .authenticated:
            if authStore.currentHouseholdId == nil {
                HouseholdOnboardingView()
            } else {
                MainTabView()
            }
        }
    }
}

#Preview {
    RootView()
        .environment(AuthStore())
}
