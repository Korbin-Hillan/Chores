import SwiftUI
import PhotosUI
import UIKit

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

private enum ProfileDestination: Hashable {
    case reminders
    case switchHousehold
    case householdSettings
}

struct ProfileView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var showSignOutConfirm = false
    @State private var biometricErrorMessage: String?
    @State private var selectedAvatarPhoto: PhotosPickerItem?
    @State private var showCamera = false
    @State private var isSavingAvatar = false
    @State private var avatarErrorMessage: String?

    var user: APIUser? { authStore.currentUser }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        UserAvatarView(
                            userId: user?.id ?? "",
                            displayName: user?.displayName ?? "You",
                            hasAvatar: user?.hasAvatar ?? false,
                            size: 64
                        )
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

                Section("Avatar") {
                    PhotosPicker(selection: $selectedAvatarPhoto, matching: .images, photoLibrary: .shared()) {
                        Label("Choose from library", systemImage: "photo")
                    }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button {
                            showCamera = true
                        } label: {
                            Label("Take photo", systemImage: "camera")
                        }
                    }
                    Button("Use generated avatar", systemImage: "person.crop.circle.badge.xmark") {
                        Task { await deleteAvatar() }
                    }
                    .disabled(user?.hasAvatar != true || isSavingAvatar)
                }

                Section("Notifications") {
                    NavigationLink("Reminder settings", value: ProfileDestination.reminders)
                }

                Section("Security") {
                    if authStore.supportsBiometricUnlock {
                        Toggle(
                            "Require \(authStore.biometricUnlockName)",
                            isOn: Binding(
                                get: { authStore.biometricUnlockEnabled },
                                set: { enabled in
                                    Task {
                                        do {
                                            try await authStore.setBiometricUnlockEnabled(enabled)
                                        } catch {
                                            biometricErrorMessage = error.localizedDescription
                                        }
                                    }
                                }
                            )
                        )
                    } else {
                        LabeledContent("Biometric unlock", value: "Not available")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Household") {
                    NavigationLink("Switch household", value: ProfileDestination.switchHousehold)
                    NavigationLink("Household settings", value: ProfileDestination.householdSettings)
                }

                Section {
                    Button(role: .destructive) {
                        showSignOutConfirm = true
                    } label: {
                        Text("Sign out")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .navigationTitle("Profile")
            .navigationDestination(for: ProfileDestination.self) { destination in
                switch destination {
                case .reminders:
                    NotificationSettingsView()
                case .switchHousehold:
                    HouseholdPickerView()
                case .householdSettings:
                    HouseholdSettingsView()
                }
            }
            .loadingOverlay(isSavingAvatar)
            .onChange(of: selectedAvatarPhoto) { _, newValue in
                Task { await uploadAvatar(from: newValue) }
            }
            .sheet(isPresented: $showCamera) {
                ProfileCameraCaptureView { image in
                    Task { await uploadAvatar(image: image) }
                }
            }
            .alert("Sign out", isPresented: $showSignOutConfirm) {
                Button("Sign out", role: .destructive) {
                    Task { await authStore.signOut() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll need to sign in again to continue.")
            }
            .alert("Security", isPresented: Binding(
                get: { biometricErrorMessage != nil },
                set: { if !$0 { biometricErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { biometricErrorMessage = nil }
            } message: {
                Text(biometricErrorMessage ?? "")
            }
            .alert("Avatar", isPresented: Binding(
                get: { avatarErrorMessage != nil },
                set: { if !$0 { avatarErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { avatarErrorMessage = nil }
            } message: {
                Text(avatarErrorMessage ?? "")
            }
        }
    }

    private func uploadAvatar(from item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
        guard let image = UIImage(data: data) else { return }
        await uploadAvatar(image: image)
    }

    private func uploadAvatar(image: UIImage) async {
        guard let data = compressedAvatarJPEG(from: image) else {
            avatarErrorMessage = "Could not read that image."
            return
        }
        isSavingAvatar = true
        defer { isSavingAvatar = false }
        do {
            let _: APIUser = try await APIClient.shared.send(
                path: "/auth/me/avatar",
                method: "PUT",
                body: UpdateAvatarBody(imageBase64: data.base64EncodedString(), mimeType: "image/jpeg")
            )
            await authStore.refreshCurrentUser()
        } catch {
            avatarErrorMessage = error.localizedDescription
        }
    }

    private func deleteAvatar() async {
        isSavingAvatar = true
        defer { isSavingAvatar = false }
        do {
            try await APIClient.shared.delete("/auth/me/avatar")
            await authStore.refreshCurrentUser()
        } catch {
            avatarErrorMessage = error.localizedDescription
        }
    }

    private func compressedAvatarJPEG(from image: UIImage) -> Data? {
        let targetBytes = 280_000
        let maxSides: [CGFloat] = [512, 420, 320, 240]
        let qualities: [CGFloat] = [0.78, 0.68, 0.58, 0.48, 0.38]
        var smallestData: Data?
        for maxSide in maxSides {
            let resized = resizedImage(image, maxSide: maxSide)
            for quality in qualities {
                guard let data = resized.jpegData(compressionQuality: quality) else { continue }
                if data.count <= targetBytes { return data }
                if smallestData == nil || data.count < (smallestData?.count ?? Int.max) {
                    smallestData = data
                }
            }
        }
        return smallestData
    }

    private func resizedImage(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

private struct ProfileCameraCaptureView: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        _ = uiViewController
        _ = context
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, dismiss: dismiss)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onImage: (UIImage) -> Void
        let dismiss: DismissAction

        init(onImage: @escaping (UIImage) -> Void, dismiss: DismissAction) {
            self.onImage = onImage
            self.dismiss = dismiss
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onImage(image)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
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
