import SwiftUI

// Operational DB: a Notion/Sheets-style multi-column table of users for the
// selected service. Clicking a row opens that user's page as a sheet.
struct OperationalDBView: View {
    let serviceId: String?
    @State private var vm = OperationalDBViewModel()
    @State private var selection: CrmUser.ID?
    @State private var openUser: CrmUser?

    var body: some View {
        @Bindable var vm = vm
        VStack(spacing: 0) {
            // Controls
            HStack(spacing: Spacing.sm) {
                TextField("이메일/ID 검색", text: $vm.search)
                    .textFieldStyle(.plain).font(Typography.body).foregroundStyle(Palette.ink)
                    .padding(.horizontal, Spacing.sm).frame(height: 28)
                    .background(Palette.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                    .overlay(RoundedRectangle(cornerRadius: Radius.button).stroke(Palette.hairline))
                    .frame(maxWidth: 260)
                Picker("", selection: $vm.config.contactFilter) {
                    Text("전체").tag("all"); Text("컨택").tag("contacted"); Text("미컨택").tag("not_contacted")
                }.labelsHidden().frame(width: 110)
                Picker("", selection: $vm.config.sortKey) {
                    Text("가입일").tag("created_at"); Text("이메일").tag("email"); Text("컨택").tag("contact_status")
                }.labelsHidden().frame(width: 100)
                Toggle("프로필", isOn: $vm.config.profiledOnly).font(Typography.caption)
                Spacer()
                if !vm.savedViews.isEmpty {
                    Menu("뷰") { ForEach(vm.savedViews) { v in Button(v.name) { vm.applyView(v) } } }.frame(width: 60)
                }
                Button("뷰 저장") { Task { await vm.saveView(name: "뷰 \(vm.savedViews.count + 1)") } }.font(Typography.caption)
                Text("\(vm.filteredUsers.count)명").font(Typography.caption).foregroundStyle(Palette.muted)
            }
            .padding(Spacing.sm)
            Divider().overlay(Palette.hairline)

            // Table
            if vm.filteredUsers.isEmpty {
                VStack {
                    Text(vm.isLoading ? "불러오는 중…" : "유저가 없습니다")
                        .font(Typography.body).foregroundStyle(Palette.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(vm.filteredUsers, selection: $selection) {
                    TableColumn("이메일") { u in
                        HStack(spacing: Spacing.sm) {
                            Circle().fill(u.contactStatus == "contacted" ? Palette.accentGreen : Palette.ash)
                                .frame(width: 7, height: 7)
                            Text(u.email ?? u.sourceUserId).foregroundStyle(Palette.ink)
                        }
                    }
                    TableColumn("컨택") { u in
                        Text(u.contactStatus == "contacted" ? "완료" : "—")
                            .foregroundStyle(u.contactStatus == "contacted" ? Palette.accentGreen : Palette.muted)
                    }.width(56)
                    TableColumn("OS") { u in Text(u.amplitudeProfile?.os ?? "—").foregroundStyle(Palette.muted) }.width(120)
                    TableColumn("지역") { u in Text(u.amplitudeProfile?.country ?? "—").foregroundStyle(Palette.muted) }.width(130)
                    TableColumn("가입일") { u in Text(String((u.createdAt ?? "").prefix(10))).foregroundStyle(Palette.muted) }.width(100)
                    TableColumn("AI 총평") { u in
                        Text((u.aiSummary ?? "—").replacingOccurrences(of: "\n", with: " "))
                            .lineLimit(1).foregroundStyle(Palette.muted)
                    }
                }
                .font(Typography.body)
                .onChange(of: selection) { _, id in
                    if let id, let u = vm.filteredUsers.first(where: { $0.id == id }) {
                        openUser = u
                        selection = nil
                    }
                }
            }
        }
        .background(Palette.canvas)
        .sheet(item: $openUser) { UserDetailSheet(user: $0) }
        .task(id: serviceId) { if let serviceId { await vm.load(serviceId: serviceId) } }
    }
}

// Wraps the user detail page in a sheet with a close affordance (Esc / ✕).
struct UserDetailSheet: View {
    let user: CrmUser
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.muted)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(Spacing.sm)
            UserDetailView(user: user)
        }
        .frame(width: 780, height: 760)
        .background(Palette.canvas)
    }
}
