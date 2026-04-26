import SwiftUI

struct LoginView: View {
    @Environment(AuthStore.self) private var authStore

    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var error: APIError?

    var canSubmit: Bool { email.contains("@") && !password.isEmpty }

    var body: some View {
        Form {
            Section {
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                SecureField("Password", text: $password)
                    .textContentType(.password)
            }
            Section {
                Button("Sign in") { submit() }
                    .disabled(!canSubmit || isLoading)
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Sign in")
        .navigationBarTitleDisplayMode(.inline)
        .loadingOverlay(isLoading)
        .errorAlert($error)
    }

    private func submit() {
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                try await authStore.logIn(
                    email: email.lowercased().trimmingCharacters(in: .whitespaces),
                    password: password
                )
            } catch let err as APIError {
                error = err
            } catch {
                self.error = .server(code: "INTERNAL", message: error.localizedDescription)
            }
        }
    }
}

#Preview { NavigationStack { LoginView().environment(AuthStore()) } }
