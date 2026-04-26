import SwiftUI

struct ChoreEditorView: View {
    let viewModel: ChoresViewModel
    let householdId: String
    let rooms: [APIRoom]
    let chore: APIChore?
    let preferredRoomId: String?

    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var description = ""
    @State private var selectedRoomId = ""
    @State private var recurrenceKind: Recurrence.RecurrenceKind = .none
    @State private var estimatedMinutes = ""
    @State private var points = 1
    @State private var isLoading = false
    @State private var hasLoadedInitialValues = false

    var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && !selectedRoomId.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $title)
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section("Room") {
                    Picker("Room", selection: $selectedRoomId) {
                        Text("Select a room").tag("")
                        ForEach(rooms) { room in
                            Text(room.name).tag(room.id)
                        }
                    }
                }
                Section("Schedule") {
                    Picker("Repeats", selection: $recurrenceKind) {
                        Text("Never").tag(Recurrence.RecurrenceKind.none)
                        Text("Daily").tag(Recurrence.RecurrenceKind.daily)
                        Text("Weekly").tag(Recurrence.RecurrenceKind.weekly)
                        Text("Monthly").tag(Recurrence.RecurrenceKind.monthly)
                    }
                    TextField("Estimated minutes (optional)", text: $estimatedMinutes)
                        .keyboardType(.numberPad)
                    Stepper("Points: \(points)", value: $points, in: 1...10)
                }
            }
            .navigationTitle(chore == nil ? "New chore" : "Edit chore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!canSave || isLoading)
                }
            }
            .loadingOverlay(isLoading)
        }
        .onAppear {
            guard !hasLoadedInitialValues else { return }
            hasLoadedInitialValues = true

            if let chore {
                title = chore.title
                description = chore.description ?? ""
                selectedRoomId = chore.roomId
                recurrenceKind = chore.recurrence.kind
                estimatedMinutes = chore.estimatedMinutes.map(String.init) ?? ""
                points = chore.points
            } else if selectedRoomId.isEmpty {
                selectedRoomId = preferredRoomId ?? rooms.first?.id ?? ""
            }
        }
    }

    private func save() {
        isLoading = true
        Task {
            defer { isLoading = false }
            let mins = Int(estimatedMinutes)
            let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
            let recurrence = buildRecurrence()

            if let chore {
                let body = UpdateChoreBody(
                    roomId: selectedRoomId,
                    title: trimmedTitle,
                    description: description.isEmpty ? nil : description,
                    recurrence: recurrence,
                    estimatedMinutes: mins,
                    points: points,
                    archived: nil
                )
                if await viewModel.updateChore(choreId: chore.id, body: body, householdId: householdId) != nil {
                    dismiss()
                }
            } else {
                let body = CreateChoreBody(
                    roomId: selectedRoomId,
                    title: trimmedTitle,
                    description: description.isEmpty ? nil : description,
                    recurrence: recurrence,
                    estimatedMinutes: mins,
                    points: points
                )
                if await viewModel.createChore(body, householdId: householdId) != nil {
                    dismiss()
                }
            }
        }
    }

    private func buildRecurrence() -> Recurrence {
        if let chore, chore.recurrence.kind == recurrenceKind {
            return chore.recurrence
        }
        return Recurrence(kind: recurrenceKind, weekdays: nil, dayOfMonth: nil)
    }
}

#Preview {
    ChoreEditorView(
        viewModel: ChoresViewModel(),
        householdId: "test",
        rooms: [],
        chore: nil,
        preferredRoomId: nil
    )
}
