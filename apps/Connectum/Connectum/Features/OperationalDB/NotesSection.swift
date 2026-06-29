import SwiftUI
import Observation

@MainActor
@Observable
final class NotesViewModel {
    var text = ""
    var isBusy = false
    var errorMessage: String?
    let crmUserId: String
    private let repo: CrmDataProviding
    private var blocks: [NoteBlock] = []
    init(crmUserId: String, repo: CrmDataProviding = CrmRepository()) { self.crmUserId = crmUserId; self.repo = repo }

    var canSave: Bool {
        !isBusy && (!text.isEmpty || !blocks.isEmpty)
    }

    func load() async {
        do {
            blocks = try await repo.fetchNoteBlocks(crmUserId: crmUserId)
            text = blocks.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n\n")
        }
        catch { errorMessage = String(describing: error) }
    }

    func save() async {
        guard !text.isEmpty || !blocks.isEmpty else { return }
        isBusy = true; defer { isBusy = false }

        do {
            if let primaryBlock = blocks.first {
                try await repo.updateNoteBlock(id: primaryBlock.id, text: text)
                for block in blocks.dropFirst() {
                    try await repo.deleteNoteBlock(id: block.id)
                }
            } else {
                try await repo.addNoteBlock(crmUserId: crmUserId, text: text)
            }
            await load()
        }
        catch { errorMessage = String(describing: error) }
    }
}

struct NotesSection: View {
    @State private var vm: NotesViewModel
    init(crmUserId: String) { _vm = State(initialValue: NotesViewModel(crmUserId: crmUserId)) }

    var body: some View {
        @Bindable var vm = vm
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "note.text")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 16)
                Text("노트")
                    .font(Typography.body)
                    .foregroundStyle(Palette.ink)
            }

            VStack(alignment: .leading, spacing: Spacing.sm) {
                TextField("유저에게 남길 메모를 입력하세요", text: $vm.text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(4...12)
                    .font(Typography.body)
                    .foregroundStyle(Palette.body)
                    .padding(Spacing.md)
                    .frame(minHeight: 96, alignment: .topLeading)
                    .background(Palette.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                    .onSubmit { Task { await vm.save() } }

                HStack {
                    if let errorMessage = vm.errorMessage {
                        Text(errorMessage)
                            .font(Typography.caption)
                            .foregroundStyle(Palette.accentRed)
                            .lineLimit(2)
                    }
                    Spacer(minLength: Spacing.sm)
                    Button {
                        Task { await vm.save() }
                    } label: {
                        Label(vm.isBusy ? "저장 중" : "저장", systemImage: "checkmark")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.ctaText)
                            .padding(.horizontal, Spacing.md)
                            .frame(height: 30)
                            .background(Palette.ctaFill)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                    }
                    .buttonStyle(.plain)
                    .disabled(!vm.canSave)
                }
            }
        }
        .padding(Spacing.md).frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceCard).clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Palette.hairline))
        .task { await vm.load() }
    }
}
