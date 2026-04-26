import SwiftUI

@Observable
@MainActor
final class HouseholdPickerViewModel {
    private(set) var households: [APIHousehold] = []
    private(set) var isLoading = false
    var error: APIError?

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            households = try await APIClient.shared.send(path: "/households/me")
        } catch let err as APIError {
            error = err
        } catch {
            self.error = .server(code: "INTERNAL", message: error.localizedDescription)
        }
    }
}

struct ProfileView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var showSignOutConfirm = false

    var user: APIUser? { authStore.currentUser }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(user?.displayName ?? "—")
                                .font(.title3.bold())
                            Text(user?.email ?? "")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section("Notifications") {
                    NavigationLink("Reminder settings") {
                        NotificationSettingsView()
                    }
                }

                Section("Household") {
                    NavigationLink("Switch household") {
                        HouseholdPickerView()
                    }
                    NavigationLink("Household settings") {
                        HouseholdSettingsView()
                    }
                }

                Section {
                    Button("Sign out", role: .destructive) {
                        showSignOutConfirm = true
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Profile")
            .confirmationDialog("Sign out?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) {
                    Task { await authStore.signOut() }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

private struct HouseholdPickerView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = HouseholdPickerViewModel()

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.households.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.households.isEmpty {
                EmptyStateView(
                    icon: "house",
                    title: "No households found",
                    message: "Create or join a household to switch between them."
                )
            } else {
                List(viewModel.households) { household in
                    Button {
                        authStore.selectHousehold(household.id)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(household.name)
                                    .foregroundStyle(.primary)
                                if household.id == authStore.currentHouseholdId {
                                    Text("Current household")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if household.id == authStore.currentHouseholdId {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Switch household")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await viewModel.load() }
        .errorAlert($viewModel.error)
        .task { await viewModel.load() }
    }
}

#Preview {
    ProfileView().environment(AuthStore())
}
