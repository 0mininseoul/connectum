import SwiftUI
#if os(macOS)
import AppKit
#endif

// Operational DB: a Notion/Sheets-style table of users for the selected service.
// Columns can be dragged to reorder, shown/hidden, and resized (native table
// customization); filters + the column layout are saved per view. Row selection
// enables explicit user actions in the toolbar.
struct OperationalDBView: View {
    let serviceId: String?
    let refreshID: Int
    @State private var vm = OperationalDBViewModel()
    @State private var selection: CrmUser.ID?
    @State private var sheetUser: CrmUser?
    @State private var sideUser: CrmUser?
    @State private var showColumns = false
    @State private var showNewView = false
    @State private var newViewName = ""
    @State private var columns = TableColumnCustomization<CrmUser>()
    @State private var columnWidthCache: [String: CGFloat] = [:]
    @State private var sortOrder = [CrmUserSortComparator(columnID: "created_at", primaryColumnID: OperationalDBViewModel.emailCol, order: .reverse)]
    @State private var pendingExclusion: CrmUser?
    @State private var showSearch = false
    @State private var selectedSourceTableId: String?   // nil = the user table (crm_user)
    @FocusState private var tableFocused: Bool
    @FocusState private var searchFocused: Bool
    @AppStorage(AppPreferenceKeys.userDetailOpenMode) private var detailOpenModeRaw = UserDetailOpenMode.side.rawValue

