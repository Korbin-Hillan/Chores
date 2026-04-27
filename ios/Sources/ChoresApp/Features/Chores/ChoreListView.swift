import SwiftUI
import SwiftData

struct ChoreListView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = ChoresViewModel()
    @State private var showAddChore = false
    @State private var showAddRoom = false
    @State private var showManageRooms = false
    @State private var showGenerate = false
    @State private var showArchived = false
    @State private var selectedChore: APIChore?
    @State private var completionChore: APIChore?
    @State private var preferredRoomIdForNewChore: String?

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

    private var canReviewCompletions: Bool {
        guard let currentUserId = authStore.currentUser?.id else { return false }
        let role = viewModel.householdMembers.first(where: { $0.userId == currentUserId })?.role
        return role == "admin" || role == "parent"
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
                    Button("Generate", systemImage: "sparkles") { showGenerate = true }
                    Menu("Add", systemImage: "plus") {
                        Button("Add chore", systemImage: "checkmark.circle") {
                            selectedChore = nil
                            preferredRoomIdForNewChore = nil
                            showAddChore = true
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
            .sheet(isPresented: $showAddChore) {
                ChoreEditorView(
                    viewModel: viewModel,
                    householdId: householdId,
                    rooms: choreEditorRooms,
                    members: viewModel.householdMembers,
                    chore: nil,
                    preferredRoomId: preferredRoomIdForNewChore
                )
            }
            .sheet(item: $selectedChore) { chore in
                ChoreEditorView(
                    viewModel: viewModel,
                    householdId: householdId,
                    rooms: choreEditorRooms,
                    members: viewModel.householdMembers,
                    chore: chore,
                    preferredRoomId: nil
                )
            }
            .sheet(isPresented: $showGenerate) {
                GenerateSheet(householdId: householdId, viewModel: viewModel)
            }
            .sheet(item: $completionChore) { chore in
                CompleteChoreSheet(
                    chore: chore,
                    householdId: householdId,
                    viewModel: viewModel
                )
            }
            .sheet(isPresented: $showManageRooms) {
                NavigationStack {
                    ManageRoomsView(viewModel: viewModel, householdId: householdId)
                }
            }
            .errorAlert($viewModel.error)
        }
        .task(id: householdId) { await viewModel.load(householdId: householdId, context: modelContext) }
        .task(id: canReviewCompletions) {
            if canReviewCompletions {
                await viewModel.loadPendingReviews(householdId: householdId)
            }
        }
    }

    private var choreList: some View {
        List {
            pendingReviewSection
            rotatingChoresSection
            ForEach(Array(visibleRooms.enumerated()), id: \.element.id) { _, room in
                let chores = viewModel.chores(for: room.id)
                Section {
                    if chores.isEmpty {
                        if room.archived {
                            Text("No chores in this archived room.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Button {
                                selectedChore = nil
                                preferredRoomIdForNewChore = room.id
                                showAddChore = true
                            } label: {
                                Label("Add a chore to \(room.name)", systemImage: "plus.circle")
                            }
                        }
                    } else {
                        ForEach(chores) { chore in
                            let schedule = chore.scheduleSnapshot()
                            NavigationLink {
                                ChoreDetailView(chore: chore, viewModel: viewModel, householdId: householdId)
                            } label: {
                                ChoreRow(
                                    chore: chore,
                                    schedule: schedule,
                                    assigneeName: displayName(for: chore.assignedToUserId)
                                )
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button("Edit", systemImage: "pencil") {
                                    selectedChore = chore
                                }
                                .tint(.blue)
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    Task { await viewModel.deleteChore(chore.id, roomId: chore.roomId, householdId: householdId) }
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button("Complete", systemImage: "checkmark") {
                                    completionChore = chore
                                }
                                .tint(.green)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Label(room.name, systemImage: room.icon ?? "rectangle.on.rectangle")
                        Spacer()
                        if room.archived {
                            Text("Archived")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Button {
                                selectedChore = nil
                                preferredRoomIdForNewChore = room.id
                                showAddChore = true
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Add chore to \(room.name)")
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private var pendingReviewSection: some View {
        if canReviewCompletions && !viewModel.pendingReviewItems.isEmpty {
            Section("Pending review") {
                ForEach(viewModel.pendingReviewItems) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(item.completedBy.displayName) finished \(item.chore?.title ?? "a chore")")
                            .font(.subheadline.weight(.semibold))
                        if item.hasPhoto {
                            CompletionPhotoView(householdId: householdId, completionId: item.id)
                                .frame(height: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        HStack {
                            Button("Approve", systemImage: "checkmark.circle.fill") {
                                Task { await viewModel.approveCompletion(item.id, householdId: householdId) }
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Reject", systemImage: "xmark.circle") {
                                Task { await viewModel.rejectCompletion(item.id, householdId: householdId) }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    @ViewBuilder
    private var rotatingChoresSection: some View {
        let rotatingChores = viewModel.choresByRoom.values
            .flatMap { $0 }
            .filter { !$0.rotationMemberIds.isEmpty && !$0.archived }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        if !rotatingChores.isEmpty {
            Section("Whose week is it?") {
                ForEach(rotatingChores) { chore in
                    HStack {
                        Label(chore.title, systemImage: "arrow.triangle.2.circlepath")
                        Spacer()
                        Text(displayName(for: chore.assignedToUserId) ?? "Anyone")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func displayName(for userId: String?) -> String? {
        guard let userId else { return nil }
        return viewModel.householdMembers.first(where: { $0.userId == userId })?.displayName
    }
}

struct ChoreRow: View {
    let chore: APIChore
    let schedule: ChoreScheduleSnapshot
    let assigneeName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(chore.title)
                    .font(.body)
                Spacer()
                if let assigneeName {
                    AssignmentBadge(name: assigneeName, isRotation: !chore.rotationMemberIds.isEmpty)
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
                if chore.requiresPhotoEvidence {
                    Label("Photo", systemImage: "camera")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if chore.requiresParentApproval {
                    Label("Review", systemImage: "checkmark.seal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

private struct AssignmentBadge: View {
    let name: String
    let isRotation: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(isRotation ? "🔄" : "👤")
            Text(name)
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.thinMaterial, in: Capsule())
    }
}

#Preview {
    ChoreListView()
        .environment(AuthStore())
}
