import Foundation
import SwiftData

@Model
final class LocalRoom {
    @Attribute(.unique) var id: String
    var householdId: String
    var name: String
    var icon: String?
    var archived: Bool

    init(from api: APIRoom) {
        id = api.id
        householdId = api.householdId
        name = api.name
        icon = api.icon
        archived = api.archived
    }

    func update(from api: APIRoom) {
        name = api.name
        icon = api.icon
        archived = api.archived
    }
}

@Model
final class LocalChore {
    @Attribute(.unique) var id: String
    var householdId: String
    var roomId: String
    var title: String
    var choreDescription: String?
    var recurrenceKind: String
    var estimatedMinutes: Int
    var points: Int
    var source: String
    var archived: Bool
    var createdAt: Date

    init(from api: APIChore) {
        id = api.id
        householdId = api.householdId
        roomId = api.roomId
        title = api.title
        choreDescription = api.description
        recurrenceKind = api.recurrence.kind.rawValue
        estimatedMinutes = api.estimatedMinutes ?? 0
        points = api.points
        source = api.source
        archived = api.archived
        createdAt = ISO8601DateFormatter().date(from: api.createdAt) ?? .now
    }

    func update(from api: APIChore) {
        title = api.title
        choreDescription = api.description
        roomId = api.roomId
        recurrenceKind = api.recurrence.kind.rawValue
        estimatedMinutes = api.estimatedMinutes ?? 0
        points = api.points
        archived = api.archived
    }
}