    init(serviceId: String?, refreshID: Int = 0) {
        self.serviceId = serviceId
        self.refreshID = refreshID
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                sourceTabs(vm)
                if let related = vm.relatedTables.first(where: { $0.id == selectedSourceTableId }) {
                    MirroredTableView(table: related, refreshID: refreshID)
                } else {
                    viewTabs(vm)
                    Divider().overlay(Palette.hairline)
                    controls(vm)
                    Divider().overlay(Palette.hairline)
                    table(vm)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if detailOpenMode == .side, let sideUser {
                ResizeHandle(width: sideDetailWidthBinding)
                UserDetailView(
                    user: sideUser,
                    primaryTitle: vm.primaryText(sideUser),
                    primaryLabel: vm.columnLabel(OperationalDBViewModel.primaryCol),
                    onClose: {
                        self.sideUser = nil
                        tableFocused = true
                    }
                )
                .id(sideUser.id)
                .frame(width: sideDetailWidth, height: nil)
                .frame(minWidth: sideDetailMinWidth, maxHeight: .infinity)
            }
        }
        .background(Palette.canvas)
        .background(openSelectedShortcut)
        .sheet(item: $sheetUser) { user in
            UserDetailSheet(
                user: user,
                primaryTitle: vm.primaryText(user),
                primaryLabel: vm.columnLabel(OperationalDBViewModel.primaryCol)
            )
        }
        .alert("새 뷰 저장", isPresented: $showNewView) {
            TextField("뷰 이름", text: $newViewName)
            Button("저장") {
                let n = newViewName.trimmingCharacters(in: .whitespaces)
                Task { await vm.saveView(name: n.isEmpty ? "뷰 \(vm.savedViews.count + 1)" : n, customization: encodedColumns()) }
                newViewName = ""
            }
            Button("취소", role: .cancel) { newViewName = "" }
        } message: { Text("현재 필터와 컬럼 구성을 새 뷰로 저장합니다.") }
        .confirmationDialog("유저 제외", isPresented: Binding(
            get: { pendingExclusion != nil },
            set: { if !$0 { pendingExclusion = nil } }
        ), titleVisibility: .visible) {
            if let user = pendingExclusion {
                Button("이 유저 제외", role: .destructive) {
                    Task {
                        await vm.excludeUser(user)
                        if selection == user.id { selection = nil }
                        if sheetUser?.id == user.id { sheetUser = nil }
                        if sideUser?.id == user.id { sideUser = nil }
                        refreshColumnWidthCache()
                        pendingExclusion = nil
                    }
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            if let user = pendingExclusion {
                Text("\(vm.primaryText(user)) 유저를 운영 DB와 대시보드에서 제외합니다. 앞으로 이 서비스의 동기화에서도 유저로 다시 포함하지 않습니다.")
            }
        }
        .task(id: "\(serviceId ?? ""):\(refreshID)") {
            if let serviceId {
                selection = nil
                sheetUser = nil
                sideUser = nil
                vm.search = ""
                showSearch = false
                await Task.yield()
                if await vm.loadCached(serviceId: serviceId) {
                    loadPrimaryColumn()
                    loadColumns()
                    scheduleColumnWidthRefresh()
                    syncSortOrderFromConfig()
                }
                await vm.refresh(serviceId: serviceId)
                loadPrimaryColumn()
                loadColumns()
                scheduleColumnWidthRefresh()
                syncSortOrderFromConfig()
            }
        }
        .onChange(of: vm.activeViewId) { _, _ in
            loadColumns()
            scheduleColumnWidthRefresh()
            syncSortOrderFromConfig()
        }
        .onChange(of: vm.config.primaryColumn) { _, _ in
            loadColumns()
            persistPrimaryColumn()
            scheduleColumnWidthRefresh()
            syncSortOrderFromConfig()
        }
        .onChange(of: selection) { _, id in
            // Keep an open detail (side/popup) in sync with arrow-key navigation.
            if let id, let user = vm.filteredUsers.first(where: { $0.id == id }) {
                if sideUser != nil { sideUser = user }
                if sheetUser != nil { sheetUser = user }
            }
            // Re-assert table focus AFTER the detail panel rebuilds (the .id swap
            // recreates the detail and steals first-responder), so repeated
            // arrow-key navigation keeps reaching the table.
            if id != nil, !searchFocused {
                tableFocused = true
                Task { @MainActor in
                    await Task.yield()
                    if !searchFocused { tableFocused = true }
                }
            }
        }
        .onChange(of: detailOpenModeRaw) { _, _ in
            if detailOpenMode == .popup { sideUser = nil }
            if detailOpenMode == .side { sheetUser = nil }
        }
        .onChange(of: sortOrder) { _, newValue in applySortOrder(newValue) }
        .onChange(of: columns) { _, _ in
            persistColumns()
            scheduleColumnWidthRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .connectumFindRequested)) { _ in
            guard serviceId != nil else { return }
            showSearchField()
        }
    }

    // Source-table switcher: the user table (rich crm_user UI) plus any extra
    // imported tables. Only shown when there's more than one source to choose.
    @ViewBuilder private func sourceTabs(_ vm: OperationalDBViewModel) -> some View {
        if !vm.relatedTables.isEmpty {
            HStack(spacing: Spacing.xs) {
                sourceTab(icon: "person.2.fill", title: "유저", active: selectedSourceTableId == nil) {
                    selectedSourceTableId = nil
                }
                ForEach(vm.relatedTables) { t in
                    sourceTab(icon: "tablecells", title: t.displayName, active: selectedSourceTableId == t.id) {
                        selectedSourceTableId = t.id
                    }
                }
                Spacer()
            }
            .padding(.horizontal, Spacing.sm).padding(.vertical, Spacing.xs)
            Divider().overlay(Palette.hairline)
        }
    }

    private func sourceTab(icon: String, title: String, active: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                Text(title).font(.system(size: 12, weight: active ? .semibold : .medium)).lineLimit(1)
            }
            .foregroundStyle(active ? Palette.ink : Palette.muted)
            .padding(.horizontal, Spacing.sm).frame(height: 26)
            .background(active ? Palette.surfaceElevated : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Radius.row))
            .overlay {
                if active { RoundedRectangle(cornerRadius: Radius.row).stroke(Palette.hairline) }
            }
        }.buttonStyle(.plain)
    }

    // Notion-style view tabs across the top.
    @ViewBuilder private func viewTabs(_ vm: OperationalDBViewModel) -> some View {
        HStack(spacing: Spacing.xs) {
            viewTab("기본", active: vm.activeViewId == nil) {
                vm.resetToDefault()
                loadPrimaryColumn()
                loadColumns()
            }
            ForEach(vm.savedViews) { v in
                viewTab(v.name, active: vm.activeViewId == v.id) { vm.applyView(v) }
            }
            Button { showNewView = true } label: {
                Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.muted)
                    .frame(width: 24, height: 24)
            }.buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, Spacing.sm).padding(.vertical, Spacing.xs)
    }

    private func viewTab(_ title: String, active: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? Palette.ink : Palette.muted)
                .padding(.horizontal, Spacing.sm).frame(height: 24)
                .background(active ? Palette.surfaceElevated : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: Radius.row))
        }.buttonStyle(.plain)
    }

    @ViewBuilder private func controls(_ vm: OperationalDBViewModel) -> some View {
        @Bindable var vm = vm
        HStack(spacing: Spacing.sm) {
            if showSearch || !vm.search.isEmpty {
                searchField(vm)
            }
            Picker("", selection: $vm.config.contactFilter) {
                Text("전체").tag("all"); Text("컨택").tag("contacted"); Text("미컨택").tag("not_contacted")
            }.labelsHidden().frame(width: 104)
            Toggle("프로필", isOn: $vm.config.profiledOnly).font(Typography.caption)
            Spacer()
            Button { showColumns = true } label: {
                Label("컬럼", systemImage: "slider.horizontal.3").font(Typography.caption).foregroundStyle(Palette.body)
            }.buttonStyle(.plain)
            .popover(isPresented: $showColumns, arrowEdge: .bottom) {
                ColumnEditor(vm: vm, customization: $columns, reset: resetColumns)
            }
            if vm.isRefreshing {
                Label("동기화 중", systemImage: "arrow.triangle.2.circlepath")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.muted)
            }
            Text("\(vm.filteredUserCount)명").font(Typography.caption).foregroundStyle(Palette.muted)
        }
        .padding(Spacing.sm)
        if let error = vm.errorMessage {
            Text(error)
                .font(Typography.caption)
                .foregroundStyle(Palette.accentRed)
                .padding(.horizontal, Spacing.sm)
                .padding(.bottom, Spacing.xs)
        }
    }

    private func searchField(_ vm: OperationalDBViewModel) -> some View {
        @Bindable var vm = vm
        return HStack(spacing: Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.muted)
            TextField("모든 셀 검색", text: $vm.search)
                .textFieldStyle(.plain)
                .font(Typography.body)
                .foregroundStyle(Palette.ink)
                .focused($searchFocused)
            Button(action: hideSearch) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.ash)
            }
            .buttonStyle(.plain)
            .help("검색 닫기")
        }
        .padding(.horizontal, Spacing.sm)
        .frame(width: 260, height: 28)
        .background(Palette.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: Radius.button))
        .overlay(RoundedRectangle(cornerRadius: Radius.button).stroke(Palette.hairline))
        .onExitCommand { hideSearch() }
    }

    @ViewBuilder private func table(_ vm: OperationalDBViewModel) -> some View {
        let rows = vm.filteredUsers
        if rows.isEmpty {
            VStack {
                Text(vm.isLoading ? "불러오는 중…" : "유저가 없습니다")
                    .font(Typography.body).foregroundStyle(Palette.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(rows, selection: $selection, sortOrder: $sortOrder, columnCustomization: $columns) {
                TableColumn(
                    columnHeader(OperationalDBViewModel.primaryCol),
                    sortUsing: CrmUserSortComparator(columnID: OperationalDBViewModel.primaryCol, primaryColumnID: vm.primaryColumn)
                ) { u in
                    interactiveCell(u) {
                        HStack(spacing: Spacing.sm) {
                            Circle().fill(u.contactStatus == "contacted" ? Palette.accentGreen : Palette.ash)
                                .frame(width: 7, height: 7)
                            Text(vm.primaryText(u)).foregroundStyle(Palette.ink)
                        }
                    }
                }
                .width(
                    min: columnMinWidth(OperationalDBViewModel.primaryCol),
                    ideal: columnIdealWidth(OperationalDBViewModel.primaryCol),
                    max: columnMaxWidth(OperationalDBViewModel.primaryCol)
                )
                .customizationID(OperationalDBViewModel.primaryCol)
                .disabledCustomizationBehavior(.visibility)   // 메인 컬럼은 항상 표시
                TableColumnForEach(renderedColumnIDs, id: \.self) { id in
                    TableColumn(
                        columnHeader(id),
                        sortUsing: CrmUserSortComparator(columnID: id, primaryColumnID: vm.primaryColumn)
                    ) { u in
                        interactiveCell(u) {
                            cell(u, id)
                        }
                    }
                        .width(min: columnMinWidth(id), ideal: columnIdealWidth(id), max: columnMaxWidth(id))
                        .customizationID(id)
                }
            }
            .font(Typography.body)
            .scrollContentBackground(.hidden)
            .background(Palette.canvas)
            .contextMenu {
                if let user = selectedUser(vm) {
                    userContextMenu(user)
                }
            }
            .focusable()
            .focused($tableFocused)
            .onMoveCommand(perform: moveSelection)
            .onKeyPress(.return) {
                openSelectedUser() ? .handled : .ignored
            }
        }
    }

    private func selectedUser(_ vm: OperationalDBViewModel) -> CrmUser? {
        guard let selection else { return nil }
        return vm.filteredUsers.first { $0.id == selection }
    }

    private func columnHeader(_ id: String) -> String {
        let label = vm.columnLabel(id)
        let sortID = id == OperationalDBViewModel.primaryCol ? vm.primaryColumn : id
        guard vm.sortColumn == sortID else { return label }
        return "\(label) \(vm.config.sortAsc ? "↑" : "↓")"
    }

    private func interactiveCell<Content: View>(_ user: CrmUser, @ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded { selectUser(user) })
            .highPriorityGesture(TapGesture(count: 2).onEnded { openUser(user) })
            .contextMenu { userContextMenu(user) }
    }

    @ViewBuilder private func userContextMenu(_ user: CrmUser) -> some View {
        Button {
            openUser(user)
        } label: {
            Label("유저 페이지 열기", systemImage: "person.crop.rectangle")
        }
        Button {
            openUser(user, as: .side)
        } label: {
            Label("사이드 보기로 열기", systemImage: "sidebar.right")
        }
        Button {
            openUser(user, as: .popup)
        } label: {
            Label("팝업으로 열기", systemImage: "macwindow")
        }
        Divider()
        Button(role: .destructive) {
            selectUser(user)
            pendingExclusion = user
        } label: {
            Label("이 유저 제외", systemImage: "eye.slash")
        }
    }

    @discardableResult
    private func openSelectedUser() -> Bool {
        guard let user = selectedUser(vm) else { return false }
        openUser(user)
        return true
    }

    private func openUser(_ user: CrmUser, as forcedMode: UserDetailOpenMode? = nil) {
        let mode = forcedMode ?? detailOpenMode
        selectUser(user)
        switch mode {
        case .side:
            sheetUser = nil
            sideUser = user
            searchFocused = false
            tableFocused = false
        case .popup:
            sideUser = nil
            sheetUser = user
            searchFocused = false
            tableFocused = false
        }
    }

    private func selectUser(_ user: CrmUser) {
        selection = user.id
        tableFocused = true
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard let selection,
              let currentIndex = vm.filteredUsers.firstIndex(where: { $0.id == selection })
        else { return }

        let nextIndex: Int
        switch direction {
        case .up:
            nextIndex = max(currentIndex - 1, vm.filteredUsers.startIndex)
        case .down:
            nextIndex = min(currentIndex + 1, vm.filteredUsers.index(before: vm.filteredUsers.endIndex))
        default:
            return
        }

        self.selection = vm.filteredUsers[nextIndex].id
    }

    private var detailOpenMode: UserDetailOpenMode {
        UserDetailOpenMode(rawValue: detailOpenModeRaw) ?? .side
    }

    @AppStorage("operationalDBSideDetailWidth") private var sideDetailWidthValue = 440.0
    private let sideDetailMinWidth: CGFloat = 360
    private let sideDetailMaxWidth: CGFloat = 760
    private var sideDetailWidth: CGFloat {
        min(max(CGFloat(sideDetailWidthValue), sideDetailMinWidth), sideDetailMaxWidth)
    }
    private var sideDetailWidthBinding: Binding<CGFloat> {
        Binding(
            get: { sideDetailWidth },
            set: { sideDetailWidthValue = Double(min(max($0, sideDetailMinWidth), sideDetailMaxWidth)) }
        )
    }

    private func syncSortOrderFromConfig() {
        sortOrder = [
            CrmUserSortComparator(
                columnID: vm.sortColumn,
                primaryColumnID: vm.primaryColumn,
                order: vm.config.sortAsc ? .forward : .reverse
            )
        ]
    }

    private func applySortOrder(_ order: [CrmUserSortComparator]) {
        guard let first = order.first else { return }
        let columnID = first.columnID == OperationalDBViewModel.primaryCol ? vm.primaryColumn : first.columnID
        if vm.config.sortKey != columnID {
            vm.config.sortKey = columnID
        }
        let asc = first.order == .forward
        if vm.config.sortAsc != asc {
            vm.config.sortAsc = asc
        }
    }

    private var openSelectedShortcut: some View {
        Button("선택한 유저 열기") { _ = openSelectedUser() }
            .keyboardShortcut(.return, modifiers: [])
            .disabled(!tableFocused || searchFocused || selectedUser(vm) == nil)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }

    private func showSearchField() {
        showSearch = true
        Task { @MainActor in
            await Task.yield()
            searchFocused = true
        }
    }

    private func hideSearch() {
        vm.search = ""
        showSearch = false
        searchFocused = false
        tableFocused = true
    }

    @ViewBuilder private func cell(_ u: CrmUser, _ id: String) -> some View {
        switch id {
        case OperationalDBViewModel.emailCol:
            Text(u.email ?? "—").lineLimit(1).foregroundStyle(Palette.muted)
        case OperationalDBViewModel.sourceUserIdCol:
            Text(u.sourceUserId).lineLimit(1).foregroundStyle(Palette.muted)
        case OperationalDBViewModel.contactCol:
            Text(u.contactStatus == "contacted" ? "완료" : "—")
                .foregroundStyle(u.contactStatus == "contacted" ? Palette.accentGreen : Palette.muted)
        case OperationalDBViewModel.aiCol:
            Text((u.aiSummary ?? "—").replacingOccurrences(of: "\n", with: " "))
                .lineLimit(1).foregroundStyle(Palette.muted)
        default:
            Text(u.profileValue(id)).lineLimit(1).foregroundStyle(Palette.muted)
        }
    }

    // MARK: Column width + customization persistence (per view; 기본 → UserDefaults)
    private func columnMinWidth(_ id: String) -> CGFloat {
        max(44, min(columnIdealWidth(id), 88))
    }
    private func columnIdealWidth(_ id: String) -> CGFloat {
        columnWidthCache[id] ?? 120
    }
    private func columnMaxWidth(_ id: String) -> CGFloat {
        let ideal = columnIdealWidth(id)
        return max(ideal + 240, ideal * 1.5)
    }
    private func refreshColumnWidthCache() {
        var next: [String: CGFloat] = [:]
        let ids = [OperationalDBViewModel.primaryCol] + renderedColumnIDs
        for id in ids {
            next[id] = fittedColumnWidth(id)
        }
        columnWidthCache = next
    }

    private func scheduleColumnWidthRefresh() {
        Task { @MainActor in
            await Task.yield()
            refreshColumnWidthCache()
        }
    }

    private var renderedColumnIDs: [String] {
        let defaults = Set(vm.defaultVisible)
        return vm.availableColumns.filter { id in
            let visibility = columns[visibility: id]
            if visibility == .hidden { return false }
            if visibility == .visible { return true }
            return defaults.contains(id)
        }
    }
    private func fittedColumnWidth(_ id: String) -> CGFloat {
        let valueWidth = vm.users.reduce(CGFloat.zero) { width, user in
            max(width, measuredTextWidth(columnDisplayValue(user, id)))
        }
        let headerWidth = measuredTextWidth(vm.columnLabel(id))
        let indicatorWidth: CGFloat = id == OperationalDBViewModel.primaryCol ? 15 : 0
        return ceil(max(valueWidth, headerWidth) + indicatorWidth + 28)
    }
    private func columnDisplayValue(_ user: CrmUser, _ id: String) -> String {
        switch id {
        case OperationalDBViewModel.primaryCol:
            return vm.primaryText(user)
        case OperationalDBViewModel.emailCol:
            return user.email ?? "—"
        case OperationalDBViewModel.sourceUserIdCol:
            return user.sourceUserId
        case OperationalDBViewModel.contactCol:
            return user.contactStatus == "contacted" ? "완료" : "—"
        case OperationalDBViewModel.aiCol:
            return (user.aiSummary ?? "—").replacingOccurrences(of: "\n", with: " ")
        default:
            return user.profileValue(id)
        }
    }
    private func measuredTextWidth(_ text: String) -> CGFloat {
        #if os(macOS)
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14)]
        return ceil((text as NSString).size(withAttributes: attributes).width)
        #else
        return CGFloat(text.count) * 7
        #endif
    }
    private func encodedColumns() -> String {
        guard let d = try? JSONEncoder().encode(columns) else { return "" }
        return String(data: d, encoding: .utf8) ?? ""
    }
    private func defaultColumns() -> TableColumnCustomization<CrmUser> {
        var c = TableColumnCustomization<CrmUser>()
        let visible = Set(vm.defaultVisible)
        for id in vm.availableColumns { c[visibility: id] = visible.contains(id) ? .visible : .hidden }
        return c
    }
    private func decodeColumns(_ s: String) -> TableColumnCustomization<CrmUser>? {
        guard let d = s.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(TableColumnCustomization<CrmUser>.self, from: d)
    }
    private func columnsDefaultsKey(_ serviceId: String) -> String { "colcustom.v4.\(serviceId)" }
    private func legacyColumnsDefaultsKey(_ serviceId: String) -> String { "colcustom.\(serviceId)" }
    private func legacyColumnsDefaultsKeyV2(_ serviceId: String) -> String { "colcustom.v2.\(serviceId)" }
    private func legacyColumnsDefaultsKeyV3(_ serviceId: String) -> String { "colcustom.v3.\(serviceId)" }
    private func primaryDefaultsKey(_ serviceId: String) -> String { "primarycol.v1.\(serviceId)" }
    private func loadPrimaryColumn() {
        guard vm.activeViewId == nil, let sid = serviceId else { return }
        let stored = UserDefaults.standard.string(forKey: primaryDefaultsKey(sid)) ?? OperationalDBViewModel.emailCol
        vm.config.primaryColumn = vm.primaryColumnCandidates.contains(stored) ? stored : OperationalDBViewModel.emailCol
    }
    private func loadColumns() {
        if let json = vm.customizationJSON(for: vm.activeViewId), let c = decodeColumns(json) {
            columns = c
        } else if vm.activeViewId == nil, let sid = serviceId,
                  let d = UserDefaults.standard.string(forKey: columnsDefaultsKey(sid)), let c = decodeColumns(d) {
            columns = c
        } else {
            columns = defaultColumns()
        }
    }
    private func resetColumns() {
        columns = defaultColumns()
        vm.config.primaryColumn = OperationalDBViewModel.emailCol
        guard let sid = serviceId else { return }
        UserDefaults.standard.removeObject(forKey: columnsDefaultsKey(sid))
        UserDefaults.standard.removeObject(forKey: legacyColumnsDefaultsKeyV3(sid))
        UserDefaults.standard.removeObject(forKey: legacyColumnsDefaultsKeyV2(sid))
        UserDefaults.standard.removeObject(forKey: legacyColumnsDefaultsKey(sid))
        UserDefaults.standard.removeObject(forKey: primaryDefaultsKey(sid))
    }
    private func persistColumns() {
        guard vm.activeViewId == nil, let sid = serviceId else { return }
        UserDefaults.standard.set(encodedColumns(), forKey: columnsDefaultsKey(sid))
    }
    private func persistPrimaryColumn() {
        guard vm.activeViewId == nil, let sid = serviceId else { return }
        UserDefaults.standard.set(vm.primaryColumn, forKey: primaryDefaultsKey(sid))
    }
}

