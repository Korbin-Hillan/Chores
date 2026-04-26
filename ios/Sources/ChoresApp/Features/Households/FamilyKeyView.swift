import SwiftUI

struct FamilyKeyView: View {
    let household: APIHousehold
    let isAdmin: Bool

    @State private var keyInput = ""
    @State private var status: OpenAIKeyStatus?
    @State private var isLoading = false
    @State private var showSetKey = false
    @State private var error: APIError?

    var body: some View {
        List {
            Section {
                if let status {
                    LabeledContent("Status") {
                        Label(status.isSet ? "Key set" : "No key", systemImage: status.isSet ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(status.isSet ? .green : .secondary)
                    }
                    if let setAt = status.setAt, let date = ISO8601DateFormatter().date(from: setAt) {
                        LabeledContent("Last updated", value: date.formatted(date: .abbreviated, time: .omitted))
                    }
                } else {
                    ProgressView()
                }
            } footer: {
                if !isAdmin {
                    Text("Only the household admin can manage the family AI key.")
                }
            }

            if isAdmin {
                Section {
                    Button(status?.isSet == true ? "Replace key" : "Set family key") {
                        showSetKey = true
                    }
                    if status?.isSet == true {
                        Button("Remove key", role: .destructive) { removeKey() }
                    }
                }
            }
        }
        .navigationTitle("Family AI Key")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSetKey, onDismiss: { Task { await loadStatus() } }) {
            SetKeySheet(householdId: household.id)
        }
        .loadingOverlay(isLoading)
        .errorAlert($error)
        .task { await loadStatus() }
    }

    private func loadStatus() async {
        do {
            status = try await APIClient.shared.send(
                path: "/households/\(household.id)/openai-key/status"
            )
        } catch let err as APIError {
            error = err
        } catch {}
    }

    private func removeKey() {
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                try await APIClient.shared.send(
                    path: "/households/\(household.id)/openai-key",
                    method: "DELETE",
                    body: Optional<String>.none
                )
                await loadStatus()
            } catch let err as APIError {
                error = err
            } catch {}
        }
    }
}

private struct SetKeySheet: View {
    let householdId: String
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var isLoading = false
    @State private var error: APIError?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("sk-...", text: $key)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("OpenAI API key")
                } footer: {
                    Text("Your key is encrypted and stored securely. It's only used to generate chores for your household and is never shared.")
                }
            }
            .navigationTitle("Set family key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(key.count < 10 || isLoading)
                }
            }
            .loadingOverlay(isLoading)
            .errorAlert($error)
        }
    }

    private func save() {
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                try await APIClient.shared.send(
                    path: "/households/\(householdId)/openai-key",
                    method: "PUT",
                    body: SetOpenAIKeyBody(key: key)
                )
                dismiss()
            } catch let err as APIError {
                error = err
            } catch {
                self.error = .server(code: "INTERNAL", message: error.localizedDescription)
            }
        }
    }
}
