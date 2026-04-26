import SwiftUI

struct JoinHouseholdView: View {
    @Environment(AuthStore.self) private var authStore

    @State private var inviteCode = ""
    @State private var isLoading = false
    @State private var error: APIError?

    var body: some View {
        Form {
            Section {
                TextField("Invite code (e.g. ABCD1234)", text: $inviteCode)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .onChange(of: inviteCode) { _, new in
                        inviteCode = String(new.uppercased().prefix(8))
                    }
            } footer: {
                Text("Ask a household member for the 8-character invite code found in Settings.")
            }
            Section {
                Button("Join") { join() }
                    .disabled(inviteCode.count < 4 || isLoading)
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Join household")
        .navigationBarTitleDisplayMode(.inline)
        .loadingOverlay(isLoading)
        .errorAlert($error)
    }

    private func join() {
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                struct Response: Decodable { let household: APIHousehold }
                let response: Response = try await APIClient.shared.send(
                    path: "/households/join",
                    method: "POST",
                    body: JoinHouseholdBody(inviteCode: inviteCode)
                )
                authStore.selectHousehold(response.household.id)
            } catch let err as APIError {
                error = err
            } catch {
                self.error = .server(code: "INTERNAL", message: error.localizedDescription)
            }
        }
    }
}

#Preview { NavigationStack { JoinHouseholdView().environment(AuthStore()) } }
