import SwiftUI
import SwiftData
import UIKit

struct TodayView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = ChoresViewModel()
    @State private var completionChore: APIChore?
    @State private var milestoneStreak: Int?
    @State private var isCompletingChoreId: String?

    private var householdId: String { authStore.currentHouseholdId ?? "" }

    private var currentMember: APIHouseholdMember? {
        guard let currentUserId = authStore.currentUser?.id else { return nil }
        return viewModel.householdMembers.first { $0.userId == currentUserId }
    }

    private var activeRoomIds: Set<String> {
        Set(viewModel.allRooms().map(\.id))
    }

    private var activeChores: [APIChore] {
        viewModel.choresByRoom.values
            .flatMap { $0 }
            .filter { !$0.archived && activeRoomIds.contains($0.roomId) }
    }

    private var overdueChores: [APIChore] {
        activeChores
            .filter {
                if case .overdue = $0.scheduleSnapshot().state { return true }
                return false
            }
            .sorted(by: sortByDueThenTitle)
    }

    private var dueTodayChores: [APIChore] {
        activeChores
            .filter {
                if case .dueToday = $0.scheduleSnapshot().state { return true }
                return false
            }
            .sorted(by: sortByDueThenTitle)
    }

    private var quickWinChores: [APIChore] {
        activeChores
            .filter { chore in
                guard chore.recurrence.kind != .none else { return false }
                if case .upcoming = chore.scheduleSnapshot().state { return true }
                return false
            }
            .sorted(by: sortByDueThenTitle)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Group {
                    if viewModel.isLoading && activeChores.isEmpty {
                        TodaySkeletonView()
                    } else if activeChores.isEmpty {
                        EmptyStateView(
                            icon: "checklist",
                            title: "No chores yet",
                            message: "Add chores by room, then Today becomes the daily action list.",
                            action: nil,
                            actionTitle: nil
                        )
                    } else {
                        todayList
                    }
                }

                if let milestoneStreak {
                    MilestoneCelebrationView(streak: milestoneStreak)
                        .transition(.opacity.combined(with: .scale))
                        .zIndex(2)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    self.milestoneStreak = nil
                                }
                            }
                        }
                }
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if let currentMember {
                        HStack(spacing: 6) {
                            UserAvatarView(
                                userId: currentMember.userId,
                                displayName: currentMember.displayName ?? authStore.currentUser?.displayName ?? "You",
                                hasAvatar: currentMember.hasAvatar ?? authStore.currentUser?.hasAvatar ?? false,
                                size: 26
                            )
                            Image(systemName: "flame.fill")
                                .foregroundStyle(.orange)
                            Text("\(currentMember.currentStreak)")
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                }
            }
            .refreshable { await viewModel.load(householdId: householdId, context: modelContext) }
            .sheet(item: $completionChore) { chore in
                CompleteChoreSheet(
                    chore: chore,
                    householdId: householdId,
                    viewModel: viewModel
                )
            }
            .errorAlert($viewModel.error)
        }
        .task(id: householdId) { await viewModel.load(householdId: householdId, context: modelContext) }
    }

    private var todayList: some View {
        List {
            ChoreBucketSection(
                title: "Overdue",
                tint: .red,
                chores: overdueChores,
                viewModel: viewModel,
                householdId: householdId,
                householdMembers: viewModel.householdMembers,
                isCompletingChoreId: isCompletingChoreId,
                onComplete: completeFromSwipe,
                onOpenSheet: { completionChore = $0 }
            )

            ChoreBucketSection(
                title: "Due today",
                tint: .orange,
                chores: dueTodayChores,
                viewModel: viewModel,
                householdId: householdId,
                householdMembers: viewModel.householdMembers,
                isCompletingChoreId: isCompletingChoreId,
                onComplete: completeFromSwipe,
                onOpenSheet: { completionChore = $0 }
            )

            ChoreBucketSection(
                title: "Quick wins",
                tint: .gray,
                chores: quickWinChores,
                viewModel: viewModel,
                householdId: householdId,
                householdMembers: viewModel.householdMembers,
                isCompletingChoreId: isCompletingChoreId,
                onComplete: completeFromSwipe,
                onOpenSheet: { completionChore = $0 }
            )
        }
        .listStyle(.insetGrouped)
    }

    private func completeFromSwipe(_ chore: APIChore) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        completionChore = chore
    }

    private func sortByDueThenTitle(_ lhs: APIChore, _ rhs: APIChore) -> Bool {
        let leftSnapshot = lhs.scheduleSnapshot()
        let rightSnapshot = rhs.scheduleSnapshot()
        let leftDate = leftSnapshot.currentDueDate ?? leftSnapshot.nextDueDate ?? .distantFuture
        let rightDate = rightSnapshot.currentDueDate ?? rightSnapshot.nextDueDate ?? .distantFuture
        if leftDate != rightDate { return leftDate < rightDate }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
}

