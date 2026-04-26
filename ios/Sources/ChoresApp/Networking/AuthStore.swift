import Foundation
import OSLog

private let logger = Logger(subsystem: "com.korbinhillan.choresapp", category: "AuthStore")

@Observable
@MainActor
final class AuthStore {
    enum State {
        case loading
        case unauthenticated
        case authenticated(APIUser)
    }

    private(set) var state: State = .loading
    private(set) var currentHouseholdId: String?

    var isLoggedIn: Bool {
        if case .authenticated = state { return true }
        return false
    }

    var currentUser: APIUser? {
        if case .authenticated(let user) = state { return user }
        return nil
    }

    private let client = APIClient.shared

    init() {
        Task { await self.bootstrap() }
    }

    // MARK: - Bootstrap

    func bootstrap() async {
        guard let token = KeychainStore.get(.accessToken) else {
            state = .unauthenticated
            return
        }
        await client.setAccessToken(token)
        await client.setTokenRefresher { [weak self] in
            try await self?.performRefresh() ?? { throw APIError.unauthorized }()
        }
        await client.setOnUnauthorized { [weak self] in
            await self?.signOut()
        }

        // Try a lightweight call to verify the token is still valid
        do {
            let households: [APIHousehold] = try await client.send(path: "/households/me")
            if let user = await loadCurrentUser() {
                let lastHousehold = KeychainStore.get(.currentHouseholdId) ?? user.currentHouseholdId
                    ?? households.first?.id
                currentHouseholdId = lastHousehold
                state = .authenticated(user)
            } else {
                state = .unauthenticated
            }
        } catch {
            state = .unauthenticated
        }
    }

    // MARK: - Auth actions

    func signUp(email: String, password: String, displayName: String) async throws {
        let body = SignUpBody(email: email, password: password, displayName: displayName)
        let response: AuthResponse = try await client.send(path: "/auth/signup", method: "POST", body: body)
        await handleAuthResponse(response)
    }

    func logIn(email: String, password: String) async throws {
        let body = LoginBody(email: email, password: password)
        let response: AuthResponse = try await client.send(path: "/auth/login", method: "POST", body: body)
        await handleAuthResponse(response)
    }

    func signOut() async {
        try? await client.send(path: "/auth/logout", method: "POST", body: Optional<String>.none)
        KeychainStore.delete(.accessToken)
        KeychainStore.delete(.refreshToken)
        KeychainStore.delete(.currentHouseholdId)
        await client.setAccessToken(nil)
        currentHouseholdId = nil
        state = .unauthenticated
    }

    func selectHousehold(_ id: String) {
        currentHouseholdId = id
        try? KeychainStore.set(id, for: .currentHouseholdId)
    }

    // MARK: - Internals

    private func handleAuthResponse(_ response: AuthResponse) async {
        try? KeychainStore.set(response.accessToken, for: .accessToken)
        try? KeychainStore.set(response.refreshToken, for: .refreshToken)
        await client.setAccessToken(response.accessToken)
        await client.setTokenRefresher { [weak self] in
            try await self?.performRefresh() ?? { throw APIError.unauthorized }()
        }
        await client.setOnUnauthorized { [weak self] in
            await self?.signOut()
        }

        let householdId = response.user.currentHouseholdId
        currentHouseholdId = householdId
        if let householdId {
            try? KeychainStore.set(householdId, for: .currentHouseholdId)
        }
        state = .authenticated(response.user)
    }

    private func performRefresh() async throws -> String {
        guard let refreshToken = KeychainStore.get(.refreshToken) else {
            throw APIError.unauthorized
        }
        struct RefreshBody: Encodable { let refreshToken: String }
        let response: AuthResponse = try await client.send(
            path: "/auth/refresh",
            method: "POST",
            body: RefreshBody(refreshToken: refreshToken)
        )
        try? KeychainStore.set(response.accessToken, for: .accessToken)
        try? KeychainStore.set(response.refreshToken, for: .refreshToken)
        return response.accessToken
    }

    private func loadCurrentUser() async -> APIUser? {
        // Decode userId from the access token (JWT payload is base64url encoded)
        // Instead, we cache the user from the last auth response.
        // Re-fetch is done via a lightweight endpoint if we add one later.
        // For now, re-fetch from households list + stored info.
        nil
    }
}
