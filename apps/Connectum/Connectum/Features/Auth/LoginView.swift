import SwiftUI

struct LoginView: View {
    @Bindable var vm: AuthViewModel

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Text("Connectum").font(Typography.cardTitle).foregroundStyle(Palette.ink)
            Text("auth.login.title").font(Typography.caption).foregroundStyle(Palette.muted)

            VStack(spacing: Spacing.sm) {
                TextField("auth.login.email", text: $vm.email)
                    .textFieldStyle(.plain).padding(Spacing.md)
                    .background(Palette.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                    .overlay(RoundedRectangle(cornerRadius: Radius.button).stroke(Palette.hairline))
                SecureField("auth.login.password", text: $vm.password)
                    .textFieldStyle(.plain).padding(Spacing.md)
                    .background(Palette.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                    .overlay(RoundedRectangle(cornerRadius: Radius.button).stroke(Palette.hairline))
            }
            .frame(width: 320)

            if let err = vm.errorMessage {
                Text(err).font(Typography.caption).foregroundStyle(Palette.accentRed)
            }

            Button { Task { await vm.signIn() } } label: {
                Text("auth.login.submit").font(Typography.body)
                    .foregroundStyle(Palette.ctaText)
                    .frame(width: 320, height: 36)
                    .background(Palette.ctaFill)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(vm.isLoading)
        }
        .padding(Spacing.xxl)
        .frame(minWidth: 900, minHeight: 600)
        .background(Palette.canvas)
        .foregroundStyle(Palette.body)
    }
}
