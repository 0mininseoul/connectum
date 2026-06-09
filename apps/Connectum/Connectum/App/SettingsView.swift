import SwiftUI

// Connectum settings (Cmd+,). Keep app-internal backend configuration out of
// the user-facing preferences surface.
struct SettingsView: View {
    @State private var authVM = AuthViewModel()
    @AppStorage(AppPreferenceKeys.userDetailOpenMode) private var userDetailOpenMode = UserDetailOpenMode.side.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            Text("설정").font(Typography.cardTitle).foregroundStyle(Palette.ink)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("로그인 정보").font(Typography.caption).foregroundStyle(Palette.muted)
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(Palette.muted)
                    Text(authVM.currentUserEmail ?? "로그인 정보를 불러오지 못했습니다")
                        .font(Typography.body)
                        .foregroundStyle(authVM.currentUserEmail == nil ? Palette.muted : Palette.body)
                        .lineLimit(1)
                        .textSelection(.enabled)
                    Spacer(minLength: Spacing.md)
                    Button(role: .destructive) {
                        Task { await authVM.signOut() }
                    } label: {
                        Label("로그아웃", systemImage: "rectangle.portrait.and.arrow.right")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.accentRed)
                    }
                    .buttonStyle(.plain)
                    .disabled(authVM.isLoading)
                }
                if let error = authVM.errorMessage {
                    Text(error)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.accentRed)
                }
            }
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surfaceCard).clipShape(RoundedRectangle(cornerRadius: Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Palette.hairline))

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("유저 페이지 열기 방식").font(Typography.caption).foregroundStyle(Palette.muted)
                Picker("열기 방식", selection: $userDetailOpenMode) {
                    ForEach(UserDetailOpenMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 260)
            }
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surfaceCard).clipShape(RoundedRectangle(cornerRadius: Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Palette.hairline))

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("정보").font(Typography.caption).foregroundStyle(Palette.muted)
                Text("Connectum \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                    .font(Typography.body).foregroundStyle(Palette.body)
            }
            Spacer()
        }
        .padding(Spacing.xl)
        .frame(width: 520, height: 420)
        .background(Palette.canvas)
        .onAppear {
            Task { await authVM.loadCurrentUserEmail() }
        }
    }
}
