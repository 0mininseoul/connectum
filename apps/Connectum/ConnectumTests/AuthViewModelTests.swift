import XCTest
@testable import Connectum

final class AuthViewModelTests: XCTestCase {
    @MainActor
    func testSuccessfulSignInSetsAuthenticated() async {
        let vm = AuthViewModel(auth: FakeAuth(result: .success(())))
        vm.email = "a@b.com"; vm.password = "secret"
        await vm.signIn()
        XCTAssertTrue(vm.isAuthenticated)
        XCTAssertNil(vm.errorMessage)
    }

    @MainActor
    func testFailedSignInShowsError() async {
        let vm = AuthViewModel(auth: FakeAuth(result: .failure(AuthError.invalid)))
        vm.email = "a@b.com"; vm.password = "wrong"
        await vm.signIn()
        XCTAssertFalse(vm.isAuthenticated)
        XCTAssertNotNil(vm.errorMessage)
    }

    @MainActor
    func testEmptyFieldsBlockSignIn() async {
        let vm = AuthViewModel(auth: FakeAuth(result: .success(())))
        await vm.signIn()
        XCTAssertFalse(vm.isAuthenticated)
        XCTAssertNotNil(vm.errorMessage)
    }

    @MainActor
    func testRestoreSessionSetsAuthenticated() async {
        let vm = AuthViewModel(auth: FakeAuth(result: .success(()), restoreResult: .success(true)))
        await vm.restoreSession()
        XCTAssertTrue(vm.isAuthenticated)
        XCTAssertNil(vm.errorMessage)
    }

    @MainActor
    func testMissingSessionLeavesUnauthenticated() async {
        let vm = AuthViewModel(auth: FakeAuth(result: .success(()), restoreResult: .failure(.invalid)))
        await vm.restoreSession()
        XCTAssertFalse(vm.isAuthenticated)
        XCTAssertNil(vm.errorMessage)
    }

    @MainActor
    func testLoadCurrentUserEmailStoresEmail() async {
        let vm = AuthViewModel(auth: FakeAuth(result: .success(()), currentUserEmailResult: .success("user@example.com")))
        await vm.loadCurrentUserEmail()
        XCTAssertEqual(vm.currentUserEmail, "user@example.com")
    }

    @MainActor
    func testSignOutClearsAuthenticationAndCredentials() async {
        let vm = AuthViewModel(auth: FakeAuth(result: .success(()), currentUserEmailResult: .success("user@example.com")))
        vm.email = "user@example.com"
        vm.password = "secret"
        vm.isAuthenticated = true
        vm.currentUserEmail = "user@example.com"

        await vm.signOut()

        XCTAssertFalse(vm.isAuthenticated)
        XCTAssertNil(vm.currentUserEmail)
        XCTAssertEqual(vm.email, "")
        XCTAssertEqual(vm.password, "")
        XCTAssertNil(vm.errorMessage)
    }
}

enum AuthError: Error { case invalid }

// Sendable test double: `AuthProviding` is Sendable, so the fake stores a
// concrete Sendable error rather than a `Result<Void, any Error>`.
struct FakeAuth: AuthProviding {
    let result: Result<Void, AuthError>
    var restoreResult: Result<Bool, AuthError> = .success(false)
    var currentUserEmailResult: Result<String?, AuthError> = .success(nil)
    var signOutResult: Result<Void, AuthError> = .success(())

    func restoreSession() async throws -> Bool {
        switch restoreResult {
        case .success(let restored): return restored
        case .failure(let e): throw e
        }
    }

    func signIn(email: String, password: String) async throws {
        if case .failure(let e) = result { throw e }
    }

    func currentUserEmail() async throws -> String? {
        switch currentUserEmailResult {
        case .success(let email): return email
        case .failure(let e): throw e
        }
    }

    func signOut() async throws {
        if case .failure(let e) = signOutResult { throw e }
    }
}
