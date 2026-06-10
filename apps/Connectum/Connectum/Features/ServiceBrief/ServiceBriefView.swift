import SwiftUI
import UniformTypeIdentifiers

struct ServiceBriefView: View {
    @State var model: ServiceBriefViewModel
    @State private var showImporter = false
    @Environment(\.dismiss) private var dismiss

    init(serviceId: String) {
        _model = State(initialValue: ServiceBriefViewModel(serviceId: serviceId))
    }
    init(model: ServiceBriefViewModel) {
        _model = State(initialValue: model)
    }

    private var importerTypes: [UTType] {
        var types: [UTType] = [.plainText, .pdf]
        if let md = UTType(filenameExtension: "md") { types.append(md) }
        return types
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.interviewActive {
                        interviewOverlay
                    } else if model.isEmpty {
                        emptyState
                    } else {
                        briefSections
                        gapNudge
                    }
                    if let e = model.errorText {
                        Text(e).font(.callout).foregroundStyle(.red)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !model.interviewActive {
                Divider()
                promptBar
            }
        }
        .frame(width: 540, height: 640)
        .task { await model.load() }
    }

    private var header: some View {
        HStack {
            Image(systemName: "doc.text.magnifyingglass")
            Text("서비스 브리프").font(.headline)
            Spacer()
            if model.isBusy { ProgressView().controlSize(.small) }
            Button("닫기") { dismiss() }
        }
        .padding()
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("이 서비스에 대해 알려주면 AI 채팅이 훨씬 똑똑해집니다.")
                .font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                documentMenu
                Button { Task { await model.startInterview() } } label: {
                    Label("질문으로 채우기", systemImage: "bubble.left.and.text.bubble.right")
                }.disabled(model.isBusy)
            }
            Button { Task { await model.autodraft() } } label: {
                Label("연동 정보로 초안 만들기", systemImage: "sparkles")
            }
            .buttonStyle(.borderless)
            .disabled(model.isBusy)
        }
    }

    private var briefSections: some View {
        ForEach(BriefSections.displayOrder, id: \.key) { item in
            let v = model.sections.value(for: item.key)
            if !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.label).font(.subheadline).bold().foregroundStyle(.secondary)
                    Text(v).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder private var gapNudge: some View {
        if !model.pendingGaps.isEmpty && !model.interviewActive {
            Button { Task { await model.startInterview(targets: model.pendingGaps) } } label: {
                Label("부족한 부분을 질문으로 채우기 (\(model.pendingGaps.count))", systemImage: "questionmark.bubble")
            }
            .buttonStyle(.borderless)
            .disabled(model.isBusy)
        }
    }

    private var interviewOverlay: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("서비스 인터뷰").font(.subheadline).bold()
                Spacer()
                Button("그만두기") { model.interviewActive = false }.controlSize(.small)
            }
            ForEach(model.interviewTurns) { turn in
                Text(turn.text)
                    .padding(8)
                    .background(turn.role == "user" ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .frame(maxWidth: .infinity, alignment: turn.role == "user" ? .trailing : .leading)
            }
            if !model.interviewOptions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.interviewOptions, id: \.self) { opt in
                        Button(opt) { Task { await model.answerInterview(opt) } }
                            .buttonStyle(.bordered)
                            .disabled(model.isBusy)
                    }
                }
            }
            HStack {
                TextField("답변…", text: $model.interviewAnswer, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
                    .onSubmit { Task { await model.answerInterview(model.interviewAnswer) } }
                if model.isBusy { ProgressView().controlSize(.small) }
            }
        }
    }

    private var documentMenu: some View {
        Menu {
            Button("텍스트 붙여넣기") { model.showPasteSheet = true }
            Button("파일 선택 (.md/.txt/.pdf)") { showImporter = true }
        } label: {
            Label("문서로 채우기", systemImage: "doc.text")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(model.isBusy)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: importerTypes, allowsMultipleSelection: false) { result in
            if case let .success(urls) = result, let url = urls.first {
                Task { await model.ingestFile(url: url) }
            }
        }
        .sheet(isPresented: $model.showPasteSheet) { pasteSheet }
    }

    private var pasteSheet: some View {
        VStack(spacing: 12) {
            Text("서비스 설명 문서 붙여넣기").font(.headline)
            TextEditor(text: $model.pasteText)
                .frame(width: 460, height: 320)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            HStack {
                Button("취소") { model.showPasteSheet = false }
                Spacer()
                Button("분석") { Task { await model.ingestPaste() } }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(model.pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 500)
    }

    private var promptBar: some View {
        HStack(spacing: 8) {
            if model.isEmpty { documentMenu }
            TextField("브리프를 어떻게 바꿀까요? (예: ICP에 B2B SaaS 추가)", text: $model.promptText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .onSubmit { Task { await model.applyPrompt() } }
            Button { Task { await model.applyPrompt() } } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title2)
            }
            .buttonStyle(.plain)
            .disabled(model.isBusy || model.promptText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding()
    }
}
