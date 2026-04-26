import SwiftUI

struct SignUpView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var error: APIError?

    var canSubmit: Bool {
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty
            && email.contains("@")
            && password.count >= 8
    }

    var body: some View {
        Form {
            Section("Your name") {
                TextField("Display name", text: $displayName)
                    .textContentType(.name)
                    .autocorrectionDisabled()
            }
            Section("Account") {
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                SecureField("Password (8+ characters)", text: $password)
                    .textContentType(.newPassword)
            }
            Section {
                Button("Create account") { submit() }
                    .disabled(!canSubmit || isLoading)
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Create account")
        .navigationBarTitleDisplayMode(.inline)
        .loadingOverlay(isLoading)
        .errorAlert($error)
    }

    private func submit() {
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                try await authStore.signUp(
                    email: email.lowercased().trimmingCharacters(in: .whitespaces),
                    password: password,
                    displayName: displayName.trimmingCharacters(in: .whitespaces)
                )
            } catch let err as APIError {
                error = err
            } catch {
                self.error = .server(code: "INTERNAL", message: error.localizedDescription)
            }
        }
    }
}

#Preview { NavigationStack { SignUpView().environment(AuthStore()) } }
