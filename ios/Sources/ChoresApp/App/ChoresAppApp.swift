import SwiftUI
import SwiftData

@main
struct ChoresAppApp: App {
    @State private var authStore = AuthStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authStore)
        }
        .modelContainer(for: [LocalRoom.self, LocalChore.self])
    }
}
