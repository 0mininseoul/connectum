import SwiftUI

struct AIChatView: View {
    let serviceId: String?
    @State private var vm = AIChatViewModel()
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Palette.hairline)
            if !vm.connected {
                notConnected
            } else {
                messagesList
                if let s = vm.statusText { statusChip(s) }
                inputBar
            }
        }
        .background(Palette.canvas)
        .task {
            vm.serviceId = serviceId
            await vm.refreshConnection()
            inputFocused = true
        }
        .onChange(of: serviceId) { _, new in vm.serviceId = new }
    }

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "sparkles").foregroundStyle(Palette.accentBlue)
            Text("AI 채팅").font(Typography.cardTitle).foregroundStyle(Palette.ink)
            Spacer()
            Label(serviceId == nil ? "서비스 없음" : "기준 서비스", systemImage: "cylinder.split.1x2")
                .font(Typography.caption).foregroundStyle(Palette.muted)
        }
        .padding(Spacing.md)
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

    private func bubble(_ m: ChatMessage) -> some View {
        HStack {
            if m.role == .user { Spacer(minLength: 32) }
            Text(m.text.isEmpty && m.isStreaming ? "…" : m.text)
                .font(Typography.body)
                .foregroundStyle(m.role == .user ? Palette.ctaText : Palette.ink)
                .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.sm)
                .background(m.role == .user ? Palette.ctaFill : Palette.surfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                .textSelection(.enabled)
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
            Image(systemName: "sparkles").font(.system(size: 26)).foregroundStyle(Palette.accentBlue)
            Text("Claude 계정을 연결하세요").font(Typography.body).foregroundStyle(Palette.ink)
            Text("연동 탭에서 Claude(AI)를 연결하면 데이터에 대해 대화할 수 있어요.")
                .font(Typography.caption).foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
        }
        .padding(Spacing.xl).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
