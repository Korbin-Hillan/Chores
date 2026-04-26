import SwiftUI

struct HouseholdSettingsView: View {
    @Environment(AuthStore.self) private var authStore

    @State private var detail: APIHouseholdDetail?
    @State private var isLoading = false
    @State private var error: APIError?
    @State private var showInviteCode = false

    var householdId: String { authStore.currentHouseholdId ?? "" }

    private var isAdmin: Bool {
        detail?.members.first(where: { $0.userId == authStore.currentUser?.id })?.role == "admin"
    }

    var body: some View {
        List {
            if let detail {
                Section("Household") {
                    LabeledContent("Name", value: detail.household.name)
                    Button {
                        showInviteCode.toggle()
                    } label: {
                        LabeledContent("Invite code") {
                            Text(showInviteCode ? detail.household.inviteCode : "Tap to reveal")
                                .foregroundStyle(showInviteCode ? .primary : .secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                }

                Section("Members (\(detail.members.count))") {
                    ForEach(detail.members) { member in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(member.displayName ?? member.userId)
                                    .font(.body)
                                HStack(spacing: 4) {
                                    if member.userId == authStore.currentUser?.id {
                                        Text("(you)").foregroundStyle(.secondary)
                                    }
                                    if member.role == "admin" {
                                        Label("Admin", systemImage: "star.fill")
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                    }
                                }
                                .font(.caption)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Label("\(member.currentStreak)", systemImage: "flame.fill")
                                    .foregroundStyle(.orange)
                                    .font(.caption.bold())
                                Text("streak").font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }

                Section("AI Settings") {
                    NavigationLink {
                        FamilyKeyView(household: detail.household, isAdmin: isAdmin)
                    } label: {
                        LabeledContent("Family AI key") {
                            Text(detail.household.openAIKeyIsSet ? "Set" : "Not set")
                                .foregroundStyle(detail.household.openAIKeyIsSet ? .green : .secondary)
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Household")
        .navigationBarTitleDisplayMode(.inline)
        .loadingOverlay(isLoading && detail == nil)
        .errorAlert($error)
        .task(id: householdId) { await loadDetail() }
        .refreshable { await loadDetail() }
    }

    private func loadDetail() async {
        do {
            detail = try await APIClient.shared.send(
                path: "/households/\(householdId)"
            )
        } catch let err as APIError {
            error = err
        } catch {}
    }
}
