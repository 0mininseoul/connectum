import SwiftUI

@MainActor
@Observable
final class MirroredTableViewModel {
    var rows: [MirroredRow] = []
    var columns: [String] = []
    var isLoading = false
    var errorMessage: String?
    private var loadedTableId: String?

    private let repo: CrmDataProviding
    init(repo: CrmDataProviding = CrmRepository()) { self.repo = repo }

    func load(serviceTableId: String) async {
        // Switching tables: drop the previous table's rows so a slow/failed load
        // never shows stale data under the new table's header.
        if serviceTableId != loadedTableId { rows = []; columns = []; errorMessage = nil }
        isLoading = rows.isEmpty
        defer { isLoading = false }
        do {
            let fetched = try await repo.fetchMirroredRows(serviceTableId: serviceTableId, limit: 1000)
            let cols = await Task.detached { Self.orderedColumns(from: fetched) }.value
            rows = fetched
            columns = cols
            loadedTableId = serviceTableId
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    // Union of every row's keys, with common identity/time columns surfaced first
    // and the rest alphabetised, so the table layout is stable across loads.
    private nonisolated static func orderedColumns(from rows: [MirroredRow]) -> [String] {
        var seen = Set<String>()
        for r in rows { for k in r.data.keys { seen.insert(k) } }
        let priority = ["id", "created_at", "updated_at", "name", "title", "email"]
        let front = priority.filter { seen.contains($0) }
        let rest = seen.subtracting(front).sorted()
        return front + rest
    }
}

// A generic, read-only table for one `related` source table's synced rows. The
// user table keeps its rich crm_user UI; this renders raw mirrored JSONB so any
// extra imported table is viewable without bespoke per-table code.
struct MirroredTableView: View {
    let table: ServiceTableInfo
    let refreshID: Int
    @State private var vm = MirroredTableViewModel()

    var body: some View {
        Group {
            if vm.isLoading && vm.rows.isEmpty {
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let e = vm.errorMessage, vm.rows.isEmpty {
                message("exclamationmark.triangle", "불러오기 실패", e)
            } else if vm.rows.isEmpty {
                message("tray", "아직 동기화된 행이 없어요",
                        "사이드바에서 이 서비스를 동기화하면 ‘\(table.displayName)’ 데이터를 가져옵니다.")
            } else {
                tableContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.canvas)
        .task(id: "\(table.id):\(refreshID)") { await vm.load(serviceTableId: table.id) }
    }

    private var tableContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.sm) {
                Text(table.displayName).font(Typography.body).foregroundStyle(Palette.ink)
                Text("\(vm.rows.count)행").font(Typography.caption).foregroundStyle(Palette.muted)
                Spacer()
            }
            .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.sm)
            Divider().overlay(Palette.hairline)
            Table(vm.rows) {
                TableColumnForEach(vm.columns, id: \.self) { key in
                    TableColumn(key) { (row: MirroredRow) in
                        Text(row.data[key]?.display ?? "—")
                            .foregroundStyle(Palette.body)
                            .help(row.data[key]?.display ?? "")
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
    }

    private func message(_ icon: String, _ title: String, _ detail: String) -> some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: icon).font(.system(size: 26)).foregroundStyle(Palette.muted)
            Text(title).font(Typography.body).foregroundStyle(Palette.ink)
            Text(detail).font(Typography.caption).foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
