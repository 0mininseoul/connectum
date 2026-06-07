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
        TabView {
            OperationalDBView().tabItem { Text("운영 DB") }
            DashboardView().tabItem { Text("대시보드") }
        }
        .frame(minWidth: 1000, minHeight: 640)
    }
}
