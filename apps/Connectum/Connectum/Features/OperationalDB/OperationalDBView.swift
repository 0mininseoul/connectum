import SwiftUI

struct OperationalDBView: View {
    @State private var vm = OperationalDBViewModel()
    @State private var selectedUser: CrmUser?

    var body: some View {
        @Bindable var vm = vm
        return NavigationSplitView {
            List(vm.services, selection: Binding(
                get: { vm.selectedServiceId },
                set: { if let id = $0 { Task { await vm.selectService(id); selectedUser = nil } } })
            ) { svc in
                Text(svc.name).font(Typography.body).foregroundStyle(Palette.ink).tag(svc.id)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            .scrollContentBackground(.hidden)
            .background(Palette.surface)
        } content: {
            VStack(spacing: 0) {
                VStack(spacing: Spacing.xs) {
                    HStack(spacing: Spacing.sm) {
                        Picker("", selection: $vm.config.contactFilter) {
                            Text("전체").tag("all"); Text("컨택").tag("contacted"); Text("미컨택").tag("not_contacted")
                        }.labelsHidden().frame(width: 110)
                        Picker("", selection: $vm.config.sortKey) {
                            Text("가입일").tag("created_at"); Text("이메일").tag("email"); Text("컨택").tag("contact_status")
                        }.labelsHidden().frame(width: 100)
                        Toggle("프로필", isOn: $vm.config.profiledOnly).toggleStyle(.checkbox).font(Typography.caption)
                        Spacer()
                    }
                    HStack(spacing: Spacing.sm) {
                        if !vm.savedViews.isEmpty {
                            Menu("뷰") { ForEach(vm.savedViews) { v in Button(v.name) { vm.applyView(v) } } }.frame(width: 70)
                        }
                        Button("뷰 저장") { Task { await vm.saveView(name: "뷰 \(vm.savedViews.count + 1)") } }
                            .font(Typography.caption)
                        Spacer()
                    }
                }
                .padding(.horizontal, Spacing.sm).padding(.top, Spacing.sm)
                TextField("이메일/ID 검색", text: $vm.search)
                    .textFieldStyle(.plain).padding(Spacing.sm)
                    .background(Palette.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                    .padding(Spacing.sm)
                List(vm.filteredUsers, selection: $selectedUser) { u in
                    HStack(spacing: Spacing.sm) {
                        Circle().fill(u.contactStatus == "contacted" ? Palette.accentGreen : Palette.ash)
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(u.email ?? u.sourceUserId).font(Typography.body).foregroundStyle(Palette.ink)
                            if let p = u.amplitudeProfile, let os = p.os {
                                Text("\(os) · \(p.country ?? "")").font(Typography.caption).foregroundStyle(Palette.muted)
                            }
                        }
                        Spacer()
                    }.tag(u)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationSplitViewColumnWidth(min: 280, ideal: 340)
            .background(Palette.canvas)
            .overlay { if vm.isLoading { ProgressView() } }
        } detail: {
            if let u = selectedUser { UserDetailView(user: u) }
            else { Text("유저를 선택하세요").font(Typography.body).foregroundStyle(Palette.muted) }
        }
        .task { await vm.loadServices() }
    }
}
