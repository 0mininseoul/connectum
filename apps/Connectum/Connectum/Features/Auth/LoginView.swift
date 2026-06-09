import SwiftUI

struct LoginView: View {
    @Bindable var vm: AuthViewModel
    private let formMaxWidth: CGFloat = 360

    var body: some View {
        GeometryReader { proxy in
            let sidePadding = min(Spacing.xxl, max(Spacing.lg, proxy.size.width * 0.08))
            let formWidth = min(formMaxWidth, max(260, proxy.size.width - sidePadding * 2))

            ScrollView {
                VStack(spacing: Spacing.lg) {
                    Image("ConnectumLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 132, height: 132)
                        .accessibilityLabel("Connectum")

                    Text("Connectum").font(Typography.cardTitle).foregroundStyle(Palette.ink)
                    Text("auth.login.title").font(Typography.caption).foregroundStyle(Palette.muted)

                    VStack(spacing: Spacing.sm) {
                        TextField("auth.login.email", text: $vm.email)
                            .textFieldStyle(.plain)
                            .padding(Spacing.md)
                            .background(Palette.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                            .overlay(RoundedRectangle(cornerRadius: Radius.button).stroke(Palette.hairline))
                        SecureField("auth.login.password", text: $vm.password)
                            .textFieldStyle(.plain)
                            .padding(Spacing.md)
                            .background(Palette.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                            .overlay(RoundedRectangle(cornerRadius: Radius.button).stroke(Palette.hairline))
                    }
                    .frame(width: formWidth)
                    .onSubmit { Task { await vm.signIn() } }

                    if let err = vm.errorMessage {
                        Text(err).font(Typography.caption).foregroundStyle(Palette.accentRed)
                    }

                    Button { Task { await vm.signIn() } } label: {
                        Text("auth.login.submit")
                            .font(Typography.body)
                            .foregroundStyle(Palette.ctaText)
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .background(Palette.ctaFill)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(vm.isLoading)
                    .frame(width: formWidth)
                }
                .padding(.horizontal, sidePadding)
                .padding(.vertical, Spacing.xxl)
                .frame(minHeight: proxy.size.height)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Palette.canvas)
        .foregroundStyle(Palette.body)
    }
}
