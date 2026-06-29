import SwiftUI
#if os(macOS)
import AppKit
#endif

struct UserDetailView: View {
    @State private var vm: UserDetailViewModel
    @State private var section: UserDetailSection = .workspace
    @AppStorage("userDetailWorkspaceCardOrder") private var workspaceCardOrderRaw = UserDetailWorkspaceCard.encoded(UserDetailWorkspaceCard.defaultOrder)
    @State private var isEditingWorkspaceLayout = false
    @State private var dropTargetCard: UserDetailWorkspaceCard?
    let primaryTitle: String?
    let primaryLabel: String?
    let onExclude: (() -> Void)?
    let onClose: (() -> Void)?

    init(user: CrmUser, primaryTitle: String? = nil, primaryLabel: String? = nil, onExclude: (() -> Void)? = nil, onClose: (() -> Void)? = nil) {
        _vm = State(initialValue: UserDetailViewModel(user: user))
        self.primaryTitle = primaryTitle
        self.primaryLabel = primaryLabel
        self.onExclude = onExclude
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Palette.hairline)
            switch section {
            case .workspace:
                workspace
            case .history:
                HistoryTabView(crmUserId: vm.user.id)
            }
        }
        .background(Palette.inspectorSurface)
        .background(detailKeyCapture)
        .task { await vm.loadEvents() }
    }

    private func toggleSection() {
        section = section == .workspace ? .history : .workspace
    }

    @ViewBuilder private var detailKeyCapture: some View {
        #if os(macOS)
        DetailKeyCaptureView(focusID: vm.user.id, onTab: toggleSection)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        #endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .center, spacing: Spacing.md) {
                identityIcon
                identityText
                    .layoutPriority(0)
                Spacer(minLength: Spacing.sm)
                closeButton
                    .layoutPriority(1)
            }
            headerControls
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .background(Palette.inspectorSurface)
    }

    private var identityIcon: some View {
        ZStack {
            Circle().fill(Palette.surfaceElevated)
            Image(systemName: "person.crop.circle")
                .font(.system(size: 25, weight: .regular))
                .foregroundStyle(Palette.muted)
        }
        .frame(width: 42, height: 42)
    }

    private var identityText: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(primaryTitle?.isEmpty == false ? primaryTitle! : vm.user.email ?? vm.user.sourceUserId)
                .font(Typography.cardTitle)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            metadataLine
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var metadataLine: some View {
        let parts = headerMetadataParts
        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(Typography.caption)
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var headerMetadataParts: [String] {
        var parts: [String] = []
        if let primaryLabel, primaryLabel != "이메일" {
            parts.append(primaryLabel)
        }
        if let email = vm.user.email, primaryTitle != email {
            parts.append(email)
        }
        if let createdAt = vm.user.createdAt {
            parts.append(createdAt)
        }
        if parts.isEmpty {
            parts.append(vm.user.sourceUserId)
        }
        return parts
    }

    private var sectionPicker: some View {
        Picker("", selection: $section) {
            ForEach(UserDetailSection.allCases) { section in
                Text(section.rawValue).tag(section)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var headerControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.sm) {
                sectionPicker.frame(width: 154)
                Spacer(minLength: Spacing.sm)
                headerActions
            }

            VStack(alignment: .leading, spacing: Spacing.sm) {
                sectionPicker.frame(width: 154)
                headerActions
            }
        }
    }

    private var headerActions: some View {
        HStack(spacing: Spacing.sm) {
            contactButton
            excludeButton
        }
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(2)
    }

    @ViewBuilder private var excludeButton: some View {
        if let onExclude {
            Button {
                onExclude()
            } label: {
                Label("제외", systemImage: "eye.slash")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.accentRed)
                    .frame(height: 30)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private var closeButton: some View {
        if let onClose {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
    }

    private var contactButton: some View {
        Button { Task { await vm.toggleContacted() } } label: {
            Label(vm.contactStatus == "contacted" ? "컨택함" : "미컨택", systemImage: vm.contactStatus == "contacted" ? "checkmark.circle.fill" : "circle")
                .font(Typography.caption)
                .foregroundStyle(vm.contactStatus == "contacted" ? Palette.ctaText : Palette.ink)
                .padding(.horizontal, Spacing.md)
                .frame(height: 30)
                .background(vm.contactStatus == "contacted" ? Palette.ctaFill : Palette.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: Radius.button))
        }
        .buttonStyle(.plain)
        .disabled(vm.isBusy)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var workspace: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    workspaceToolbar
                    workspaceCards(width: proxy.size.width)
                    errorText
                }
                .padding(Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private var workspaceToolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: Spacing.md) {
                workspaceToolbarTitle
                Spacer(minLength: Spacing.md)
                workspaceToolbarActions
            }

            VStack(alignment: .leading, spacing: Spacing.sm) {
                workspaceToolbarTitle
                workspaceToolbarActions
            }
        }
    }

    private var workspaceToolbarTitle: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("카드 배치")
                .font(Typography.body)
                .foregroundStyle(Palette.ink)
            Text(isEditingWorkspaceLayout ? "표시 순서 편집 중" : "작업 탭 구성")
                .font(Typography.caption)
                .foregroundStyle(Palette.muted)
                .lineLimit(2)
        }
    }

    private var workspaceToolbarActions: some View {
        HStack(spacing: Spacing.sm) {
            if isEditingWorkspaceLayout {
                Button {
                    setWorkspaceCardOrder(UserDetailWorkspaceCard.defaultOrder)
                } label: {
                    Label("기본값", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(WorkspaceChromeButtonStyle())
            }
            if isEditingWorkspaceLayout {
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        isEditingWorkspaceLayout = false
                        dropTargetCard = nil
                    }
                } label: {
                    Label("완료", systemImage: "checkmark")
                }
                .buttonStyle(WorkspacePrimaryButtonStyle())
            } else {
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        isEditingWorkspaceLayout = true
                        dropTargetCard = nil
                    }
                } label: {
                    Label("수정", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(WorkspaceChromeButtonStyle())
            }
        }
    }

    private func workspaceCards(width: CGFloat) -> some View {
        let order = workspaceCardOrder
        return Group {
            if width >= 720 {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: Spacing.lg, alignment: .top),
                        GridItem(.flexible(), spacing: Spacing.lg, alignment: .top)
                    ],
                    alignment: .leading,
                    spacing: Spacing.lg
                ) {
                    ForEach(order) { card in
                        workspaceCardContainer(card, order: order)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    ForEach(order) { card in
                        workspaceCardContainer(card, order: order)
                    }
                }
            }
        }
    }

    private func workspaceCardContainer(_ card: UserDetailWorkspaceCard, order: [UserDetailWorkspaceCard]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if isEditingWorkspaceLayout {
                workspaceCardEditBar(card, order: order)
            }
            workspaceCardContent(card)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(isEditingWorkspaceLayout ? Spacing.sm : 0)
        .background(isEditingWorkspaceLayout ? Palette.surfaceElevated : .clear)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay {
            if isEditingWorkspaceLayout {
                RoundedRectangle(cornerRadius: Radius.card)
                    .stroke(dropTargetCard == card ? Palette.accentBlue : Palette.hairline, lineWidth: dropTargetCard == card ? 2 : 1)
            }
        }
        .dropDestination(for: String.self) { items, _ in
            guard
                let rawValue = items.first,
                let source = UserDetailWorkspaceCard(rawValue: rawValue)
            else {
                return false
            }
            moveWorkspaceCard(source, to: card)
            return true
        } isTargeted: { isTargeted in
            dropTargetCard = isTargeted ? card : nil
        }
    }

    private func workspaceCardEditBar(_ card: UserDetailWorkspaceCard, order: [UserDetailWorkspaceCard]) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.muted)
                .frame(width: 26, height: 26)
                .background(Palette.surfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                .draggable(card.rawValue)
                .help("드래그해서 위치 변경")

            VStack(alignment: .leading, spacing: 2) {
                Text(card.title)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.ink)
                Text(card.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: Spacing.sm)

            HStack(spacing: Spacing.xs) {
                workspaceMoveButton(systemImage: "chevron.up", isDisabled: order.first == card) {
                    moveWorkspaceCard(card, offset: -1)
                }
                workspaceMoveButton(systemImage: "chevron.down", isDisabled: order.last == card) {
                    moveWorkspaceCard(card, offset: 1)
                }
            }
        }
    }

    private func workspaceMoveButton(systemImage: String, isDisabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isDisabled ? Palette.muted.opacity(0.45) : Palette.ink)
                .frame(width: 24, height: 24)
                .background(Palette.surfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.button))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    @ViewBuilder private func workspaceCardContent(_ card: UserDetailWorkspaceCard) -> some View {
        switch card {
        case .aiSummary:
            AISummaryPanel(vm: vm)
        case .contactRecords:
            RecordsSection(vm: vm)
        case .notes:
            NotesSection(crmUserId: vm.user.id)
        case .profile:
            ProfilePanel(user: vm.user)
        case .recentEvents:
            RecentEventsPanel(events: vm.events)
        }
    }

    private var workspaceCardOrder: [UserDetailWorkspaceCard] {
        UserDetailWorkspaceCard.decodedOrder(from: workspaceCardOrderRaw)
    }

    private func setWorkspaceCardOrder(_ order: [UserDetailWorkspaceCard]) {
        withAnimation(.snappy(duration: 0.2)) {
            workspaceCardOrderRaw = UserDetailWorkspaceCard.encoded(order)
        }
    }

    private func moveWorkspaceCard(_ card: UserDetailWorkspaceCard, offset: Int) {
        var order = workspaceCardOrder
        guard
            let sourceIndex = order.firstIndex(of: card),
            order.indices.contains(sourceIndex + offset)
        else {
            return
        }

        order.swapAt(sourceIndex, sourceIndex + offset)
        setWorkspaceCardOrder(order)
    }

    @discardableResult
    private func moveWorkspaceCard(_ source: UserDetailWorkspaceCard, to target: UserDetailWorkspaceCard) -> Bool {
        let order = workspaceCardOrder
        let reorderedOrder = UserDetailWorkspaceCard.reordered(order, moving: source, to: target)
        guard reorderedOrder != order else { return false }

        setWorkspaceCardOrder(reorderedOrder)
        return true
    }

    @ViewBuilder private var errorText: some View {
        if let errorMessage = vm.errorMessage {
            Text(errorMessage)
                .font(Typography.caption)
                .foregroundStyle(Palette.accentRed)
        }
    }
}