// Discoverable show/hide for columns (drag the headers to reorder). Drives the
// same native TableColumnCustomization the table binds to.
struct ColumnEditor: View {
    @Bindable var vm: OperationalDBViewModel
    @Binding var customization: TableColumnCustomization<CrmUser>
    let reset: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    Text("표시 컬럼").font(Typography.body).foregroundStyle(Palette.ink)
                    Spacer()
                    Button(action: reset) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.muted)
                    }
                    .buttonStyle(.plain)
                    .help("기본 컬럼으로 복원")
                }
                Text("메인 컬럼")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.muted)
                    .padding(.top, Spacing.xs)
                Picker("", selection: $vm.config.primaryColumn) {
                    ForEach(vm.primaryColumnCandidates, id: \.self) { id in
                        Text(vm.columnLabel(id)).tag(id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)

                Divider().overlay(Palette.hairline)
                    .padding(.vertical, Spacing.xs)
                Text("표시 컬럼").font(Typography.caption).foregroundStyle(Palette.muted)
                ForEach(vm.availableColumns, id: \.self) { id in
                    let visible = customization[visibility: id] != .hidden
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: visible ? "checkmark.square.fill" : "square")
                            .foregroundStyle(visible ? Palette.accentBlue : Palette.muted)
                        Text(vm.columnLabel(id)).font(Typography.caption)
                            .foregroundStyle(visible ? Palette.body : Palette.muted).lineLimit(1)
                        Spacer(minLength: Spacing.sm)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { customization[visibility: id] = visible ? .hidden : .visible }
                }
            }
            .padding(Spacing.md)
        }
        .frame(width: 260, height: min(480, CGFloat(vm.availableColumns.count) * 28 + 150))
    }
}

