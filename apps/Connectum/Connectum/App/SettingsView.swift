import SwiftUI
import AppKit

// Connectum settings (Cmd+,). Keep app-internal backend configuration out of
// the user-facing preferences surface.
struct SettingsView: View {
    @State private var authVM = AuthViewModel()
    @State private var updater = UpdateChecker()
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

            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("버전").font(Typography.caption).foregroundStyle(Palette.muted)
                        Text("Connectum \(updater.currentVersion)")
                            .font(Typography.body).foregroundStyle(Palette.body)
                    }
                    Spacer()
                    Button { Task { await updater.check() } } label: {
                        Label("업데이트 확인", systemImage: "arrow.triangle.2.circlepath")
                            .font(Typography.caption).foregroundStyle(Palette.accentBlue)
                    }
                    .buttonStyle(.plain)
                    .disabled(updater.state == .checking)
                }
                updateStatusRow
            }
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surfaceCard).clipShape(RoundedRectangle(cornerRadius: Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Palette.hairline))

            Spacer()
        }
        .padding(Spacing.xl)
        .frame(width: 520, height: 420)
        .background(Palette.canvas)
        .onAppear {
            Task { await authVM.loadCurrentUserEmail() }
        }
    }

    @ViewBuilder private var updateStatusRow: some View {
        switch updater.state {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: Spacing.xs) {
                ProgressView().controlSize(.small)
                Text("확인 중…").font(Typography.caption).foregroundStyle(Palette.muted)
            }
        case .upToDate:
            Label("최신 버전입니다", systemImage: "checkmark.circle")
                .font(Typography.caption).foregroundStyle(Palette.accentGreen)
        case .available(let version, let url, let notes):
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.sm) {
                    Text("새 버전 \(version) 사용 가능")
                        .font(Typography.caption).foregroundStyle(Palette.accentBlue)
                    Button {
                        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
                    } label: {
                        Label("다운로드", systemImage: "arrow.down.circle")
                            .font(Typography.caption).foregroundStyle(Palette.ctaText)
                            .padding(.horizontal, Spacing.sm).frame(height: 26)
                            .background(Palette.ctaFill)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.badge))
                    }
                    .buttonStyle(.plain)
                }
                if let notes, !notes.isEmpty {
                    Text(notes).font(.system(size: 11)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .failed(let message):
            Text("확인 실패: \(message)").font(Typography.caption).foregroundStyle(Palette.accentRed)
        }
    }
}
