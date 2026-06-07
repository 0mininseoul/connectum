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

// Phase 0 placeholder shell — Phase 1b replaces with the operational DB.
struct AuthenticatedShell: View {
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Connectum").font(Typography.cardTitle).foregroundStyle(Palette.ink)
                Spacer()
            }
            .padding(Spacing.lg)
            .frame(width: 240)
            .background(Palette.surface)
            Divider().overlay(Palette.hairline)
            VStack { Text("운영 DB (Phase 1)").font(Typography.body).foregroundStyle(Palette.muted) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.canvas)
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}
