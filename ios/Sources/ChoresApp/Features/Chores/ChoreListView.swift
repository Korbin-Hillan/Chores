import SwiftUI
import SwiftData

struct ChoreListView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = ChoresViewModel()
    @State private var showChoreEditor = false
    @State private var showAddRoom = false
    @State private var showManageRooms = false
    @State private var showGenerate = false
    @State private var showArchived = false
    @State private var selectedChore: APIChore?

    var householdId: String { authStore.currentHouseholdId ?? "" }

    private var visibleRooms: [APIRoom] {
        viewModel.allRooms(includeArchived: showArchived)
    }

    private var choreEditorRooms: [APIRoom] {
        let selectedRoomId = selectedChore?.roomId
        return viewModel.allRooms(includeArchived: true).filter { room in
            !room.archived || room.id == selectedRoomId
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.allRooms(includeArchived: true).isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if visibleRooms.isEmpty {
                    EmptyStateView(
                        icon: "house",
                        title: showArchived ? "No rooms found" : "No rooms yet",
                        message: showArchived
                            ? "There are no active or archived rooms in this household."
                            : "Add a room to start organizing chores.",
                        action: { showAddRoom = true },
                        actionTitle: "Add a room"
                    )
                } else {
                    choreList
                }
            }
            .navigationTitle("Chores")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu("View", systemImage: "line.3.horizontal.decrease.circle") {
                        Toggle("Show archived", isOn: $showArchived)
                    }
                    Button("Generate", systemImage: "sparkles") { showGenerate = true }
                    Menu("Add", systemImage: "plus") {
                        Button("Add chore", systemImage: "checkmark.circle") {
                            selectedChore = nil
                            showChoreEditor = true
                        }
                        Button("Add room", systemImage: "plus.rectangle") { showAddRoom = true }
                        Button("Manage rooms", systemImage: "slider.horizontal.3") { showManageRooms = true }
                    }
                }
            }
            .refreshable { await viewModel.load(householdId: householdId, context: modelContext) }
            .sheet(isPresented: $showAddRoom) {
                RoomEditorView(viewModel: viewModel, householdId: householdId, room: nil)
            }
            .sheet(isPresented: $showChoreEditor) {
                ChoreEditorView(
                    viewModel: viewModel,
                    householdId: householdId,
                    rooms: choreEditorRooms,
                    chore: selectedChore
                )
            }
            .sheet(isPresented: $showGenerate) {
                GenerateSheet(householdId: householdId, viewModel: viewModel)
            }
            .sheet(isPresented: $showManageRooms) {
                NavigationStack {
                    ManageRoomsView(viewModel: viewModel, householdId: householdId)
                }
            }
            .errorAlert($viewModel.error)
        }
        .task(id: householdId) { await viewModel.load(householdId: householdId, context: modelContext) }
    }

    private var choreList: some View {
        List {
            Section {
                Toggle("Show archived chores and rooms", isOn: $showArchived)
            }

            ForEach(visibleRooms) { room in
                let chores = viewModel.chores(for: room.id, includeArchived: showArchived)
                if !chores.isEmpty || room.archived {
                    Section {
                        ForEach(chores) { chore in
                            let schedule = chore.scheduleSnapshot()
                            NavigationLink {
                                ChoreDetailView(chore: chore, viewModel: viewModel, householdId: householdId)
                            } label: {
                                ChoreRow(chore: chore, schedule: schedule)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button("Edit", systemImage: "pencil") {
                                    selectedChore = chore
                                    showChoreEditor = true
                                }
                                .tint(.blue)
                                Button("Complete", systemImage: "checkmark") {
                                    Task { await viewModel.completeChore(chore.id, householdId: householdId) }
                                }
                                .tint(.green)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(chore.archived ? "Restore" : "Archive", systemImage: chore.archived ? "arrow.uturn.backward" : "archivebox") {
                                    Task { await viewModel.setChoreArchived(chore, archived: !chore.archived, householdId: householdId) }
                                }
                                .tint(chore.archived ? .green : .orange)
                            }
                        }
                    } header: {
                        HStack {
                            Label(room.name, systemImage: room.icon ?? "rectangle.on.rectangle")
                            if room.archived {
                                Text("Archived")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

struct ChoreRow: View {
    let chore: APIChore
    let schedule: ChoreScheduleSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(chore.title)
                    .font(.body)
                if chore.archived {
                    Text("Archived")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                if chore.recurrence.kind != .none {
                    Label(chore.recurrence.kind.rawValue.capitalized, systemImage: "repeat")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let mins = chore.estimatedMinutes {
                    Label("\(mins) min", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if chore.source != "manual" {
                    Label("AI", systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.purple)
                }
            }
            if let dueText = dueText {
                Text(dueText)
                    .font(.caption)
                    .foregroundStyle(dueColor)
            }
        }
        .padding(.vertical, 2)
    }

    private var dueText: String? {
        switch schedule.state {
        case .unscheduled:
            return nil
        case .dueToday:
            return "Due today"
        case .overdue(let date):
            return "Overdue since \(date.formatted(date: .abbreviated, time: .omitted))"
        case .upcoming(let date):
            return "Next due \(date.formatted(date: .abbreviated, time: .omitted))"
        }
    }

    private var dueColor: Color {
        switch schedule.state {
        case .dueToday:
            return .orange
        case .overdue:
            return .red
        case .upcoming:
            return .secondary
        case .unscheduled:
            return .secondary
        }
    }
}

#Preview {
    ChoreListView()
        .environment(AuthStore())
}
