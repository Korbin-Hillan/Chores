import Foundation
import OSLog

private let logger = Logger(subsystem: "com.korbinhillan.choresapp", category: "AuthStore")

@Observable
@MainActor
final class AuthStore {
    enum State {
        case loading
        case unauthenticated
        case locked(APIUser)
        case authenticated(APIUser)
    }

    private enum PreferenceKey {
        static let biometricUnlockEnabled = "com.korbinhillan.choresapp.biometricUnlockEnabled"
    }

    private(set) var state: State = .loading
    private(set) var currentHouseholdId: String?
    private(set) var biometricUnlockEnabled = UserDefaults.standard.bool(
        forKey: PreferenceKey.biometricUnlockEnabled
    )

    var isLoggedIn: Bool {
        switch state {
        case .authenticated, .locked:
            return true
        case .loading, .unauthenticated:
            return false
        }
    }

    var currentUser: APIUser? {
        switch state {
        case .authenticated(let user), .locked(let user):
            return user
        case .loading, .unauthenticated:
            return nil
        }
    }

    var supportsBiometricUnlock: Bool {
        BiometricAuth.isAvailable
    }

    var biometricUnlockName: String {
        BiometricAuth.localizedBiometryName
    }

    private let client = APIClient.shared

    init() {
        Task { await bootstrap() }
    }

    // MARK: - Bootstrap

