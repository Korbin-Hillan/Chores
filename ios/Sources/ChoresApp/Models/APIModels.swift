import Foundation

private let apiDateFormatter = ISO8601DateFormatter()

// MARK: - Auth

struct AuthResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let user: APIUser
}

struct APIUser: Codable, Identifiable {
    let id: String
    let email: String
    let displayName: String
    let currentHouseholdId: String?
}

// MARK: - Household

struct APIHousehold: Decodable, Identifiable {
    let id: String
    let name: String
    let inviteCode: String
    let adminUserId: String
    let openAIKeyIsSet: Bool
    let openAIKeySetAt: String?
}

struct APIHouseholdDetail: Decodable {
    let household: APIHousehold
    let members: [APIHouseholdMember]
}

struct APIHouseholdMember: Decodable, Identifiable {
    let id: String
    let householdId: String
    let userId: String
    let role: String
    let currentStreak: Int
    let longestStreak: Int
    let lastCompletionAt: String?
    let displayName: String?
}

struct OpenAIKeyStatus: Decodable {
    let isSet: Bool
    let setAt: String?
}

// MARK: - Rooms

struct APIRoom: Decodable, Identifiable {
    let id: String
    let householdId: String
    let name: String
    let icon: String?
    let archived: Bool
}

// MARK: - Chores

struct Recurrence: Codable, Equatable {
    let kind: RecurrenceKind
    let weekdays: [Int]?
    let dayOfMonth: Int?

    enum RecurrenceKind: String, Codable {
        case none, daily, weekly, monthly
    }
}

struct APIChore: Decodable, Identifiable {
    let id: String
    let householdId: String
    let roomId: String
    let title: String
    let description: String?
    let recurrence: Recurrence
    let estimatedMinutes: Int?
    let points: Int
    let createdByUserId: String
    let source: String
    let archived: Bool
    let createdAt: String
    let lastCompletedAt: String?
}

struct APICompletion: Decodable, Identifiable {
    let id: String
    let choreId: String
    let householdId: String
    let completedByUserId: String
    let completedAt: String
    let notes: String?
}

struct CompleteChoreResponse: Decodable {
    let completion: APICompletion
    let membership: APIHouseholdMember
}

// MARK: - Feed

struct FeedItem: Decodable, Identifiable {
    let id: String
    let completedAt: String
    let notes: String?
    let chore: APIChore?
    let completedBy: FeedUser
}

struct FeedUser: Decodable {
    let id: String
    let displayName: String
}

struct ChoreCompletionHistoryItem: Decodable, Identifiable {
    let id: String
    let completedAt: String
    let notes: String?
    let completedBy: FeedUser
}

// MARK: - Leaderboard

struct LeaderboardEntry: Decodable, Identifiable {
    var id: String { userId }
    let userId: String
    let displayName: String
    let completionCount: Int
    let currentStreak: Int
    let longestStreak: Int
}

// MARK: - Generation

struct ChoreDraft: Decodable, Identifiable {
    var id: String { title + suggestedRoomName }
    let title: String
    let description: String?
    let suggestedRoomName: String
    let recurrence: Recurrence
    let estimatedMinutes: Int?
}

struct GenerationResponse: Decodable {
    let jobId: String
    let suggestedChores: [ChoreDraft]
}

// MARK: - Request Bodies (Encodable)

struct SignUpBody: Encodable {
    let email: String
    let password: String
    let displayName: String
}

struct LoginBody: Encodable {
    let email: String
    let password: String
}

struct CreateHouseholdBody: Encodable {
    let name: String
}

struct JoinHouseholdBody: Encodable {
    let inviteCode: String
}

struct CreateRoomBody: Encodable {
    let name: String
    let icon: String?
}

struct UpdateRoomBody: Encodable {
    let name: String?
    let icon: String?
    let archived: Bool?
}

struct CreateChoreBody: Encodable {
    let roomId: String
    let title: String
    let description: String?
    let recurrence: Recurrence
    let estimatedMinutes: Int?
    let points: Int
}

struct UpdateChoreBody: Encodable {
    let roomId: String?
    let title: String?
    let description: String?
    let recurrence: Recurrence?
    let estimatedMinutes: Int?
    let points: Int?
    let archived: Bool?
}

struct CompleteChoreBody: Encodable {
    let notes: String?
    let tz: String
}

struct TextGenerationBody: Encodable {
    let prompt: String
    let roomId: String?
}

struct ImageGenerationBody: Encodable {
    let imageBase64: String
    let mimeType: String
    let roomId: String?
}

struct AcceptGenerationBody: Encodable {
    let acceptedIndices: [Int]
}

struct SetOpenAIKeyBody: Encodable {
    let key: String
}

enum ChoreDueState {
    case unscheduled
    case dueToday
    case overdue(Date)
    case upcoming(Date)
}

struct ChoreScheduleSnapshot {
    let state: ChoreDueState
    let currentDueDate: Date?
    let nextDueDate: Date?
    let lastCompletedDate: Date?
}

extension APIChore {
    var createdDate: Date {
        apiDateFormatter.date(from: createdAt) ?? .now
    }

    var lastCompletedDate: Date? {
        guard let lastCompletedAt else { return nil }
        return apiDateFormatter.date(from: lastCompletedAt)
    }

