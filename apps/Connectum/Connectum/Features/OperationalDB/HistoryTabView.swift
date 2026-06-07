import SwiftUI
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class HistoryViewModel {
    var entries: [HistoryEntry] = []
    var isBusy = false
    var errorMessage: String?
    let crmUserId: String
    private let repo: CrmDataProviding
    init(crmUserId: String, repo: CrmDataProviding = CrmRepository()) { self.crmUserId = crmUserId; self.repo = repo }

    func load() async {
        do { entries = try await repo.fetchHistory(crmUserId: crmUserId) }
        catch { errorMessage = String(describing: error) }
    }
    func add(entryDate: String, memo: String, imageData: Data?, fileExt: String) async {
        isBusy = true; defer { isBusy = false }
        do { try await repo.addHistory(crmUserId: crmUserId, entryDate: entryDate, memo: memo, imageData: imageData, fileExt: fileExt); await load() }
        catch { errorMessage = String(describing: error) }
    }
}

struct HistoryTabView: View {
    @State private var vm: HistoryViewModel
    @State private var date = ""
    @State private var memo = ""
    @State private var pickedData: Data?
    @State private var pickedExt = "jpg"
    @State private var importing = false
    init(crmUserId: String) { _vm = State(initialValue: HistoryViewModel(crmUserId: crmUserId)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                // Add form
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("새 히스토리").font(Typography.caption).foregroundStyle(Palette.muted)
                    TextField("날짜 (예: 2026-06-08)", text: $date).textFieldStyle(.plain)
                        .padding(Spacing.sm).background(Palette.surfaceElevated).clipShape(RoundedRectangle(cornerRadius: Radius.button))
                    Button { importing = true } label: {
                        Text(pickedData == nil ? "이미지 선택" : "이미지 선택됨 ✓").font(Typography.caption)
                            .foregroundStyle(Palette.ink).padding(.horizontal, Spacing.md).frame(height: 28)
                            .background(Palette.surfaceElevated).clipShape(Capsule())
                    }.buttonStyle(.plain)
                    TextField("메모", text: $memo, axis: .vertical).textFieldStyle(.plain).lineLimit(2...6)
                        .padding(Spacing.sm).background(Palette.surfaceElevated).clipShape(RoundedRectangle(cornerRadius: Radius.button))
                    Button {
                        let d = date; let m = memo; let img = pickedData; let ext = pickedExt
                        Task { await vm.add(entryDate: d, memo: m, imageData: img, fileExt: ext); date = ""; memo = ""; pickedData = nil }
                    } label: {
                        Text(vm.isBusy ? "추가 중…" : "추가").font(Typography.caption).foregroundStyle(Palette.ctaText)
                            .padding(.horizontal, Spacing.md).frame(height: 28).background(Palette.ctaFill).clipShape(Capsule())
                    }.buttonStyle(.plain).disabled(vm.isBusy || (date.isEmpty && memo.isEmpty))
                }
                .padding(Spacing.lg).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.surfaceCard).clipShape(RoundedRectangle(cornerRadius: Radius.card))
                .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Palette.hairline))

                // Entries: image left, memo right, grouped by date
                ForEach(vm.entries) { e in
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(e.entryDate).font(Typography.caption).foregroundStyle(Palette.accentBlue)
                        HStack(alignment: .top, spacing: Spacing.md) {
                            if let u = e.imageUrl, let url = URL(string: u) {
                                AsyncImage(url: url) { img in img.resizable().scaledToFill() } placeholder: { Palette.surfaceElevated }
                                    .frame(width: 160, height: 120).clipShape(RoundedRectangle(cornerRadius: Radius.card)).clipped()
                            }
                            Text(e.memo ?? "").font(Typography.body).foregroundStyle(Palette.body)
                            Spacer()
                        }
                    }
                    .padding(Spacing.lg).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.surfaceCard).clipShape(RoundedRectangle(cornerRadius: Radius.card))
                    .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Palette.hairline))
                }
                if vm.entries.isEmpty { Text("히스토리 없음").font(Typography.caption).foregroundStyle(Palette.muted) }
            }
            .padding(Spacing.xl)
        }
        .background(Palette.canvas)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result {
                if url.startAccessingSecurityScopedResource() {
                    defer { url.stopAccessingSecurityScopedResource() }
                    pickedData = try? Data(contentsOf: url)
                    pickedExt = url.pathExtension.isEmpty ? "jpg" : url.pathExtension.lowercased()
                }
            }
        }
        .task { await vm.load() }
    }
}
