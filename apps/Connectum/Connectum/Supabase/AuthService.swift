import Foundation
import Supabase

// Protocol so the view model is testable without the network.
// `Sendable` so a conformer can be held by the @MainActor view model and the
// async signIn call can cross the actor boundary under Swift 6 strict concurrency.
protocol AuthProviding: Sendable {
    func signIn(email: String, password: String) async throws
}

struct SupabaseAuthService: AuthProviding {
    let client: SupabaseClient
    init(client: SupabaseClient = SupabaseClientProvider.shared) { self.client = client }
    func signIn(email: String, password: String) async throws {
        _ = try await client.auth.signIn(email: email, password: password)
    }
}
