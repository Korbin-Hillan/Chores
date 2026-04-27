import SwiftUI

@Observable
@MainActor
final class LeaderboardViewModel {
    private(set) var entries: [LeaderboardEntry] = []
    private(set) var isLoading = false
    var error: APIError?
    var period: String = "week"

    func load(householdId: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            entries = try await APIClient.shared.send(
                path: "/households/\(householdId)/leaderboard",
                query: [URLQueryItem(name: "period", value: period)]
            )
        } catch let err as APIError {
            error = err
        } catch {
            self.error = .server(code: "INTERNAL", message: error.localizedDescription)
        }
    }
}

struct LeaderboardView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var viewModel = LeaderboardViewModel()

    var householdId: String { authStore.currentHouseholdId ?? "" }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.entries.isEmpty {
                    LeaderboardSkeletonView()
                } else if viewModel.entries.isEmpty {
                    EmptyStateView(
                        icon: "trophy",
                        title: "No completions yet",
                        message: "Complete some chores to appear on the leaderboard!"
                    )
                } else {
                    List {
                        ForEach(Array(viewModel.entries.enumerated()), id: \.element.id) { index, entry in
                            LeaderboardRow(rank: index + 1, entry: entry)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Leaderboard")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Picker("Period", selection: $viewModel.period) {
                        Text("This week").tag("week")
                        Text("This month").tag("month")
                        Text("All time").tag("all")
                    }
                    .pickerStyle(.menu)
                    .onChange(of: viewModel.period) { _, _ in
                        Task { await viewModel.load(householdId: householdId) }
                    }
                }
            }
            .refreshable { await viewModel.load(householdId: householdId) }
            .errorAlert($viewModel.error)
        }
        .task(id: householdId) { await viewModel.load(householdId: householdId) }
    }
}

struct LeaderboardRow: View {
    let rank: Int
    let entry: LeaderboardEntry
    @Environment(AuthStore.self) private var authStore

    private var isMe: Bool { entry.userId == authStore.currentUser?.id }

    var rankEmoji: String {
        switch rank {
        case 1: return "🥇"
        case 2: return "🥈"
        case 3: return "🥉"
        default: return "\(rank)"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(rankEmoji)
                .font(rank <= 3 ? .title2 : .body)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(entry.displayName)
                        .font(.body.weight(isMe ? .semibold : .regular))
                    if isMe {
                        Text("(you)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Label("\(entry.currentStreak) day streak", systemImage: "flame.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(entry.completionCount)")
                    .font(.title3.bold())
                Text("done").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct LeaderboardSkeletonView: View {
    var body: some View {
        List {
            ForEach(0..<6, id: \.self) { index in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 6)
                        .frame(width: 32, height: 24)
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 5)
                            .frame(width: index == 0 ? 170 : 130, height: 16)
                        RoundedRectangle(cornerRadius: 4)
                            .frame(width: 95, height: 12)
                    }
                    Spacer()
                    RoundedRectangle(cornerRadius: 5)
                        .frame(width: 42, height: 22)
                }
                .foregroundStyle(.quaternary)
                .padding(.vertical, 6)
                .redacted(reason: .placeholder)
            }
        }
        .listStyle(.insetGrouped)
        .disabled(true)
    }
}

@Observable
@MainActor
final class RewardsViewModel {
    private(set) var rewards: [APIReward] = []
    private(set) var balance: RewardBalance?
    private(set) var pendingRedemptions: [APIRewardRedemption] = []
    private(set) var myRedemptions: [APIRewardRedemption] = []
    private(set) var members: [APIHouseholdMember] = []
    private(set) var isLoading = false
    var error: APIError?

    func load(householdId: String) async {
        guard !householdId.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let rewardsResult: RewardsResponse = APIClient.shared.send(path: "/households/\(householdId)/rewards")
            async let detailResult: APIHouseholdDetail = APIClient.shared.send(path: "/households/\(householdId)")
            async let mineResult: [APIRewardRedemption] = APIClient.shared.send(
                path: "/households/\(householdId)/rewards/redemptions",
                query: [URLQueryItem(name: "mine", value: "true")]
            )

            let (rewardsResponse, detail, mine) = try await (rewardsResult, detailResult, mineResult)
            rewards = rewardsResponse.rewards
            balance = rewardsResponse.balance
            members = detail.members
            myRedemptions = mine

        } catch let err as APIError {
            error = err
        } catch {
            self.error = .server(code: "INTERNAL", message: error.localizedDescription)
        }
    }

