import SwiftUI

struct ChoreEditorView: View {
    let viewModel: ChoresViewModel
    let householdId: String
    let rooms: [APIRoom]
    let members: [APIHouseholdMember]
    let chore: APIChore?
    let preferredRoomId: String?

    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var description = ""
    @State private var selectedRoomId = ""
    @State private var recurrenceKind: Recurrence.RecurrenceKind = .none
    @State private var estimatedMinutes = ""
    @State private var points = 1
    @State private var assignmentMode: AssignmentMode = .anyone
    @State private var assignedToUserId = ""
    @State private var rotationMemberIds: [String] = []
    @State private var requiresPhotoEvidence = false
    @State private var requiresParentApproval = false
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
                    TextField("Notes (optional)", text: $description, axis: .vertical)
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
                Section("Assignment") {
                    Picker("Responsible", selection: $assignmentMode) {
                        ForEach(AssignmentMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch assignmentMode {
                    case .anyone:
                        Text("Anyone can do this chore.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case .onePerson:
                        Picker("Person", selection: $assignedToUserId) {
                            Text("Select").tag("")
                            ForEach(members) { member in
                                Text(member.displayName ?? member.userId).tag(member.userId)
                            }
                        }
                    case .rotate:
                        ForEach(members) { member in
                            Toggle(isOn: rotationBinding(for: member.userId)) {
                                HStack {
                                    Text(member.displayName ?? member.userId)
                                    if rotationMemberIds.first == member.userId {
                                        Text("Current")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                Section("Verification") {
                    Toggle("Require photo evidence", isOn: $requiresPhotoEvidence)
                    Toggle("Parent approval required", isOn: $requiresParentApproval)
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
                requiresPhotoEvidence = chore.requiresPhotoEvidence
                requiresParentApproval = chore.requiresParentApproval
                rotationMemberIds = chore.rotationMemberIds
                assignedToUserId = chore.assignedToUserId ?? ""
                assignmentMode = chore.rotationMemberIds.isEmpty
                    ? (chore.assignedToUserId == nil ? .anyone : .onePerson)
                    : .rotate
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
            let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
            let recurrence = buildRecurrence()
            let assignment = buildAssignment()

            if let chore {
                let body = UpdateChoreBody(
                    roomId: selectedRoomId,
                    title: trimmedTitle,
                    description: trimmedDescription.isEmpty ? nil : trimmedDescription,
                    recurrence: recurrence,
                    estimatedMinutes: mins,
                    points: points,
                    archived: nil,
                    assignedToUserId: assignment.assignedToUserId,
                    rotationMemberIds: assignment.rotationMemberIds,
                    requiresPhotoEvidence: requiresPhotoEvidence,
                    requiresParentApproval: requiresParentApproval
                )
                if await viewModel.updateChore(choreId: chore.id, body: body, householdId: householdId) != nil {
                    dismiss()
                }
            } else {
                let body = CreateChoreBody(
                    roomId: selectedRoomId,
                    title: trimmedTitle,
                    description: trimmedDescription.isEmpty ? nil : trimmedDescription,
                    recurrence: recurrence,
                    estimatedMinutes: mins,
                    points: points,
                    assignedToUserId: assignment.assignedToUserId,
                    rotationMemberIds: assignment.rotationMemberIds,
                    requiresPhotoEvidence: requiresPhotoEvidence,
                    requiresParentApproval: requiresParentApproval
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

    private func buildAssignment() -> (assignedToUserId: String?, rotationMemberIds: [String]) {
        switch assignmentMode {
        case .anyone:
            return (nil, [])
        case .onePerson:
            return (assignedToUserId.isEmpty ? nil : assignedToUserId, [])
        case .rotate:
            let rotation = rotationMemberIds.filter { memberId in
                members.contains { $0.userId == memberId }
            }
            return (rotation.first, rotation)
        }
    }

    private func rotationBinding(for userId: String) -> Binding<Bool> {
        Binding {
            rotationMemberIds.contains(userId)
        } set: { isSelected in
            if isSelected {
                if !rotationMemberIds.contains(userId) {
                    rotationMemberIds.append(userId)
                }
            } else {
                rotationMemberIds.removeAll { $0 == userId }
            }
        }
    }
}

private enum AssignmentMode: String, CaseIterable, Identifiable {
    case anyone
    case onePerson
    case rotate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .anyone: return "Anyone"
        case .onePerson: return "One"
        case .rotate: return "Rotate"
        }
    }
}

#Preview {
    ChoreEditorView(
        viewModel: ChoresViewModel(),
        householdId: "test",
        rooms: [],
        members: [],
        chore: nil,
        preferredRoomId: nil
    )
}