#if os(macOS)
private struct DetailKeyCaptureView: NSViewRepresentable {
    let focusID: String
    let onTab: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.focusRingType = .none
        view.onTab = onTab
        return view
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        nsView.onTab = onTab
        guard context.coordinator.focusID != focusID else { return }
        context.coordinator.focusID = focusID
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }

    final class Coordinator {
        var focusID: String?
    }

    final class KeyCaptureNSView: NSView {
        var onTab: () -> Void = {}

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            let flags = event.modifierFlags.intersection([.command, .control, .option])
            if event.keyCode == 48, flags.isEmpty {
                onTab()
                return
            }
            super.keyDown(with: event)
        }
    }
}
#endif

private enum UserDetailSection: String, CaseIterable, Identifiable {
    case workspace = "작업"
    case history = "히스토리"
    var id: String { rawValue }
}

private struct WorkspaceChromeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.caption)
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, Spacing.md)
            .frame(height: 30)
            .background(Palette.surfaceElevated.opacity(configuration.isPressed ? 0.7 : 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.button))
    }
}

private struct WorkspacePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.caption)
            .foregroundStyle(Palette.ctaText)
            .padding(.horizontal, Spacing.md)
            .frame(height: 30)
            .background(Palette.ctaFill.opacity(configuration.isPressed ? 0.82 : 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.button))
    }
}