    func loadPendingRedemptions(householdId: String) async {
        do {
            pendingRedemptions = try await APIClient.shared.send(
                path: "/households/\(householdId)/rewards/redemptions",
                query: [URLQueryItem(name: "status", value: "pending")]
            )
        } catch {
            pendingRedemptions = []
        }
    }

    func createReward(title: String, description: String?, costPoints: Int, householdId: String) async -> Bool {
        do {
            let _: APIReward = try await APIClient.shared.send(
                path: "/households/\(householdId)/rewards",
                method: "POST",
                body: CreateRewardBody(title: title, description: description, costPoints: costPoints)
            )
            await load(householdId: householdId)
            return true
        } catch let err as APIError {
            error = err
            return false
        } catch {
            self.error = .server(code: "INTERNAL", message: error.localizedDescription)
            return false
        }
    }

    func setRewardArchived(_ reward: APIReward, archived: Bool, householdId: String) async {
        do {
            let _: APIReward = try await APIClient.shared.send(
                path: "/households/\(householdId)/rewards/\(reward.id)",
                method: "PUT",
                body: UpdateRewardBody(
                    title: nil,
                    description: nil,
                    costPoints: nil,
                    archived: archived
                )
            )
            await load(householdId: householdId)
        } catch let err as APIError {
            error = err
        } catch {
            self.error = .server(code: "INTERNAL", message: error.localizedDescription)
        }
    }

    func redeem(_ reward: APIReward, householdId: String) async {
        do {
            let _: APIRewardRedemption = try await APIClient.shared.send(
                path: "/households/\(householdId)/rewards/\(reward.id)/redeem",
                method: "POST",
                body: Optional<String>.none
            )
            await load(householdId: householdId)
        } catch let err as APIError {
            error = err
        } catch {
            self.error = .server(code: "INTERNAL", message: error.localizedDescription)
        }
    }

    func approve(_ redemption: APIRewardRedemption, householdId: String) async {
        do {
            let _: APIRewardRedemption = try await APIClient.shared.send(
                path: "/households/\(householdId)/rewards/redemptions/\(redemption.id)/approve",
                method: "POST",
                body: Optional<String>.none
            )
            pendingRedemptions.removeAll { $0.id == redemption.id }
            await load(householdId: householdId)
        } catch let err as APIError {
            error = err
        } catch {
            self.error = .server(code: "INTERNAL", message: error.localizedDescription)
        }
    }

    func reject(_ redemption: APIRewardRedemption, householdId: String) async {
        do {
            let _: APIRewardRedemption = try await APIClient.shared.send(
                path: "/households/\(householdId)/rewards/redemptions/\(redemption.id)/reject",
                method: "POST",
                body: RejectRewardRedemptionBody(rejectionReason: nil)
            )
            pendingRedemptions.removeAll { $0.id == redemption.id }
            await load(householdId: householdId)
        } catch let err as APIError {
            error = err
        } catch {
            self.error = .server(code: "INTERNAL", message: error.localizedDescription)
        }
    }
}

