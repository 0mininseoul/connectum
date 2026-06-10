import SwiftUI

struct AIChatView: View {
    @Bindable var vm: AIChatViewModel
    let serviceId: String?
    var isVisible: Bool = true
    @FocusState private var inputFocused: Bool
    @State private var focusTask: Task<Void, Never>?
    @State private var showBrief = false
    @State private var briefEmpty = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Palette.hairline)
            if !vm.connected {
                notConnected
            } else {
                if briefEmpty { briefBanner }
                messagesList
                if let s = vm.statusText { statusChip(s) }
                inputBar
            }
        }
        .background(Palette.canvas)
        .sheet(isPresented: $showBrief, onDismiss: { Task { await refreshBriefState() } }) {
            if let sid = serviceId { ServiceBriefView(serviceId: sid) }
        }
        .task(id: serviceId) { await refreshBriefState() }
        .task {
            await vm.bind(serviceId: serviceId)
        }
        .task {
            focusInput()
        }
        .onChange(of: isVisible) { _, visible in
            // The inspector keeps this view alive across Cmd+I toggles, so .task
            // won't re-run on reopen — focus on each open, stop trying on close.
            if visible { focusInput() } else { focusTask?.cancel() }
        }
        .onChange(of: serviceId) { _, new in Task { await vm.bind(serviceId: new) } }
    }

    // Focus the input right after Cmd+I. Retries briefly because the inspector
    // slide-in / window-key timing can drop a single early focus attempt.
    // Replaces any in-flight attempt so retries never overlap or outlive the open.
    private func focusInput() {
        focusTask?.cancel()
        focusTask = Task { @MainActor in
            for _ in 0 ..< 12 {
                if Task.isCancelled { return }
                if vm.connected { inputFocused = true }
                try? await Task.sleep(for: .milliseconds(50))
                if inputFocused { return }
            }
        }
    }

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            ClaudeMark(size: 17)
            Text("AI 채팅").font(Typography.cardTitle).foregroundStyle(Palette.ink)
            Spacer()
            // Always-available entry to view/edit this service's brief — the empty
            // banner disappears once filled, so this is how you reopen it later.
            if serviceId != nil {
                Button { showBrief = true } label: {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(briefEmpty ? Palette.accentBlue : Palette.muted)
                }
                .buttonStyle(.plain)
                .help("서비스 브리프 보기·수정")
            }
            Label(serviceId == nil ? "서비스 없음" : "기준 서비스", systemImage: "cylinder.split.1x2")
                .font(Typography.caption).foregroundStyle(Palette.muted)
        }
        .padding(Spacing.md)
    }

    // Nudge shown when this service has no brief yet: the assistant only knows the
    // raw data, not what the service is. Opens the brief editor.
    private var briefBanner: some View {
        Button { showBrief = true } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "lightbulb")
                Text("AI가 이 서비스를 더 잘 이해하게 하기")
                    .font(Typography.caption)
                Spacer()
                Image(systemName: "chevron.right").font(Typography.caption)
            }
            .foregroundStyle(Palette.accentBlue)
            .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.accentBlue.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: Radius.button))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Spacing.md).padding(.top, Spacing.sm)
    }

    private func refreshBriefState() async {
        guard let sid = serviceId else { briefEmpty = false; return }
        let brief = try? await CrmRepository().fetchServiceBrief(serviceId: sid)
        briefEmpty = brief?.isEmpty ?? true
    }

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    if vm.messages.isEmpty { emptyHint }
                    ForEach(vm.messages) { m in
                        bubble(m).id(m.id)
                    }
                    if let e = vm.errorText {
                        Text(e).font(Typography.caption).foregroundStyle(Palette.accentRed)
                    }
                }
                .padding(Spacing.md)
            }
            .scrollContentBackground(.hidden)
            .onChange(of: vm.messages.last?.text) { _, _ in
                if let last = vm.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
    }

    @ViewBuilder
    private func bubble(_ m: ChatMessage) -> some View {
        HStack {
            if m.role == .user { Spacer(minLength: 32) }
            if m.role == .assistant && m.isStreaming && m.text.isEmpty {
                TypingIndicator()
                    .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.sm + 2)
                    .background(Palette.surfaceCard)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card))
            } else {
                Text(m.text)
                    .font(Typography.body)
                    .foregroundStyle(m.role == .user ? Palette.ctaText : Palette.ink)
                    .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.sm)
                    .background(m.role == .user ? Palette.ctaFill : Palette.surfaceCard)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                    .textSelection(.enabled)
            }
            if m.role == .assistant { Spacer(minLength: 32) }
        }
    }

    private var emptyHint: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("이 서비스의 데이터에 대해 물어보세요").font(Typography.body).foregroundStyle(Palette.ink)
            Text("예: \"이번 주 가입한 유저 알려줘\", \"아직 연락 안 한 유저 수는?\"")
                .font(Typography.caption).foregroundStyle(Palette.muted)
        }
        .padding(.vertical, Spacing.sm)
    }

    private func statusChip(_ s: String) -> some View {
        HStack(spacing: Spacing.xs) {
            ProgressView().controlSize(.small)
            Text(s).font(Typography.caption).foregroundStyle(Palette.muted)
        }
        .padding(.horizontal, Spacing.md).padding(.bottom, Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inputBar: some View {
        HStack(spacing: Spacing.sm) {
            TextField("데이터에 대해 질문하세요…", text: $vm.inputText, axis: .vertical)
                .textFieldStyle(.plain).lineLimit(1...5)
                .focused($inputFocused)
                .onSubmit { Task { await vm.send() } }
                .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.sm)
                .background(Palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                .overlay(RoundedRectangle(cornerRadius: Radius.button).stroke(Palette.hairline))
            Button { Task { await vm.send() } } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 24))
                    .foregroundStyle(vm.isStreaming ? Palette.muted : Palette.accentBlue)
            }
            .buttonStyle(.plain).disabled(vm.isStreaming)
        }
        .padding(Spacing.md)
    }

    private var notConnected: some View {
        VStack(spacing: Spacing.md) {
            ClaudeMark(size: 30)
            Text("Claude 계정을 연결하세요").font(Typography.body).foregroundStyle(Palette.ink)
            Text("연동 탭에서 Claude(AI)를 연결하면 데이터에 대해 대화할 수 있어요.")
                .font(Typography.caption).foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
            Button { Task { await vm.refreshConnection() } } label: {
                Label("다시 확인", systemImage: "arrow.clockwise")
                    .font(Typography.caption).foregroundStyle(Palette.accentBlue)
            }
            .buttonStyle(.plain)
        }
        .padding(Spacing.xl).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// Animated "generating" dots shown in the assistant bubble while awaiting a reply.
private struct TypingIndicator: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Palette.muted)
                        .frame(width: 6, height: 6)
                        .opacity(opacity(t, i))
                        .scaleEffect(0.85 + 0.3 * opacity(t, i))
                }
            }
        }
        .frame(height: 10)
    }

    private func opacity(_ t: Double, _ i: Int) -> Double {
        let v = sin(t * 3.0 - Double(i) * 0.7)
        return 0.3 + 0.7 * ((v + 1) / 2)
    }
}