private struct AISummaryPanel: View {
    @Bindable var vm: UserDetailViewModel

    var body: some View {
        DetailPanel(title: "AI 총평", systemImage: "sparkles") {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text(vm.aiSummary?.isEmpty == false ? vm.aiSummary! : "아직 생성되지 않았습니다.")
                    .font(Typography.body)
                    .foregroundStyle(vm.aiSummary == nil ? Palette.muted : Palette.body)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                Button { Task { await vm.regenerate() } } label: {
                    Label(vm.isRegenerating ? "생성 중" : "재생성", systemImage: "arrow.clockwise")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, Spacing.md)
                        .frame(height: 28)
                        .background(Palette.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                }
                .buttonStyle(.plain)
                .disabled(vm.isRegenerating)
            }
        }
    }
}

private struct ProfilePanel: View {
    let user: CrmUser

    var body: some View {
        DetailPanel(title: "프로필", systemImage: "person.text.rectangle") {
            VStack(alignment: .leading, spacing: Spacing.md) {
                let p = user.amplitudeProfile
                detailRow("이메일", user.email)
                detailRow("유저 ID", user.sourceUserId)
                detailRow("OS", p?.os)
                detailRow("디바이스", p?.deviceFamily ?? p?.deviceType)
                detailRow("지역", location)
                detailRow("최근 활동", p?.lastEventTime)
                detailRow("동기화", user.lastSyncedAt)

                if !profilePreview.isEmpty {
                    Divider().overlay(Palette.hairline)
                    ForEach(profilePreview, id: \.key) { item in
                        detailRow(item.key, item.value)
                    }
                }
            }
        }
    }

