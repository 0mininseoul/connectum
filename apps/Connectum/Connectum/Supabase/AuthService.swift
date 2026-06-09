import Foundation
import Supabase

// Protocol so the view model is testable without the network.
// `Sendable` so a conformer can be held by the @MainActor view model and the
// async signIn call can cross the actor boundary under Swift 6 strict concurrency.
protocol AuthProviding: Sendable {
    func restoreSession() async throws -> Bool
    func signIn(email: String, password: String) async throws
    func currentUserEmail() async throws -> String?
    func signOut() async throws
}

struct SupabaseAuthService: AuthProviding {
    let client: SupabaseClient
    init(client: SupabaseClient = SupabaseClientProvider.shared) { self.client = client }

    func restoreSession() async throws -> Bool {
        _ = try await client.auth.session
        return true
    }

    func signIn(email: String, password: String) async throws {
        _ = try await client.auth.signIn(email: email, password: password)
    }

    func currentUserEmail() async throws -> String? {
        if let user = client.auth.currentUser {
            return user.email
        }
        let session = try await client.auth.session
        return session.user.email
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }
}