    func bootstrap() async {
        await configureClient()

        let cachedUser = loadCurrentUser()
        currentHouseholdId = KeychainStore.get(.currentHouseholdId) ?? cachedUser?.currentHouseholdId

        let accessToken = KeychainStore.get(.accessToken)
        let refreshToken = KeychainStore.get(.refreshToken)

        guard accessToken != nil || refreshToken != nil else {
            clearLocalSession()
            state = .unauthenticated
            return
        }

        if let accessToken {
            await client.setAccessToken(accessToken)
        }

        if let cachedUser {
            restoreState(for: cachedUser)
        }

        if accessToken == nil, let refreshToken {
            do {
                let response = try await refreshSession(using: refreshToken)
                await persistSession(response)
                restoreState(for: response.user)
            } catch {
                logger.error("Bootstrap refresh failed: \(error.localizedDescription, privacy: .public)")
                clearLocalSession()
                state = .unauthenticated
                return
            }
        }

        do {
            let households: [APIHousehold] = try await client.send(path: "/households/me")
            if let user = loadCurrentUser() {
                updateSelectedHousehold(for: user, households: households)
                if case .loading = state {
                    restoreState(for: user)
                }
            } else if let refreshToken = KeychainStore.get(.refreshToken) {
                let response = try await refreshSession(using: refreshToken)
                await persistSession(response)
                updateSelectedHousehold(for: response.user, households: households)
                restoreState(for: response.user)
            } else if cachedUser == nil {
                clearLocalSession()
                state = .unauthenticated
            }
        } catch let err as APIError {
            switch err {
            case .unauthorized:
                clearLocalSession()
                await client.setAccessToken(nil)
                state = .unauthenticated
            case .transport:
                logger.warning("Bootstrap transport error: \(err.localizedDescription, privacy: .public)")
                if cachedUser == nil {
                    state = .unauthenticated
                }
            default:
                logger.error("Bootstrap validation failed: \(err.localizedDescription, privacy: .public)")
                if cachedUser == nil {
                    state = .unauthenticated
                }
            }
        } catch {
            logger.error("Bootstrap validation failed: \(error.localizedDescription, privacy: .public)")
            if cachedUser == nil {
                state = .unauthenticated
            }
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

    func unlockWithBiometrics() async throws {
        guard case .locked(let user) = state else { return }
        guard supportsBiometricUnlock else {
            throw BiometricAuth.BiometricError.unavailable
        }

        let didAuthenticate = await BiometricAuth.authenticate(
            reason: "Unlock your saved Chores session."
        )
        guard didAuthenticate else {
            throw BiometricAuth.BiometricError.failed
        }

        state = .authenticated(user)
    }

    func setBiometricUnlockEnabled(_ enabled: Bool) async throws {
        if enabled {
            guard supportsBiometricUnlock else {
                throw BiometricAuth.BiometricError.unavailable
            }

            let didAuthenticate = await BiometricAuth.authenticate(
                reason: "Enable \(biometricUnlockName) to unlock your saved Chores session."
            )
            guard didAuthenticate else {
                throw BiometricAuth.BiometricError.failed
            }
        }

        biometricUnlockEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: PreferenceKey.biometricUnlockEnabled)
    }

    func signOut() async {
        let existingToken = KeychainStore.get(.accessToken)

        await client.setOnUnauthorized(nil)
        await client.setTokenRefresher(nil)
        await client.setAccessToken(existingToken)
        try? await client.send(path: "/auth/logout", method: "POST", body: Optional<String>.none)

        clearLocalSession()
        await client.setAccessToken(nil)
        currentHouseholdId = nil
        state = .unauthenticated
    }

    func selectHousehold(_ id: String) {
        currentHouseholdId = id
        try? KeychainStore.set(id, for: .currentHouseholdId)
    }

    func refreshCurrentUser() async {
        do {
            let user: APIUser = try await client.send(path: "/auth/me")
            if let data = try? JSONEncoder().encode(user),
               let userString = String(data: data, encoding: .utf8) {
                try? KeychainStore.set(userString, for: .currentUser)
            }
            restoreState(for: user)
        } catch {
            logger.warning("Refresh current user failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Internals

    private func configureClient() async {
        await client.setTokenRefresher { [weak self] in
            try await self?.performRefresh() ?? { throw APIError.unauthorized }()
        }
        await client.setOnUnauthorized { [weak self] in
            await self?.signOut()
        }
    }

    private func handleAuthResponse(_ response: AuthResponse) async {
        await persistSession(response)
        restoreState(for: response.user)
    }

    private func persistSession(_ response: AuthResponse) async {
        try? KeychainStore.set(response.accessToken, for: .accessToken)
        try? KeychainStore.set(response.refreshToken, for: .refreshToken)

        if let data = try? JSONEncoder().encode(response.user),
           let userString = String(data: data, encoding: .utf8) {
            try? KeychainStore.set(userString, for: .currentUser)
        }

        updateSelectedHousehold(for: response.user)
        await client.setAccessToken(response.accessToken)
        await configureClient()
    }

    private func performRefresh() async throws -> String {
        guard let refreshToken = KeychainStore.get(.refreshToken) else {
            throw APIError.unauthorized
        }

        let response = try await refreshSession(using: refreshToken)
        await persistSession(response)
        return response.accessToken
    }

    private func refreshSession(using refreshToken: String) async throws -> AuthResponse {
        struct RefreshBody: Encodable { let refreshToken: String }
        return try await client.send(
            path: "/auth/refresh",
            method: "POST",
            body: RefreshBody(refreshToken: refreshToken)
        )
    }

    private func restoreState(for user: APIUser) {
        updateSelectedHousehold(for: user)
        if biometricUnlockEnabled && supportsBiometricUnlock {
            state = .locked(user)
        } else {
            state = .authenticated(user)
        }
    }

    private func updateSelectedHousehold(for user: APIUser, households: [APIHousehold] = []) {
        let selectedHouseholdId = KeychainStore.get(.currentHouseholdId)
            ?? user.currentHouseholdId
            ?? households.first?.id

        currentHouseholdId = selectedHouseholdId
        if let selectedHouseholdId {
            try? KeychainStore.set(selectedHouseholdId, for: .currentHouseholdId)
        } else {
            KeychainStore.delete(.currentHouseholdId)
        }
    }

    private func loadCurrentUser() -> APIUser? {
        guard let storedUser = KeychainStore.get(.currentUser),
              let data = storedUser.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(APIUser.self, from: data)
    }

    private func clearLocalSession() {
        KeychainStore.delete(.accessToken)
        KeychainStore.delete(.refreshToken)
        KeychainStore.delete(.currentHouseholdId)
        KeychainStore.delete(.currentUser)
    }
}
