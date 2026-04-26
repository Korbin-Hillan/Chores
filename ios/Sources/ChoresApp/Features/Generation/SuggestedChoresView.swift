import SwiftUI

struct SuggestedChoresView: View {
    let chores: [ChoreDraft]
    let householdId: String
    @Bindable var genViewModel: GenerationViewModel
    @Bindable var choresViewModel: ChoresViewModel
    let onComplete: () -> Void

    @State private var selectedIndices: Set<Int> = []
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        List {
            Section {
                ForEach(Array(chores.enumerated()), id: \.element.id) { index, chore in
                    ChoreSelectionRow(
                        chore: chore,
                        isSelected: selectedIndices.contains(index)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selectedIndices.contains(index) {
                            selectedIndices.remove(index)
                        } else {
                            selectedIndices.insert(index)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("\(chores.count) suggestions")
                    Spacer()
                    Button(selectedIndices.count == chores.count ? "Deselect all" : "Select all") {
                        if selectedIndices.count == chores.count {
                            selectedIndices.removeAll()
                        } else {
                            selectedIndices = Set(0..<chores.count)
                        }
                    }
                    .font(.caption)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Review suggestions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save \(selectedIndices.count)") {
                    save()
                }
                .disabled(selectedIndices.isEmpty || genViewModel.isSaving)
                .bold()
            }
        }
        .loadingOverlay(genViewModel.isSaving)
        .errorAlert($genViewModel.error)
        .onAppear { selectedIndices = Set(0..<chores.count) }
    }

    private func save() {
        Task {
            if let saved = await genViewModel.acceptChores(
                selectedIndices: selectedIndices,
                householdId: householdId
            ) {
                choresViewModel.mergeChores(saved)
                onComplete()
            }
        }
    }
}

private struct ChoreSelectionRow: View {
    let chore: ChoreDraft
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(chore.title).font(.body)
                HStack(spacing: 8) {
                    Label(chore.suggestedRoomName, systemImage: "rectangle.on.rectangle")
                    if chore.recurrence.kind != .none {
                        Label(chore.recurrence.kind.rawValue.capitalized, systemImage: "repeat")
                    }
                    if let mins = chore.estimatedMinutes {
                        Label("\(mins) min", systemImage: "clock")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
