import SwiftUI

struct HouseholdOnboardingView: View {
    @State private var showCreate = false
    @State private var showJoin = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "house.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                Text("Set up your household")
                    .font(.title.bold())
                Text("Create a new household or join one with an invite code.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Spacer()
                VStack(spacing: 12) {
                    Button("Create a household") { showCreate = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                    Button("Join with invite code") { showJoin = true }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
            .navigationDestination(isPresented: $showCreate) { CreateHouseholdView() }
            .navigationDestination(isPresented: $showJoin) { JoinHouseholdView() }
        }
    }
}

#Preview { HouseholdOnboardingView() }
