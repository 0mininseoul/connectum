import SwiftUI

struct OperationalDBView: View {
    @State private var vm = OperationalDBViewModel()
    @State private var selectedUser: CrmUser?

    var body: some View {
        NavigationSplitView {
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