private struct ResizeHandle: View {
    @Binding var width: CGFloat
    @State private var dragStartWidth: CGFloat?
    @State private var isHovering = false
    @State private var isDragging = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill((isHovering || isDragging) ? Palette.surfaceElevated : Color.clear)
            Rectangle()
                .fill((isHovering || isDragging) ? Palette.accentBlue.opacity(0.75) : Palette.hairline)
                .frame(width: 1)
            VStack(spacing: 3) {
                gripDot
                gripDot
                gripDot
            }
            .opacity(isHovering || isDragging ? 1 : 0.56)
        }
        .frame(width: 14)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
            #if os(macOS)
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
            #endif
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    isDragging = true
                    if dragStartWidth == nil {
                        dragStartWidth = width
                    }
                    width = (dragStartWidth ?? width) - value.translation.width
                }
                .onEnded { _ in
                    dragStartWidth = nil
                    isDragging = false
                }
        )
        .help("드래그해서 사이드 보기 너비 조절")
        .accessibilityLabel("사이드 보기 너비 조절")
    }

    private var gripDot: some View {
        Capsule()
            .fill((isHovering || isDragging) ? Palette.accentBlue : Palette.ash)
            .frame(width: 3, height: 3)
    }
}

// Wraps the user detail page in a sheet with a close affordance (Esc / ✕).
struct UserDetailSheet: View {
    let user: CrmUser
    let primaryTitle: String?
    let primaryLabel: String?
    @Environment(\.dismiss) private var dismiss

    init(user: CrmUser, primaryTitle: String? = nil, primaryLabel: String? = nil) {
        self.user = user
        self.primaryTitle = primaryTitle
        self.primaryLabel = primaryLabel
    }

    var body: some View {
        UserDetailView(
            user: user,
            primaryTitle: primaryTitle,
            primaryLabel: primaryLabel,
            onClose: { dismiss() }
        )
        .frame(width: 780, height: 760)
        .background(Palette.canvas)
    }
}
