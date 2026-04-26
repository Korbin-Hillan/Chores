import SwiftUI

struct GenerateFromTextView: View {
    let householdId: String
    let choresViewModel: ChoresViewModel
    let onComplete: () -> Void

    @State private var prompt = ""
    @State private var genViewModel = GenerationViewModel()
    @State private var showSuggestions = false

    var body: some View {
        Form {
            Section {
                TextField(
                    "e.g. 3 bedroom apartment with 2 bathrooms, a dog, and a small balcony",
                    text: $prompt,
                    axis: .vertical
                )
                .lineLimit(4...8)
            } header: {
                Text("Describe your home")
            } footer: {
                Text("The more detail you give, the better the suggestions.")
            }

            Section {
                Button("Generate chores") {
                    Task {
                        await genViewModel.generateFromText(prompt: prompt, householdId: householdId)
                        if genViewModel.suggestedChores.isEmpty == false {
                            showSuggestions = true
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .disabled(prompt.trimmingCharacters(in: .whitespaces).isEmpty || genViewModel.isGenerating)
            }
        }
        .navigationTitle("Describe your home")
        .navigationBarTitleDisplayMode(.inline)
        .loadingOverlay(genViewModel.isGenerating)
        .errorAlert($genViewModel.error)
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
