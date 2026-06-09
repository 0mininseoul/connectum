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
    var currentUserEmail: String?

    private let auth: AuthProviding
    init(auth: AuthProviding = SupabaseAuthService()) { self.auth = auth }

    func restoreSession() async {
        guard !isAuthenticated else { return }
        do {
            isAuthenticated = try await auth.restoreSession()
            if isAuthenticated {
                currentUserEmail = try? await auth.currentUserEmail()
            }
        } catch {
            isAuthenticated = false
            currentUserEmail = nil
        }
    }

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
            currentUserEmail = try? await auth.currentUserEmail()
            if currentUserEmail == nil { currentUserEmail = email }
        } catch {
            errorMessage = String(localized: "auth.error.failed")
        }
    }

    func loadCurrentUserEmail() async {
        currentUserEmail = try? await auth.currentUserEmail()
    }

    func signOut() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            try await auth.signOut()
            email = ""
            password = ""
            currentUserEmail = nil
            isAuthenticated = false
            NotificationCenter.default.post(name: .connectumDidSignOut, object: nil)
        } catch {
            errorMessage = "로그아웃 실패: \(error)"
        }
    }
}

extension Notification.Name {
    static let connectumDidSignOut = Notification.Name("connectumDidSignOut")
    static let connectumFindRequested = Notification.Name("connectumFindRequested")
}
