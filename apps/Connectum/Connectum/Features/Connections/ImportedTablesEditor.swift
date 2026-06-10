import SwiftUI

@MainActor
@Observable
final class ImportedTablesEditorModel {
    let service: Service
    var projectTables: [TableInfo] = []
    var current: [ServiceTableInfo] = []     // existing service_table rows
    var selected: Set<String> = []           // chosen table ids ("schema.table")
    var userTableKey: String?                // the locked user_table's "schema.table"
    var isLoading = false
    var isSaving = false
    var errorMessage: String?

    private let repo: CrmDataProviding
    init(service: Service, repo: CrmDataProviding = CrmRepository()) {
        self.service = service
        self.repo = repo
    }

    private func key(_ t: ServiceTableInfo) -> String { "\(t.sourceSchema).\(t.sourceTable)" }

    func load() async {
        guard let acc = service.supabaseAccountId, let ref = service.supabaseProjectRef else {
            errorMessage = "이 서비스에 연결된 Supabase 계정/프로젝트가 없습니다."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            async let tablesCall = repo.listTables(supabaseAccountId: acc, projectRef: ref)
            async let currentCall = repo.fetchServiceTables(serviceId: service.id)
            let (tables, cur) = try await (tablesCall, currentCall)
            projectTables = tables
            current = cur
            userTableKey = cur.first(where: { $0.isUserTable }).map(key)
            selected = Set(cur.map(key))
            errorMessage = nil
        } catch {
            let raw = error.localizedDescription
            if raw.contains("refresh") || raw.contains("No such refresh token")
                || raw.contains("401") || raw.contains("403") || raw.contains("reauth") {
                errorMessage = "Supabase 연결이 만료됐어요. 연동 탭의 연결된 데이터 소스에서 Supabase 계정을 삭제(🗑)하고 다시 연결한 뒤 시도하세요. (동기화된 유저 데이터는 보존됩니다.)"
            } else {
                errorMessage = "테이블 목록을 불러오지 못했습니다: \(raw)"
            }
        }
    }

    func isUserTable(_ t: TableInfo) -> Bool { t.id == userTableKey }

    func toggle(_ t: TableInfo) {
        guard !isUserTable(t) else { return }   // the user table can't be removed here
        if selected.contains(t.id) { selected.remove(t.id) } else { selected.insert(t.id) }
    }

    var changeCount: Int {
        let currentKeys = Set(current.map(key))
        return selected.symmetricDifference(currentKeys).count
    }

    // Applies the diff (insert new related tables, delete removed ones). Returns
    // true on success so the caller can trigger a re-sync and dismiss.
    func save() async -> Bool {
        let byKey = Dictionary(uniqueKeysWithValues: current.map { (key($0), $0) })
        let currentKeys = Set(byKey.keys)
        let toAdd = selected.subtracting(currentKeys)
        let toRemove = currentKeys.subtracting(selected)
        isSaving = true
        defer { isSaving = false }
        do {
            for k in toRemove {
                guard let row = byKey[k], !row.isUserTable else { continue }
                try await repo.removeServiceTable(id: row.id)
            }
            for k in toAdd {
                guard let t = projectTables.first(where: { $0.id == k }) else { continue }
                try await repo.addRelatedTable(serviceId: service.id, schema: t.schema, table: t.table)
            }
            return true
        } catch {
            errorMessage = "저장 실패: \(error.localizedDescription)"
            // A partial diff may have applied; re-sync `current`/`selected` to the
            // actual DB state so the UI doesn't disagree with what was saved.
            if let cur = try? await repo.fetchServiceTables(serviceId: service.id) {
                current = cur
                userTableKey = cur.first(where: { $0.isUserTable }).map(key)
                selected = Set(cur.map(key))
            }
            return false
        }
    }
}

// Sheet to edit which Supabase tables this service imports. The user table stays
// fixed; other project tables can be toggled on/off. Saving re-syncs the service.
struct ImportedTablesEditor: View {
    @State private var model: ImportedTablesEditorModel
    @Environment(\.dismiss) private var dismiss
    let onSaved: () -> Void

    init(service: Service, onSaved: @escaping () -> Void) {
        _model = State(initialValue: ImportedTablesEditorModel(service: service))
        self.onSaved = onSaved
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Palette.hairline)
            content
            Divider().overlay(Palette.hairline)
            footer
        }
        .frame(width: 460, height: 560)
        .background(Palette.canvas)
        .task { await model.load() }
    }

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "tablecells.badge.ellipsis").foregroundStyle(Palette.accentBlue)
            VStack(alignment: .leading, spacing: 2) {
                Text("가져올 테이블").font(Typography.cardTitle).foregroundStyle(Palette.ink)
                Text(model.service.supabaseProjectName ?? model.service.name)
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            Spacer()
            if model.isLoading || model.isSaving { ProgressView().controlSize(.small) }
        }
        .padding(Spacing.lg)
    }

    @ViewBuilder private var content: some View {
        if let e = model.errorMessage, model.projectTables.isEmpty {
            VStack(spacing: Spacing.sm) {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 24)).foregroundStyle(Palette.accentYellow)
                Text(e).font(Typography.caption).foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            .padding(Spacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.isLoading && model.projectTables.isEmpty {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("유저 테이블은 고정이며, 추가로 동기화할 테이블을 선택하세요.")
                        .font(Typography.caption).foregroundStyle(Palette.muted)
                        .padding(.bottom, Spacing.xs)
                    ForEach(model.projectTables) { t in tableRow(t) }
                }
                .padding(Spacing.lg)
            }
            .scrollContentBackground(.hidden)
        }
    }

    private func tableRow(_ t: TableInfo) -> some View {
        let locked = model.isUserTable(t)
        let on = model.selected.contains(t.id)
        return Button { model.toggle(t) } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15))
                    .foregroundStyle(locked ? Palette.ash : (on ? Palette.accentBlue : Palette.muted))
                VStack(alignment: .leading, spacing: 1) {
                    Text(t.table).font(Typography.body).foregroundStyle(Palette.ink).lineLimit(1)
                    if t.schema != "public" {
                        Text(t.schema).font(.system(size: 11)).foregroundStyle(Palette.muted)
                    }
                }
                Spacer(minLength: Spacing.sm)
                if locked {
                    Text("유저 테이블").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted)
                }
            }
            .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(on ? Palette.accentBlue.opacity(0.08) : Palette.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.button))
            .overlay(RoundedRectangle(cornerRadius: Radius.button).stroke(Palette.hairline))
        }
        .buttonStyle(.plain)
        .disabled(locked || model.isSaving)
    }

    private var footer: some View {
        HStack(spacing: Spacing.sm) {
            if let e = model.errorMessage, !model.projectTables.isEmpty {
                Text(e).font(Typography.caption).foregroundStyle(Palette.accentRed).lineLimit(2)
            }
            Spacer()
            Button("취소") { dismiss() }
                .buttonStyle(.plain).foregroundStyle(Palette.muted)
            Button {
                Task {
                    if await model.save() {
                        onSaved()
                        dismiss()
                    }
                }
            } label: {
                Text(model.isSaving ? "저장 중…" : (model.changeCount > 0 ? "저장 후 동기화 (\(model.changeCount))" : "저장"))
                    .font(Typography.body).foregroundStyle(Palette.ctaText)
                    .padding(.horizontal, Spacing.lg).frame(height: 36)
                    .background(Palette.ctaFill)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.button))
            }
            .buttonStyle(.plain)
            .disabled(model.isSaving || model.changeCount == 0)
        }
        .padding(Spacing.lg)
    }
}
