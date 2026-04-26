import Foundation
import SwiftData

@Observable
@MainActor
final class ChoresViewModel {
    private(set) var rooms: [APIRoom] = []
    private(set) var choresByRoom: [String: [APIChore]] = [:]
    private(set) var isLoading = false
    var error: APIError?

    private let client = APIClient.shared

    func allRooms(includeArchived: Bool = false) -> [APIRoom] {
        rooms.filter { includeArchived || !$0.archived }
    }

    func chores(for roomId: String, includeArchived: Bool = false) -> [APIChore] {
        let chores = choresByRoom[roomId] ?? []
        return chores.filter { includeArchived || !$0.archived }
    }

    func load(householdId: String, context: ModelContext) async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let roomsResult: [APIRoom] = client.send(
                path: "/households/\(householdId)/rooms",
                query: [URLQueryItem(name: "includeArchived", value: "true")]
            )
            async let choresResult: [APIChore] = client.send(
                path: "/households/\(householdId)/chores",
                query: [URLQueryItem(name: "includeArchived", value: "true")]
            )
            let (fetchedRooms, fetchedChores) = try await (roomsResult, choresResult)
            rooms = fetchedRooms
            choresByRoom = Dictionary(grouping: fetchedChores, by: \.roomId)

            // Sync to local cache
            for room in fetchedRooms {
                let roomID = room.id
                let existing = try? context.fetch(
                    FetchDescriptor<LocalRoom>(predicate: #Predicate { $0.id == roomID })
                ).first
                if let existing {
                    existing.update(from: room)
                } else {
                    context.insert(LocalRoom(from: room))
                }
            }
            for chore in fetchedChores {
                let choreID = chore.id
                let existing = try? context.fetch(
                    FetchDescriptor<LocalChore>(predicate: #Predicate { $0.id == choreID })
                ).first
                if let existing {
                    existing.update(from: chore)
                } else {
                    context.insert(LocalChore(from: chore))
                }
            }
        } catch let err as APIError {
            error = err
        } catch {
            self.error = .server(code: "INTERNAL", message: error.localizedDescription)
        }
    }

    func completeChore(_ choreId: String, householdId: String, notes: String? = nil) async {
        let tz = TimeZone.current.identifier
        let body = CompleteChoreBody(notes: notes, tz: tz)
        do {
            let _: CompleteChoreResponse = try await client.send(
                path: "/households/\(householdId)/chores/\(choreId)/complete",
                method: "POST",
                body: body
            )
            // Refresh to update the list
            await load(householdId: householdId, context: ModelContext(try! ModelContainer(for: LocalRoom.self, LocalChore.self)))
        } catch let err as APIError {
            error = err
        } catch {
            self.error = .server(code: "INTERNAL", message: error.localizedDescription)
        }
    }

    func createRoom(name: String, icon: String?, householdId: String) async -> APIRoom? {
        do {
            let room: APIRoom = try await client.send(
                path: "/households/\(householdId)/rooms",
                method: "POST",
                body: CreateRoomBody(name: name, icon: icon)
            )
            rooms.append(room)
            rooms.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            return room
        } catch let err as APIError {
            error = err
            return nil
        } catch {
            self.error = .server(code: "INTERNAL", message: error.localizedDescription)
            return nil
        }
    }

    func createChore(_ body: CreateChoreBody, householdId: String) async -> APIChore? {
        do {
            let chore: APIChore = try await client.send(
                path: "/households/\(householdId)/chores",
                method: "POST",
                body: body
            )
            choresByRoom[chore.roomId, default: []].append(chore)
            return chore
        } catch let err as APIError {
            error = err
            return nil
        } catch {
            self.error = .server(code: "INTERNAL", message: error.localizedDescription)
            return nil
        }
    }

    func updateRoom(
        roomId: String,
        name: String,
        icon: String?,
        archived: Bool,
        householdId: String
    ) async -> APIRoom? {
        do {
            let room: APIRoom = try await client.send(
                path: "/households/\(householdId)/rooms/\(roomId)",
                method: "PUT",
                body: UpdateRoomBody(name: name, icon: icon, archived: archived)
            )
            replaceRoom(room)
            return room
        } catch let err as APIError {
            error = err
            return nil
        } catch {
            self.error = .server(code: "INTERNAL", message: error.localizedDescription)
            return nil
        }
    }

    func setRoomArchived(_ roomId: String, archived: Bool, householdId: String) async {
        guard let room = rooms.first(where: { $0.id == roomId }) else { return }
        _ = await updateRoom(
            roomId: roomId,
            name: room.name,
            icon: room.icon,
            archived: archived,
            householdId: householdId
        )
    }

    func updateChore(
        choreId: String,
        body: UpdateChoreBody,
        householdId: String
    ) async -> APIChore? {
        do {
            let chore: APIChore = try await client.send(
                path: "/households/\(householdId)/chores/\(choreId)",
                method: "PUT",
                body: body
            )
            replaceChore(chore)
            return chore
        } catch let err as APIError {
            error = err
            return nil
        } catch {
            self.error = .server(code: "INTERNAL", message: error.localizedDescription)
            return nil
        }
    }

    func setChoreArchived(_ chore: APIChore, archived: Bool, householdId: String) async {
        _ = await updateChore(
            choreId: chore.id,
            body: UpdateChoreBody(
                roomId: nil,
                title: nil,
                description: nil,
                recurrence: nil,
                estimatedMinutes: nil,
                points: nil,
                archived: archived
            ),
            householdId: householdId
        )
    }

    func deleteChore(_ choreId: String, roomId: String, householdId: String) async {
        do {
            try await client.send(
                path: "/households/\(householdId)/chores/\(choreId)",
                method: "DELETE",
                body: Optional<String>.none
            )
            choresByRoom[roomId]?.removeAll { $0.id == choreId }
        } catch let err as APIError {
            error = err
        } catch {
            self.error = .server(code: "INTERNAL", message: error.localizedDescription)
        }
    }

    func mergeChores(_ chores: [APIChore]) {
        for chore in chores {
            choresByRoom[chore.roomId, default: []].append(chore)
        }
    }

    private func replaceRoom(_ updatedRoom: APIRoom) {
        if let index = rooms.firstIndex(where: { $0.id == updatedRoom.id }) {
            rooms[index] = updatedRoom
        } else {
            rooms.append(updatedRoom)
        }
        rooms.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func replaceChore(_ updatedChore: APIChore) {
        for roomId in choresByRoom.keys {
            choresByRoom[roomId]?.removeAll { $0.id == updatedChore.id }
        }
        choresByRoom[updatedChore.roomId, default: []].append(updatedChore)
        choresByRoom[updatedChore.roomId]?.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
}
