import SwiftUI

@Observable
@MainActor
final class ChoreCompletionHistoryViewModel {
    private(set) var items: [ChoreCompletionHistoryItem] = []
    private(set) var isLoading = false
    var error: APIError?

    func load(householdId: String, choreId: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await APIClient.shared.send(
                path: "/households/\(householdId)/chores/\(choreId)/completions",
                query: [URLQueryItem(name: "limit", value: "20")]
            )
        } catch let err as APIError {
            error = err
        } catch {
            self.error = .server(code: "INTERNAL", message: error.localizedDescription)
        }
    }
}

struct ChoreDetailView: View {
    let chore: APIChore
    let viewModel: ChoresViewModel
    let householdId: String

    @State private var showComplete = false
    @State private var isCompleting = false
    @State private var historyViewModel = ChoreCompletionHistoryViewModel()
    @Environment(\.dismiss) private var dismiss

    private var schedule: ChoreScheduleSnapshot {
        chore.scheduleSnapshot()
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Title", value: chore.title)
                if let desc = chore.description, !desc.isEmpty {
                    LabeledContent("Notes", value: desc)
                }
            }
            Section("Schedule") {
                LabeledContent("Repeats", value: chore.recurrence.kind.rawValue.capitalized)
                if let statusText {
                    LabeledContent("Status", value: statusText)
                }
                if let nextDueText {
                    LabeledContent("Next due", value: nextDueText)
                }
                if let lastCompletedText {
                    LabeledContent("Last done", value: lastCompletedText)
                }
                if let mins = chore.estimatedMinutes {
                    LabeledContent("Estimated", value: "\(mins) min")
                }
                LabeledContent("Points", value: "\(chore.points)")
            }
            Section("Info") {
                LabeledContent("Source", value: chore.source == "manual" ? "Created manually" : "AI generated")
            }
            Section {
                Button("Mark as complete") { showComplete = true }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.green)
            }

            Section("Completion history") {
                if historyViewModel.isLoading && historyViewModel.items.isEmpty {
                    ProgressView()
                } else if historyViewModel.items.isEmpty {
                    Text("No completions yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(historyViewModel.items) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.completedBy.displayName)
                                .font(.subheadline.weight(.medium))
                            Text(historyTimestamp(for: item))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let notes = item.notes, !notes.isEmpty {
                                Text(notes)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle(chore.title)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Complete chore", isPresented: $showComplete, titleVisibility: .visible) {
            Button("Complete") {
                Task {
                    isCompleting = true
                    await viewModel.completeChore(chore.id, householdId: householdId)
                    await historyViewModel.load(householdId: householdId, choreId: chore.id)
                    isCompleting = false
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Mark \"\(chore.title)\" as done?")
        }
        .loadingOverlay(isCompleting)
        .errorAlert($historyViewModel.error)
        .task(id: chore.id) { await historyViewModel.load(householdId: householdId, choreId: chore.id) }
    }

    private var statusText: String? {
        switch schedule.state {
        case .unscheduled:
            return "No recurrence"
        case .dueToday:
            return "Due today"
        case .overdue(let date):
            return "Overdue since \(formatDate(date, includeTime: false))"
        case .upcoming(let date):
            return "Upcoming on \(formatDate(date, includeTime: false))"
        }
    }

    private var nextDueText: String? {
        guard let nextDueDate = schedule.nextDueDate else { return nil }
        return formatDate(nextDueDate, includeTime: false)
    }

    private var lastCompletedText: String? {
        guard let lastCompletedDate = schedule.lastCompletedDate else { return nil }
        return formatDate(lastCompletedDate, includeTime: true)
    }

    private func historyTimestamp(for item: ChoreCompletionHistoryItem) -> String {
        let formatter = ISO8601DateFormatter()
        let date = formatter.date(from: item.completedAt) ?? .now
        return formatDate(date, includeTime: true)
    }

    private func formatDate(_ date: Date, includeTime: Bool) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = includeTime ? .short : .none
        return formatter.string(from: date)
    }
}
