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

        case .locked:
            SessionUnlockView()

        case .authenticated:
            if authStore.currentHouseholdId == nil {
                HouseholdOnboardingView()
            } else {
                MainTabView()
            }
        }
    }
}

private struct SessionUnlockView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var isUnlocking = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: authStore.biometricUnlockName == "Face ID" ? "faceid" : "lock.circle")
                .font(.system(size: 72))
                .foregroundStyle(.tint)
            Text("Unlock Chores")
                .font(.largeTitle.bold())
            Text("Use \(authStore.biometricUnlockName) to open your saved session.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button("Unlock with \(authStore.biometricUnlockName)") {
                unlock()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isUnlocking)

            Button("Sign out", role: .destructive) {
                Task { await authStore.signOut() }
            }
            .disabled(isUnlocking)
            Spacer()
        }
        .padding(.horizontal, 24)
        .loadingOverlay(isUnlocking)
        .alert("Couldn’t unlock", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func unlock() {
        isUnlocking = true
        Task {
            defer { isUnlocking = false }
            do {
                try await authStore.unlockWithBiometrics()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    RootView()
        .environment(AuthStore())
}
