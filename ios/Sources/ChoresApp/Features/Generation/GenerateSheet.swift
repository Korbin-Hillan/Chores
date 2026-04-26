import SwiftUI

struct GenerateSheet: View {
    let householdId: String
    let viewModel: ChoresViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var showText = false
    @State private var showImage = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "sparkles")
                    .font(.system(size: 56))
                    .foregroundStyle(.purple)
                Text("AI Chore Generator")
                    .font(.title.bold())
                Text("Describe your home or take a photo of a room — we'll suggest chores tailored to your space.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                Spacer()
                VStack(spacing: 12) {
                    Button {
                        showText = true
                    } label: {
                        Label("From a description", systemImage: "text.bubble")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        showImage = true
                    } label: {
                        Label("From a photo", systemImage: "camera")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
            .navigationTitle("Generate chores")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .navigationDestination(isPresented: $showText) {
                GenerateFromTextView(householdId: householdId, choresViewModel: viewModel, onComplete: { dismiss() })
            }
            .navigationDestination(isPresented: $showImage) {
                GenerateFromImageView(householdId: householdId, choresViewModel: viewModel, onComplete: { dismiss() })
            }
        }
    }
}
