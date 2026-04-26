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
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
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

#Preview {
    LeaderboardView().environment(AuthStore())
}