    private var location: String? {
        let p = user.amplitudeProfile
        let value = [p?.city, p?.region, p?.country].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: ", ")
        return value.isEmpty ? nil : value
    }

    private var profilePreview: [(key: String, value: String)] {
        (user.supabaseProfile ?? [:])
            .sorted { $0.key < $1.key }
            .map { (key: $0.key, value: $0.value.display) }
            .filter { !$0.value.isEmpty }
            .prefix(6)
            .map { $0 }
    }

    @ViewBuilder private func detailRow(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(Palette.muted)
            Text(value?.isEmpty == false ? value! : "-")
                .font(Typography.body)
                .foregroundStyle(Palette.body)
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }
}

private struct RecentEventsPanel: View {
    let events: [CrmUserEvent]

    var body: some View {
        DetailPanel(title: "최근 이벤트", systemImage: "bolt.horizontal") {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                if events.isEmpty {
                    Text("없음")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.muted)
                } else {
                    ForEach(events.prefix(8)) { event in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.eventType)
                                .font(Typography.body)
                                .foregroundStyle(Palette.body)
                                .lineLimit(1)
                            Text(event.eventTime)
                                .font(Typography.caption)
                                .foregroundStyle(Palette.muted)
                                .lineLimit(1)
                        }
                        if event.id != events.prefix(8).last?.id {
                            Divider().overlay(Palette.hairline)
                        }
                    }
                }
            }
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
        DetailPanel(title: "컨택 기록", systemImage: "bubble.left.and.text.bubble.right") {
            VStack(alignment: .leading, spacing: Spacing.md) {
                if vm.records.isEmpty {
                    Text("기록 없음")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.muted)
                } else {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        ForEach(vm.records) { record in
                            HStack(alignment: .top, spacing: Spacing.sm) {
                                Text(record.channel)
                                    .font(Typography.caption)
                                    .foregroundStyle(Palette.accentBlue)
                                    .frame(width: 72, alignment: .leading)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(record.body)
                                        .font(Typography.body)
                                        .foregroundStyle(Palette.body)
                                    Text(record.occurredAt ?? "")
                                        .font(Typography.caption)
                                        .foregroundStyle(Palette.muted)
                                }
                                Spacer(minLength: Spacing.sm)
                            }
                        }
                    }
                }

                Divider().overlay(Palette.hairline)

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .bottom, spacing: Spacing.sm) {
                        channelPicker
                            .frame(width: 118)
                        dateField
                            .frame(width: 132)
                        noteField
                            .frame(minWidth: 160)
                        addRecordButton
                    }

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        HStack(spacing: Spacing.sm) {
                            channelPicker
                            dateField
                        }
                        HStack(alignment: .bottom, spacing: Spacing.sm) {
                            noteField
                            addRecordButton
                        }
                    }
                }
            }
        }
        .task { await vm.loadRecords() }
    }

    private var channelPicker: some View {
        Picker("", selection: $channel) {
            ForEach(channels, id: \.self) { Text($0).tag($0) }
        }
        .labelsHidden()
    }

    private var dateField: some View {
        TextField("날짜", text: $date)
            .textFieldStyle(.plain)
            .font(Typography.body)
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, Spacing.sm)
            .frame(height: 30)
            .background(Palette.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: Radius.button))
    }

    private var noteField: some View {
        TextField("내용", text: $note, axis: .vertical)
            .textFieldStyle(.plain)
            .lineLimit(2...5)
            .font(Typography.body)
            .foregroundStyle(Palette.body)
            .padding(Spacing.sm)
            .frame(minWidth: 0, maxWidth: .infinity)
            .background(Palette.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: Radius.button))
    }

    private var addRecordButton: some View {
        Button {
            let c = channel
            let d = date
            let b = note
            Task {
                await vm.addRecord(channel: c, occurredAt: d, body: b)
                note = ""
                date = ""
            }
        } label: {
            Label("추가", systemImage: "plus")
                .font(Typography.caption)
                .foregroundStyle(Palette.ctaText)
                .padding(.horizontal, Spacing.md)
                .frame(height: 30)
                .background(Palette.ctaFill)
                .clipShape(RoundedRectangle(cornerRadius: Radius.button))
        }
        .buttonStyle(.plain)
        .disabled(note.isEmpty)
    }
}

private struct DetailPanel<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 16)
                Text(title)
                    .font(Typography.body)
                    .foregroundStyle(Palette.ink)
            }
            content()
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Palette.hairline))
    }
}
