import SwiftUI
import PhotosUI

struct GenerateFromImageView: View {
    let householdId: String
    let choresViewModel: ChoresViewModel
    let onComplete: () -> Void

    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var genViewModel = GenerationViewModel()
    @State private var showSuggestions = false

    var body: some View {
        VStack(spacing: 24) {
            if let image = selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)

                Button("Generate chores") {
                    Task {
                        await genViewModel.generateFromImage(image, householdId: householdId)
                        if !genViewModel.suggestedChores.isEmpty {
                            showSuggestions = true
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(genViewModel.isGenerating)

                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Label("Choose a different photo", systemImage: "photo")
                }
                .buttonStyle(.bordered)
            } else {
                Spacer()
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary)
                Text("Pick or take a photo of a room")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Label("Choose from library", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
        }
        .navigationTitle("From a photo")
        .navigationBarTitleDisplayMode(.inline)
        .loadingOverlay(genViewModel.isGenerating)
        .errorAlert($genViewModel.error)
        .onChange(of: selectedItem) { _, newItem in
            Task {
                guard let data = try? await newItem?.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                selectedImage = image
            }
        }
        .navigationDestination(isPresented: $showSuggestions) {
            SuggestedChoresView(
                chores: genViewModel.suggestedChores,
                householdId: householdId,
                genViewModel: genViewModel,
                choresViewModel: choresViewModel,
                onComplete: onComplete
            )
        }
    }
}