private struct ChoreBucketSection: View {
    let title: String
    let tint: Color
    let chores: [APIChore]
    let viewModel: ChoresViewModel
    let householdId: String
    let householdMembers: [APIHouseholdMember]
    let isCompletingChoreId: String?
    let onComplete: (APIChore) -> Void
    let onOpenSheet: (APIChore) -> Void

    var body: some View {
        Section {
            if chores.isEmpty {
                Text("Nothing here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(chores) { chore in
                    NavigationLink {
                        ChoreDetailView(chore: chore, viewModel: viewModel, householdId: householdId)
                    } label: {
                        ChoreRow(
                            chore: chore,
                            schedule: chore.scheduleSnapshot(),
                            assigneeName: displayName(for: chore.assignedToUserId)
                        )
                    }
                    .opacity(isCompletingChoreId == chore.id ? 0.5 : 1)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("Complete", systemImage: "checkmark") {
                            onComplete(chore)
                        }
                        .tint(.green)
                    }
                    .contextMenu {
                        Button("Complete with notes", systemImage: "square.and.pencil") {
                            onOpenSheet(chore)
                        }
                    }
                }
            }
        } header: {
            Label(title, systemImage: "circle.fill")
                .foregroundStyle(tint)
        }
    }

    private func displayName(for userId: String?) -> String? {
        guard let userId else { return nil }
        return householdMembers.first(where: { $0.userId == userId })?.displayName
    }
}

private struct TodaySkeletonView: View {
    var body: some View {
        List {
            ForEach(["Overdue", "Due today", "Quick wins"], id: \.self) { title in
                Section(title) {
                    ForEach(0..<2, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 8) {
                            RoundedRectangle(cornerRadius: 5)
                                .frame(width: 180, height: 18)
                            RoundedRectangle(cornerRadius: 4)
                                .frame(width: 240, height: 12)
                        }
                        .foregroundStyle(.quaternary)
                        .padding(.vertical, 6)
                        .redacted(reason: .placeholder)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .disabled(true)
    }
}

private struct MilestoneCelebrationView: View {
    let streak: Int

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
            VStack(spacing: 18) {
                ZStack {
                    ForEach(0..<18, id: \.self) { index in
                        Capsule()
                            .fill(colors[index % colors.count])
                            .frame(width: 8, height: 22)
                            .rotationEffect(.degrees(Double(index) * 21))
                            .offset(x: CGFloat((index % 6) - 3) * 30, y: CGFloat((index / 6) - 1) * 28)
                    }
                }
                .frame(width: 220, height: 120)

                VStack(spacing: 6) {
                    Label("\(streak) day streak", systemImage: "flame.fill")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.orange)
                    Text("Milestone reached")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .allowsHitTesting(false)
    }

    private var colors: [Color] {
        [.red, .orange, .yellow, .green, .blue, .purple]
    }
}

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
                    RoomChoreSkeletonView()
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
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    completionChore = chore
                                }
                                .tint(.green)
                            }
                        }
                    }
                } header: {
                    HStack {
                        RoomHeaderLabel(room: room)
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
                    HStack(alignment: .top, spacing: 10) {
                        UserAvatarView(
                            userId: item.completedBy.id,
                            displayName: item.completedBy.displayName,
                            hasAvatar: item.completedBy.hasAvatar ?? false,
                            size: 34
                        )
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

private struct RoomChoreSkeletonView: View {
    var body: some View {
        List {
            ForEach(0..<3, id: \.self) { _ in
                Section {
                    ForEach(0..<3, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 8) {
                            RoundedRectangle(cornerRadius: 5)
                                .frame(width: 170, height: 18)
                            RoundedRectangle(cornerRadius: 4)
                                .frame(width: 230, height: 12)
                        }
                        .foregroundStyle(.quaternary)
                        .padding(.vertical, 6)
                        .redacted(reason: .placeholder)
                    }
                } header: {
                    RoundedRectangle(cornerRadius: 4)
                        .frame(width: 120, height: 14)
                        .foregroundStyle(.quaternary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .disabled(true)
    }
}

struct RoomHeaderLabel: View {
    let room: APIRoom

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: room.icon ?? "rectangle.on.rectangle")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tint)
                .frame(width: 26, height: 26)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(.tint.opacity(0.18), lineWidth: 1)
                )
            Text(room.name)
        }
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
            Text(initials)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(.tint, in: Circle())
            Text(name)
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.thinMaterial, in: Capsule())
    }

    private var initials: String {
        let parts = name.split(separator: " ").map(String.init)
        let letters = parts.prefix(2).compactMap { $0.first }.map { String($0).uppercased() }
        return letters.isEmpty ? String(name.prefix(2)).uppercased() : letters.joined()
    }
}

#Preview {
    ChoreListView()
        .environment(AuthStore())
}