struct RewardsView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var viewModel = RewardsViewModel()
    @State private var showCreateReward = false

    var householdId: String { authStore.currentHouseholdId ?? "" }

    private var currentRole: String? {
        guard let currentUserId = authStore.currentUser?.id else { return nil }
        return viewModel.members.first(where: { $0.userId == currentUserId })?.role
    }

    private var isAdmin: Bool {
        currentRole == "admin"
    }

    private var canReview: Bool {
        currentRole == "admin" || currentRole == "parent"
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.rewards.isEmpty {
                    RewardsSkeletonView()
                } else {
                    List {
                        balanceSection
                        pendingSection
                        rewardsSection
                        historySection
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Rewards")
            .toolbar {
                if isAdmin {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Add", systemImage: "plus") { showCreateReward = true }
                    }
                }
            }
            .sheet(isPresented: $showCreateReward) {
                RewardEditorSheet(viewModel: viewModel, householdId: householdId)
            }
            .refreshable {
                await viewModel.load(householdId: householdId)
                if canReview { await viewModel.loadPendingRedemptions(householdId: householdId) }
            }
            .errorAlert($viewModel.error)
        }
        .task(id: householdId) {
            await viewModel.load(householdId: householdId)
        }
        .task(id: canReview) {
            if canReview {
                await viewModel.loadPendingRedemptions(householdId: householdId)
            }
        }
    }

    @ViewBuilder
    private var balanceSection: some View {
        if let balance = viewModel.balance {
            Section {
                HStack {
                    Label("Available", systemImage: "star.circle.fill")
                        .foregroundStyle(.yellow)
                    Spacer()
                    Text("\(balance.availablePoints) pts")
                        .font(.title3.bold())
                }
                if balance.pendingRedemptionPoints > 0 {
                    LabeledContent("Pending redemptions", value: "\(balance.pendingRedemptionPoints) pts")
                }
                LabeledContent("Earned total", value: "\(balance.earnedPoints) pts")
            }
        }
    }

    @ViewBuilder
    private var pendingSection: some View {
        if canReview && !viewModel.pendingRedemptions.isEmpty {
            Section("Pending approval") {
                ForEach(viewModel.pendingRedemptions) { redemption in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(redemption.rewardTitleSnapshot)
                            .font(.subheadline.weight(.semibold))
                        Text("\(redemption.requestedBy?.displayName ?? "Someone") wants to redeem \(redemption.costPointsSnapshot) pts")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Approve", systemImage: "checkmark.circle.fill") {
                                Task { await viewModel.approve(redemption, householdId: householdId) }
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Reject", systemImage: "xmark.circle") {
                                Task { await viewModel.reject(redemption, householdId: householdId) }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var rewardsSection: some View {
        Section("Rewards") {
            if viewModel.rewards.isEmpty {
                Text(isAdmin ? "Add a reward to make points useful." : "No rewards yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.rewards) { reward in
                    RewardRow(
                        reward: reward,
                        canManage: isAdmin,
                        onRedeem: { Task { await viewModel.redeem(reward, householdId: householdId) } },
                        onArchive: {
                            Task { await viewModel.setRewardArchived(reward, archived: true, householdId: householdId) }
                        }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var historySection: some View {
        if !viewModel.myRedemptions.isEmpty {
            Section("My redemptions") {
                ForEach(viewModel.myRedemptions) { redemption in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(redemption.rewardTitleSnapshot)
                            Text(redemption.status.capitalized)
                                .font(.caption)
                                .foregroundStyle(statusColor(redemption.status))
                        }
                        Spacer()
                        Text("\(redemption.costPointsSnapshot) pts")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "approved": return .green
        case "rejected": return .red
        default: return .orange
        }
    }
}

private struct RewardsSkeletonView: View {
    var body: some View {
        List {
            Section {
                ForEach(0..<3, id: \.self) { _ in
                    HStack {
                        RoundedRectangle(cornerRadius: 5)
                            .frame(width: 150, height: 16)
                        Spacer()
                        RoundedRectangle(cornerRadius: 5)
                            .frame(width: 70, height: 20)
                    }
                    .foregroundStyle(.quaternary)
                    .padding(.vertical, 6)
                    .redacted(reason: .placeholder)
                }
            }
            Section {
                ForEach(0..<4, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 5)
                            .frame(width: 210, height: 18)
                        RoundedRectangle(cornerRadius: 4)
                            .frame(width: 120, height: 12)
                    }
                    .foregroundStyle(.quaternary)
                    .padding(.vertical, 6)
                    .redacted(reason: .placeholder)
                }
            }
        }
        .listStyle(.insetGrouped)
        .disabled(true)
    }
}

private struct RewardRow: View {
    let reward: APIReward
    let canManage: Bool
    let onRedeem: () -> Void
    let onArchive: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "gift.fill")
                .foregroundStyle(.pink)
                .font(.title3)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(reward.title)
                    .font(.body.weight(.semibold))
                if let description = reward.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("\(reward.costPoints) pts")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if canManage {
                Menu {
                    Button("Archive", systemImage: "archivebox", role: .destructive) { onArchive() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .frame(width: 36, height: 36)
                }
            } else {
                Button("Redeem") { onRedeem() }
                    .buttonStyle(.borderedProminent)
                    .disabled(reward.canRedeem == false)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct RewardEditorSheet: View {
    let viewModel: RewardsViewModel
    let householdId: String

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var description = ""
    @State private var costPoints = ""
    @State private var isSaving = false

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && (Int(costPoints) ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Reward") {
                    TextField("Title", text: $title)
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("Point cost", text: $costPoints)
                        .keyboardType(.numberPad)
                }
            }
            .navigationTitle("New reward")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave || isSaving)
                }
            }
            .loadingOverlay(isSaving)
        }
    }

    private func save() {
        guard let points = Int(costPoints) else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
            if await viewModel.createReward(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                description: trimmedDescription.isEmpty ? nil : trimmedDescription,
                costPoints: points,
                householdId: householdId
            ) {
                dismiss()
            }
        }
    }
}

#Preview {
    LeaderboardView().environment(AuthStore())
}
