import SwiftUI
#if os(macOS)
import AppKit
#endif

struct UserDetailView: View {
    @State private var vm: UserDetailViewModel
    @State private var section: UserDetailSection = .workspace
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
        .background(Palette.canvas)
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
        ViewThatFits(in: .horizontal) {
            expandedHeader
            compactHeader
        }
        .background(Palette.surface)
    }

    private var expandedHeader: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            identityIcon
            identityText
            Spacer(minLength: Spacing.md)
            sectionPicker.frame(width: 170)
            contactButton
            excludeButton
            closeButton
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
    }

    private var compactHeader: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .center, spacing: Spacing.md) {
                identityIcon
                identityText
                Spacer(minLength: Spacing.sm)
                closeButton
            }
            HStack(spacing: Spacing.sm) {
                sectionPicker.frame(width: 150)
                contactButton
                excludeButton
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
    }

    private var identityIcon: some View {
        ZStack {
            Circle().fill(Palette.surfaceElevated)
            Image(systemName: "person.crop.circle")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(Palette.muted)
        }
        .frame(width: 46, height: 46)
    }

    private var identityText: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(primaryTitle?.isEmpty == false ? primaryTitle! : vm.user.email ?? vm.user.sourceUserId)
                .font(Typography.cardTitle)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            HStack(spacing: Spacing.sm) {
                if let primaryLabel, primaryLabel != "이메일" {
                    Text(primaryLabel)
                    Text("·")
                }
                if let email = vm.user.email, primaryTitle != email {
                    Text(email)
                    Text("·")
                }
                Text(vm.user.sourceUserId)
                if let createdAt = vm.user.createdAt {
                    Text("·")
                    Text(createdAt)
                }
            }
            .font(Typography.caption)
            .foregroundStyle(Palette.muted)
            .lineLimit(1)
        }
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
    }

    private var workspace: some View {
        GeometryReader { proxy in
            if proxy.size.width < 680 {
                compactWorkspace
            } else {
                expandedWorkspace
            }
        }
    }

    private var expandedWorkspace: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    AISummaryPanel(vm: vm)
                    RecordsSection(vm: vm)
                    NotesSection(crmUserId: vm.user.id)
                }
                .padding(Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            Divider().overlay(Palette.hairline)

            sideRail
                .frame(width: 280)
        }
    }

    private var compactWorkspace: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                AISummaryPanel(vm: vm)
                ProfilePanel(user: vm.user)
                RecentEventsPanel(events: vm.events)
                RecordsSection(vm: vm)
                NotesSection(crmUserId: vm.user.id)
                errorText
            }
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var sideRail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                ProfilePanel(user: vm.user)
                RecentEventsPanel(events: vm.events)
                errorText
            }
            .padding(Spacing.lg)
        }
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
            .prefix(6)
            .map { ($0.key, String(describing: $0.value)) }
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

                HStack(spacing: Spacing.sm) {
                    Picker("", selection: $channel) {
                        ForEach(channels, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 120)

                    TextField("날짜", text: $date)
                        .textFieldStyle(.plain)
                        .font(Typography.body)
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, Spacing.sm)
                        .frame(width: 136, height: 30)
                        .background(Palette.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                }

                HStack(alignment: .bottom, spacing: Spacing.sm) {
                    TextField("내용", text: $note, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(2...5)
                        .font(Typography.body)
                        .foregroundStyle(Palette.body)
                        .padding(Spacing.sm)
                        .background(Palette.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.button))
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
        }
        .task { await vm.loadRecords() }
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
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Palette.hairline))
    }
}
