import SwiftUI

struct UserDetailView: View {
    @State private var vm: UserDetailViewModel
    init(user: CrmUser) { _vm = State(initialValue: UserDetailViewModel(user: user)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(vm.user.email ?? vm.user.sourceUserId).font(Typography.cardTitle).foregroundStyle(Palette.ink)
                    Text(vm.user.sourceUserId).font(Typography.caption).foregroundStyle(Palette.muted)
                }
                Button { Task { await vm.toggleContacted() } } label: {
                    Text(vm.contactStatus == "contacted" ? "✓ 컨택함" : "컨택 안함")
                        .font(Typography.body).foregroundStyle(vm.contactStatus == "contacted" ? Palette.ctaText : Palette.ink)
                        .padding(.horizontal, Spacing.lg).frame(height: 36)
                        .background(vm.contactStatus == "contacted" ? Palette.ctaFill : Palette.surfaceElevated)
                        .clipShape(Capsule())
                }.buttonStyle(.plain).disabled(vm.isBusy)

                card(title: "AI 총평") {
                    Text(vm.user.aiSummary ?? "아직 생성되지 않았습니다.")
                        .font(Typography.body).foregroundStyle(vm.user.aiSummary == nil ? Palette.muted : Palette.body)
                }
                card(title: "프로필") {
                    let p = vm.user.amplitudeProfile
                    profileRow("OS", p?.os); profileRow("디바이스", p?.deviceFamily ?? p?.deviceType)
                    profileRow("지역", [p?.city, p?.region, p?.country].compactMap { $0 }.joined(separator: ", "))
                    profileRow("최근 활동", p?.lastEventTime)
                }
                card(title: "최근 이벤트") {
                    if vm.events.isEmpty { Text("없음").font(Typography.caption).foregroundStyle(Palette.muted) }
                    else {
                        ForEach(vm.events) { e in
                            HStack {
                                Text(e.eventType).font(Typography.caption).foregroundStyle(Palette.body)
                                Spacer()
                                Text(e.eventTime).font(Typography.caption).foregroundStyle(Palette.muted)
                            }
                        }
                    }
                }
            }
            .padding(Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.canvas)
        .task { await vm.loadEvents() }
    }

    @ViewBuilder private func card<Content: View>(title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title).font(Typography.caption).foregroundStyle(Palette.muted)
            content()
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Palette.hairline))
    }

    @ViewBuilder private func profileRow(_ label: String, _ value: String?) -> some View {
        HStack {
            Text(label).font(Typography.caption).foregroundStyle(Palette.muted).frame(width: 80, alignment: .leading)
            Text(value?.isEmpty == false ? value! : "-").font(Typography.body).foregroundStyle(Palette.body)
            Spacer()
        }
    }
}
