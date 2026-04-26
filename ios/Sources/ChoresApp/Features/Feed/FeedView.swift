import SwiftUI

@Observable
@MainActor
final class FeedViewModel {
    private(set) var items: [FeedItem] = []
    private(set) var isLoading = false
    var error: APIError?

    func load(householdId: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await APIClient.shared.send(
                path: "/households/\(householdId)/feed",
                query: [URLQueryItem(name: "limit", value: "50")]
            )
        } catch let err as APIError {
            error = err
        } catch {
            self.error = .server(code: "INTERNAL", message: error.localizedDescription)
        }
    }
}

struct FeedView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var viewModel = FeedViewModel()

    var householdId: String { authStore.currentHouseholdId ?? "" }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.items.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.items.isEmpty {
                    EmptyStateView(
                        icon: "list.bullet.below.rectangle",
                        title: "No activity yet",
                        message: "Completed chores will appear here."
                    )
                } else {
                    List(viewModel.items) { item in
                        FeedItemRow(item: item)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Activity")
            .refreshable { await viewModel.load(householdId: householdId) }
            .errorAlert($viewModel.error)
        }
        .task(id: householdId) { await viewModel.load(householdId: householdId) }
    }
}

struct FeedItemRow: View {
    let item: FeedItem

    private var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let date = ISO8601DateFormatter().date(from: item.completedAt) ?? .now
        return formatter.localizedString(for: date, relativeTo: .now)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title2)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(item.completedBy.displayName) completed **\(item.chore?.title ?? "a chore")**")
                    .font(.subheadline)
                if let notes = item.notes, !notes.isEmpty {
                    Text(notes).font(.caption).foregroundStyle(.secondary)
                }
                Text(timeAgo)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    FeedView().environment(AuthStore())
}
