import SwiftUI

struct RootView: View {
    @State private var vm = AuthViewModel()

    var body: some View {
        Group {
            if vm.isAuthenticated {
                AuthenticatedShell()
            } else {
                LoginView(vm: vm)
            }
        }
    }
}

struct AuthenticatedShell: View {
    var body: some View {
        OperationalDBView()
            .frame(minWidth: 1000, minHeight: 640)
    }
}
