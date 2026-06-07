import SwiftUI

struct UserDetailView: View {
    @State private var vm: UserDetailViewModel
    @State private var tab = 0
    init(user: CrmUser) { _vm = State(initialValue: UserDetailViewModel(user: user)) }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) { Text("개요").tag(0); Text("히스토리").tag(1) }
                .pickerStyle(.segmented).labelsHidden().padding(Spacing.sm).frame(maxWidth: 280)
            if tab == 0 { overview } else { HistoryTabView(crmUserId: vm.user.id) }
        }
        .background(Palette.canvas)
    }

    private var overview: some View {
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
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text(vm.aiSummary ?? "아직 생성되지 않았습니다.")
                            .font(Typography.body).foregroundStyle(vm.aiSummary == nil ? Palette.muted : Palette.body)
                        Button { Task { await vm.regenerate() } } label: {
                            Text(vm.isRegenerating ? "생성 중…" : "재생성")
                                .font(Typography.caption).foregroundStyle(Palette.ink)
                                .padding(.horizontal, Spacing.md).frame(height: 28)
                                .background(Palette.surfaceElevated).clipShape(Capsule())
                        }.buttonStyle(.plain).disabled(vm.isRegenerating)
                    }
                }
                card(title: "프로필") {
                    let p = vm.user.amplitudeProfile
                    profileRow("OS", p?.os); profileRow("디바이스", p?.deviceFamily ?? p?.deviceType)
                    profileRow("지역", [p?.city, p?.region, p?.country].compactMap { $0 }.joined(separator: ", "))
                    profileRow("최근 활동", p?.lastEventTime)
                }
                RecordsSection(vm: vm)
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

private struct RecordsSection: View {
    @Bindable var vm: UserDetailViewModel
    @State private var channel = "email"
    @State private var date = ""
    @State private var note = ""
    private let channels = ["email", "kakao", "sms", "interview", "memo"]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("기록 (이메일/카톡/문자/인터뷰/메모)").font(Typography.caption).foregroundStyle(Palette.muted)
            ForEach(vm.records) { r in
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Text(r.channel).font(Typography.caption).foregroundStyle(Palette.accentBlue).frame(width: 64, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.body).font(Typography.body).foregroundStyle(Palette.body)
                        Text(r.occurredAt ?? "").font(Typography.caption).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                }
            }
            if vm.records.isEmpty { Text("기록 없음").font(Typography.caption).foregroundStyle(Palette.muted) }
            Divider().overlay(Palette.hairline)
            HStack(spacing: Spacing.sm) {
                Picker("", selection: $channel) { ForEach(channels, id: \.self) { Text($0).tag($0) } }
                    .labelsHidden().frame(width: 110)
                TextField("날짜 (예: 2026-06-08)", text: $date).textFieldStyle(.plain)
                    .padding(Spacing.xs).background(Palette.surfaceElevated).clipShape(RoundedRectangle(cornerRadius: Radius.button)).frame(width: 160)
            }
            TextField("내용", text: $note, axis: .vertical).textFieldStyle(.plain).lineLimit(2...5)
                .padding(Spacing.sm).background(Palette.surfaceElevated).clipShape(RoundedRectangle(cornerRadius: Radius.button))
            Button {
                let c = channel; let d = date; let b = note
                Task { await vm.addRecord(channel: c, occurredAt: d, body: b); note = ""; date = "" }
            } label: {
                Text("기록 추가").font(Typography.caption).foregroundStyle(Palette.ctaText)
                    .padding(.horizontal, Spacing.md).frame(height: 28).background(Palette.ctaFill).clipShape(Capsule())
            }.buttonStyle(.plain).disabled(note.isEmpty)
        }
        .padding(Spacing.lg).frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceCard).clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Palette.hairline))
        .task { await vm.loadRecords() }
    }
}
