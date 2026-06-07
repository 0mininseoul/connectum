import Foundation
import Observation

@MainActor
@Observable
final class AuthViewModel {
    var email = ""
    var password = ""
    var isAuthenticated = false
    var isLoading = false
    var errorMessage: String?

    private let auth: AuthProviding
    init(auth: AuthProviding = SupabaseAuthService()) { self.auth = auth }

    func signIn() async {
        errorMessage = nil
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = String(localized: "auth.error.empty")
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            try await auth.signIn(email: email, password: password)
            isAuthenticated = true
        } catch {
            errorMessage = String(localized: "auth.error.failed")
        }
    }
}
