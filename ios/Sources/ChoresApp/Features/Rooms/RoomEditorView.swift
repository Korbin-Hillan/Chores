import SwiftUI

private let roomIcons = [
    "fork.knife", "sofa.fill", "bed.double.fill", "shower.fill",
    "tree.fill", "car.fill", "washer.fill", "tv.fill",
    "dumbbell.fill", "books.vertical.fill"
]

struct RoomEditorView: View {
    @Bindable var viewModel: ChoresViewModel
    let householdId: String
    let room: APIRoom?

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selectedIcon: String? = nil
    @State private var isLoading = false
    @State private var hasLoadedInitialValues = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Room name") {
                    TextField("e.g. Kitchen", text: $name)
                }
                Section("Icon (optional)") {
                    LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 5), spacing: 16) {
                        ForEach(roomIcons, id: \.self) { icon in
                            Button {
                                selectedIcon = selectedIcon == icon ? nil : icon
                            } label: {
                                Image(systemName: icon)
                                    .font(.title2)
                                    .frame(width: 44, height: 44)
                                    .background(selectedIcon == icon ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay {
                                        if selectedIcon == icon {
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.accentColor, lineWidth: 2)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle(room == nil ? "New room" : "Edit room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                }
            }
            .loadingOverlay(isLoading)
            .errorAlert($viewModel.error)
        }
        .onAppear {
            guard !hasLoadedInitialValues else { return }
            hasLoadedInitialValues = true

            if let room {
                name = room.name
                selectedIcon = room.icon
            }
        }
    }

    private func save() {
        isLoading = true
        Task {
            defer { isLoading = false }
            let trimmedName = name.trimmingCharacters(in: .whitespaces)
            if let room {
                if await viewModel.updateRoom(
                    roomId: room.id,
                    name: trimmedName,
                    icon: selectedIcon,
                    archived: room.archived,
                    householdId: householdId
                ) != nil {
                    dismiss()
                }
            } else if await viewModel.createRoom(
                name: trimmedName,
                icon: selectedIcon,
                householdId: householdId
            ) != nil {
                dismiss()
            }
        }
    }
}

struct ManageRoomsView: View {
    @Bindable var viewModel: ChoresViewModel
    let householdId: String

    @State private var showArchived = false
    @State private var showEditor = false
    @State private var selectedRoom: APIRoom?
    @State private var roomPendingDelete: APIRoom?

    private var rooms: [APIRoom] {
        viewModel.allRooms(includeArchived: showArchived)
    }

    var body: some View {
        List {

            Section {
                ForEach(rooms) { room in
                    HStack {
                        RoomHeaderLabel(room: room)
                        Spacer()
                        if room.archived {
                            Text("Archived")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button("Edit", systemImage: "pencil") {
                            selectedRoom = room
                            showEditor = true
                        }
                        .tint(.blue)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            roomPendingDelete = room
                        }
                    }
                }
            } header: {
                Text("Rooms")
            } footer: {
                if rooms.isEmpty {
                    Text(showArchived ? "No rooms found." : "No active rooms.")
                } else {
                    Text("Deleting a room also deletes every chore in that room.")
                }
            }
        }
        .navigationTitle("Manage rooms")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add room", systemImage: "plus") {
                    selectedRoom = nil
                    showEditor = true
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            RoomEditorView(viewModel: viewModel, householdId: householdId, room: selectedRoom)
        }
        .confirmationDialog(
            "Delete room?",
            isPresented: Binding(
                get: { roomPendingDelete != nil },
                set: { if !$0 { roomPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let room = roomPendingDelete {
                Button("Delete \"\(room.name)\"", role: .destructive) {
                    Task {
                        await viewModel.deleteRoom(room.id, householdId: householdId)
                        roomPendingDelete = nil
                    }
                }
            }
            Button("Cancel", role: .cancel) { roomPendingDelete = nil }
        } message: {
            Text("This permanently removes the room and every chore in it.")
        }
        .errorAlert($viewModel.error)
    }
}
