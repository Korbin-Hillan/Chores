import SwiftUI

struct CreateHouseholdView: View {
    @Environment(AuthStore.self) private var authStore

    @State private var name = ""
    @State private var isLoading = false
    @State private var error: APIError?

    var body: some View {
        Form {
            Section("Household name") {
                TextField("e.g. The Smith House", text: $name)
                    .autocorrectionDisabled()
            }
            Section {
                Button("Create") { create() }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("New household")
        .navigationBarTitleDisplayMode(.inline)
        .loadingOverlay(isLoading)
        .errorAlert($error)
    }

    private func create() {
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                let body = CreateHouseholdBody(name: name.trimmingCharacters(in: .whitespaces))
                struct Response: Decodable {
                    let household: APIHousehold
                }
                let response: Response = try await APIClient.shared.send(
                    path: "/households",
                    method: "POST",
                    body: body
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

#Preview { NavigationStack { CreateHouseholdView().environment(AuthStore()) } }