    func scheduleSnapshot(reference: Date = .now, calendar: Calendar = .current) -> ChoreScheduleSnapshot {
        let today = calendar.startOfDay(for: reference)
        let createdDay = calendar.startOfDay(for: createdDate)
        let lastCompletedDate = self.lastCompletedDate

        guard recurrence.kind != .none else {
            return ChoreScheduleSnapshot(
                state: .unscheduled,
                currentDueDate: nil,
                nextDueDate: nil,
                lastCompletedDate: lastCompletedDate
            )
        }

        let currentDueDate = currentOccurrence(onOrBefore: today, calendar: calendar, createdDay: createdDay)
        let currentOccurrenceCompleted = currentDueDate.map {
            guard let lastCompletedDate else { return false }
            return calendar.isDate(lastCompletedDate, inSameDayAs: $0)
        } ?? false

        if let currentDueDate, !currentOccurrenceCompleted {
            return ChoreScheduleSnapshot(
                state: calendar.isDate(currentDueDate, inSameDayAs: today) ? .dueToday : .overdue(currentDueDate),
                currentDueDate: currentDueDate,
                nextDueDate: nextOccurrence(after: currentDueDate, calendar: calendar),
                lastCompletedDate: lastCompletedDate
            )
        }

        let nextDueDate: Date?
        if let currentDueDate {
            nextDueDate = nextOccurrence(after: currentDueDate, calendar: calendar)
        } else {
            nextDueDate = firstUpcomingOccurrence(onOrAfter: today, calendar: calendar, createdDay: createdDay)
        }

        return ChoreScheduleSnapshot(
            state: nextDueDate.map(ChoreDueState.upcoming) ?? .unscheduled,
            currentDueDate: currentDueDate,
            nextDueDate: nextDueDate,
            lastCompletedDate: lastCompletedDate
        )
    }

    private func currentOccurrence(onOrBefore date: Date, calendar: Calendar, createdDay: Date) -> Date? {
        switch recurrence.kind {
        case .none:
            return nil
        case .daily:
            return date >= createdDay ? date : nil
        case .weekly:
            let weekdays = scheduledWeekdays(calendar: calendar)
            for offset in 0...6 {
                guard let candidate = calendar.date(byAdding: .day, value: -offset, to: date) else { continue }
                if weekdays.contains(calendar.weekdayIndex(for: candidate)), candidate >= createdDay {
                    return candidate
                }
            }
            return nil
        case .monthly:
            let targetDay = scheduledDayOfMonth(calendar: calendar)
            for offset in 0...24 {
                guard let monthDate = calendar.date(byAdding: .month, value: -offset, to: date),
                      let candidate = calendar.monthlyOccurrence(for: monthDate, day: targetDay)
                else { continue }
                if candidate <= date, candidate >= createdDay {
                    return candidate
                }
            }
            return nil
        }
    }

    private func nextOccurrence(after date: Date, calendar: Calendar) -> Date? {
        let start = calendar.startOfDay(for: date)

        switch recurrence.kind {
        case .none:
            return nil
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: start)
        case .weekly:
            let weekdays = scheduledWeekdays(calendar: calendar)
            for offset in 1...14 {
                guard let candidate = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
                if weekdays.contains(calendar.weekdayIndex(for: candidate)) {
                    return candidate
                }
            }
            return nil
        case .monthly:
            let targetDay = scheduledDayOfMonth(calendar: calendar)
            for offset in 1...24 {
                guard let monthDate = calendar.date(byAdding: .month, value: offset, to: start),
                      let candidate = calendar.monthlyOccurrence(for: monthDate, day: targetDay)
                else { continue }
                return candidate
            }
            return nil
        }
    }

    private func firstUpcomingOccurrence(onOrAfter date: Date, calendar: Calendar, createdDay: Date) -> Date? {
        let start = max(calendar.startOfDay(for: date), createdDay)

        switch recurrence.kind {
        case .none:
            return nil
        case .daily:
            return start
        case .weekly:
            let weekdays = scheduledWeekdays(calendar: calendar)
            for offset in 0...14 {
                guard let candidate = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
                if weekdays.contains(calendar.weekdayIndex(for: candidate)) {
                    return candidate
                }
            }
            return nil
        case .monthly:
            let targetDay = scheduledDayOfMonth(calendar: calendar)
            for offset in 0...24 {
                guard let monthDate = calendar.date(byAdding: .month, value: offset, to: start),
                      let candidate = calendar.monthlyOccurrence(for: monthDate, day: targetDay)
                else { continue }
                if candidate >= start {
                    return candidate
                }
            }
            return nil
        }
    }

    private func scheduledWeekdays(calendar: Calendar) -> [Int] {
        let fallbackWeekday = calendar.weekdayIndex(for: createdDate)
        let values = recurrence.weekdays?.sorted() ?? [fallbackWeekday]
        return values.isEmpty ? [fallbackWeekday] : values
    }

    private func scheduledDayOfMonth(calendar: Calendar) -> Int {
        recurrence.dayOfMonth ?? calendar.component(.day, from: createdDate)
    }
}

private extension Calendar {
    func weekdayIndex(for date: Date) -> Int {
        component(.weekday, from: date) - 1
    }

    func monthlyOccurrence(for monthDate: Date, day: Int) -> Date? {
        let components = dateComponents([.year, .month], from: monthDate)
        guard let year = components.year, let month = components.month else { return nil }
        guard let range = range(of: .day, in: .month, for: monthDate) else { return nil }
        let clampedDay = min(day, range.count)
        return date(from: DateComponents(year: year, month: month, day: clampedDay))
    }
}
