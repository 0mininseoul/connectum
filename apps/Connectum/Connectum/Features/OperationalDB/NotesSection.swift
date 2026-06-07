import SwiftUI
import Observation

@MainActor
@Observable
final class NotesViewModel {
    var blocks: [NoteBlock] = []
    var draft = ""
    var isBusy = false
    var errorMessage: String?
    let crmUserId: String
    private let repo: CrmDataProviding
    init(crmUserId: String, repo: CrmDataProviding = CrmRepository()) { self.crmUserId = crmUserId; self.repo = repo }

    func load() async {
        do { blocks = try await repo.fetchNoteBlocks(crmUserId: crmUserId) }
        catch { errorMessage = String(describing: error) }
    }
    func add() async {
        guard !draft.isEmpty else { return }
        isBusy = true; defer { isBusy = false }
        do { try await repo.addNoteBlock(crmUserId: crmUserId, text: draft); draft = ""; await load() }
        catch { errorMessage = String(describing: error) }
    }
    func update(_ block: NoteBlock) async {
        do { try await repo.updateNoteBlock(id: block.id, text: block.text) }
        catch { errorMessage = String(describing: error) }
    }
    func delete(_ id: String) async {
        do { try await repo.deleteNoteBlock(id: id); await load() }
        catch { errorMessage = String(describing: error) }
    }
}

struct NotesSection: View {
    @State private var vm: NotesViewModel
    init(crmUserId: String) { _vm = State(initialValue: NotesViewModel(crmUserId: crmUserId)) }

    var body: some View {
        @Bindable var vm = vm
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("노트 (자유 블록)").font(Typography.caption).foregroundStyle(Palette.muted)
            ForEach($vm.blocks) { $block in
                HStack(alignment: .top, spacing: Spacing.sm) {
                    TextField("내용", text: $block.text, axis: .vertical)
                        .textFieldStyle(.plain).lineLimit(1...10).font(Typography.body).foregroundStyle(Palette.body)
                        .padding(Spacing.sm).background(Palette.surfaceElevated).clipShape(RoundedRectangle(cornerRadius: Radius.button))
                        .onSubmit { Task { await vm.update(block) } }
                    Button { Task { await vm.delete(block.id) } } label: {
                        Image(systemName: "trash").font(.caption).foregroundStyle(Palette.muted)
                    }.buttonStyle(.plain)
                }
            }
            if vm.blocks.isEmpty { Text("블록 없음 — 아래에서 추가하세요").font(Typography.caption).foregroundStyle(Palette.muted) }
            HStack(spacing: Spacing.sm) {
                TextField("새 텍스트 블록", text: $vm.draft, axis: .vertical).textFieldStyle(.plain).lineLimit(1...6)
                    .padding(Spacing.sm).background(Palette.surfaceElevated).clipShape(RoundedRectangle(cornerRadius: Radius.button))
                Button { Task { await vm.add() } } label: {
                    Text("추가").font(Typography.caption).foregroundStyle(Palette.ctaText)
                        .padding(.horizontal, Spacing.md).frame(height: 28).background(Palette.ctaFill).clipShape(Capsule())
                }.buttonStyle(.plain).disabled(vm.isBusy || vm.draft.isEmpty)
            }
        }
        .padding(Spacing.lg).frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceCard).clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Palette.hairline))
        .task { await vm.load() }
    }
}
