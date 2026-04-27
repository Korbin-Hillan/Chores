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
                    FeedSkeletonView()
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
            UserAvatarView(
                userId: item.completedBy.id,
                displayName: item.completedBy.displayName,
                hasAvatar: item.completedBy.hasAvatar ?? false,
                size: 40
            )
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("\(item.completedBy.displayName) completed **\(item.chore?.title ?? "a chore")**")
                }
                .font(.subheadline)
                if let socialText {
                    Text(socialText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if item.reviewStatus == "pending" {
                    Label("Pending review", systemImage: "hourglass")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if let notes = item.notes, !notes.isEmpty {
                    Text(notes).font(.caption).foregroundStyle(.secondary)
                }
                if item.hasPhoto {
                    CompletionPhotoView(
                        householdId: item.chore?.householdId ?? "",
                        completionId: item.id
                    )
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                Text(timeAgo)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private var socialText: String? {
        guard
            let chore = item.chore,
            let assignedTo = item.assignedToAtCompletion,
            assignedTo.id != item.completedBy.id
        else { return nil }
        return "\(item.completedBy.displayName) did \(assignedTo.displayName)'s \(chore.title) 🌟"
    }
}

private struct FeedSkeletonView: View {
    var body: some View {
        List {
            ForEach(0..<6, id: \.self) { _ in
                HStack(alignment: .top, spacing: 12) {
                    Circle()
                        .frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 5)
                            .frame(width: 220, height: 16)
                        RoundedRectangle(cornerRadius: 4)
                            .frame(width: 150, height: 12)
                    }
                }
                .foregroundStyle(.quaternary)
                .padding(.vertical, 6)
                .redacted(reason: .placeholder)
            }
        }
        .listStyle(.plain)
        .disabled(true)
    }
}

#Preview {
    FeedView().environment(AuthStore())
}
