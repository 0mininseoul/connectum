# Connectum Phase 1b-ii — User Detail: AI Regenerate + Channel Records

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development / executing-plans. Checkbox steps.

**Goal:** Complete the user detail page's interactivity: (1) an "AI 총평 재생성" button that calls the `summarize-user` Edge Function and refreshes the summary; (2) a channel-records section to log and view manual contact records (email/kakao/sms/interview/memo) with a date, persisted as `page_block` rows of type `channel_record`.

**Architecture:** Extend `CrmRepository` with `regenerateSummary` (via `functions.invoke`) and `fetchChannelRecords`/`addChannelRecord` (page_block CRUD). A `ChannelRecord` model decodes `page_block.id` + `content`. `UserDetailViewModel` gains regenerate/records state. `UserDetailView` adds a regenerate button to the AI card and a records section with an add form.

**Tech Stack:** SwiftUI (macOS 14), supabase-swift (`functions.invoke`, `from().insert`). Builds on Plan 5 (user detail) + Plan 7 (summarize-user function).

**Prerequisites:** Plans 0-7 merged. Branch `phase1b-user-records`.

---

## File Structure
```
apps/Connectum/Connectum/
├─ Models/CrmModels.swift            # ADD ChannelRecord + PageBlockRow
├─ Data/CrmRepository.swift          # ADD regenerateSummary, fetchChannelRecords, addChannelRecord
└─ Features/OperationalDB/
   ├─ UserDetailViewModel.swift      # ADD regenerate/records/addRecord
   └─ UserDetailView.swift           # ADD regenerate button + records section
apps/Connectum/ConnectumTests/
└─ CrmModelsTests.swift              # ADD ChannelRecord decode test
```

---

## Task 1: Models (TDD)

**Files:** Modify `apps/Connectum/Connectum/Models/CrmModels.swift`, `apps/Connectum/ConnectumTests/CrmModelsTests.swift`

- [ ] **Step 1: add failing test** — append to `CrmModelsTests.swift` (inside the class):
```swift
    func testDecodeChannelRecordRow() throws {
        let json = """
        {"id":"33333333-3333-3333-3333-333333333333",
         "content":{"channel":"email","occurred_at":"2026-06-01","body":"온보딩 안내 메일 발송"}}
        """.data(using: .utf8)!
        let row = try JSONDecoder().decode(PageBlockRow.self, from: json)
        let rec = row.asChannelRecord
        XCTAssertEqual(rec.id, "33333333-3333-3333-3333-333333333333")
        XCTAssertEqual(rec.channel, "email")
        XCTAssertEqual(rec.occurredAt, "2026-06-01")
        XCTAssertEqual(rec.body, "온보딩 안내 메일 발송")
    }
```

- [ ] **Step 2: run (FAIL)** — `cd apps/Connectum && xcodegen generate && cd - && xcodebuild -project apps/Connectum/Connectum.xcodeproj -scheme Connectum -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO`

- [ ] **Step 3: implement** — append to `CrmModels.swift`:
```swift
struct ChannelRecord: Identifiable, Hashable {
    let id: String
    let channel: String
    let occurredAt: String?
    let body: String
}

// page_block row whose `content` jsonb holds a channel record.
struct PageBlockRow: Codable, Identifiable, Hashable {
    let id: String
    let content: Content
    struct Content: Codable, Hashable {
        let channel: String?
        let occurredAt: String?
        let body: String?
        enum CodingKeys: String, CodingKey { case channel, body, occurredAt = "occurred_at" }
    }
    var asChannelRecord: ChannelRecord {
        ChannelRecord(id: id, channel: content.channel ?? "memo", occurredAt: content.occurredAt, body: content.body ?? "")
    }
}
```

- [ ] **Step 4: run (PASS)**. **Step 5: commit**
```bash
git add apps/Connectum/Connectum/Models/CrmModels.swift apps/Connectum/ConnectumTests/CrmModelsTests.swift
git commit -m "feat(app): ChannelRecord + PageBlockRow models"
```

---

## Task 2: Repository methods

**Files:** Modify `apps/Connectum/Connectum/Data/CrmRepository.swift`

- [ ] **Step 1: extend the protocol + struct** — add to `CrmDataProviding`:
```swift
    func regenerateSummary(crmUserId: String) async throws -> String
    func fetchChannelRecords(crmUserId: String) async throws -> [ChannelRecord]
    func addChannelRecord(crmUserId: String, channel: String, occurredAt: String, body: String) async throws
```
And implement in `CrmRepository`:
```swift
    func regenerateSummary(crmUserId: String) async throws -> String {
        struct Resp: Decodable { let ai_summary: String? }
        let resp: Resp = try await client.functions.invoke(
            "summarize-user",
            options: FunctionInvokeOptions(body: ["crm_user_id": crmUserId, "force": true])
        )
        return resp.ai_summary ?? ""
    }
    func fetchChannelRecords(crmUserId: String) async throws -> [ChannelRecord] {
        let rows: [PageBlockRow] = try await client.from("page_block")
            .select("id,content")
            .eq("crm_user_id", value: crmUserId)
            .eq("type", value: "channel_record")
            .order("position", ascending: false)
            .execute().value
        return rows.map { $0.asChannelRecord }
    }
    func addChannelRecord(crmUserId: String, channel: String, occurredAt: String, body: String) async throws {
        struct NewBlock: Encodable {
            let crm_user_id: String; let type: String; let position: Double
            let content: [String: String]
        }
        let block = NewBlock(
            crm_user_id: crmUserId, type: "channel_record", position: Date().timeIntervalSince1970,
            content: ["channel": channel, "occurred_at": occurredAt, "body": body])
        try await client.from("page_block").insert(block).execute()
    }
```

- [ ] **Step 2: build** — `cd apps/Connectum && xcodegen generate && cd - && xcodebuild ... build CODE_SIGNING_ALLOWED=NO` → SUCCEEDED. (If `FunctionInvokeOptions` body needs a concrete Encodable, wrap `["crm_user_id": crmUserId]` works since `[String: String]`/`[String: AnyJSON]` is Encodable; if the compiler complains about the mixed `["crm_user_id": crmUserId, "force": true]` types, change to a struct `Body: Encodable { let crm_user_id: String; let force: Bool }`.)

- [ ] **Step 3: commit**
```bash
git add apps/Connectum/Connectum/Data/CrmRepository.swift
git commit -m "feat(app): repository regenerateSummary + channel records CRUD"
```

---

## Task 3: View model

**Files:** Modify `apps/Connectum/Connectum/Features/OperationalDB/UserDetailViewModel.swift`

- [ ] **Step 1: extend** — add state + methods:
```swift
    var records: [ChannelRecord] = []
    var aiSummary: String?
    var isRegenerating = false

    // in init, after contactStatus assignment, add:  self.aiSummary = user.aiSummary
```
and methods:
```swift
    func loadRecords() async {
        do { records = try await repo.fetchChannelRecords(crmUserId: user.id) }
        catch { errorMessage = String(describing: error) }
    }
    func regenerate() async {
        isRegenerating = true; defer { isRegenerating = false }
        do { aiSummary = try await repo.regenerateSummary(crmUserId: user.id) }
        catch { errorMessage = String(describing: error) }
    }
    func addRecord(channel: String, occurredAt: String, body: String) async {
        do {
            try await repo.addChannelRecord(crmUserId: user.id, channel: channel, occurredAt: occurredAt, body: body)
            await loadRecords()
        } catch { errorMessage = String(describing: error) }
    }
```
Update the `init` to set `self.aiSummary = user.aiSummary`.

- [ ] **Step 2: build** → SUCCEEDED. **Step 3: commit**
```bash
git add apps/Connectum/Connectum/Features/OperationalDB/UserDetailViewModel.swift
git commit -m "feat(app): user detail VM regenerate + records"
```

---

## Task 4: View (regenerate button + records section)

**Files:** Modify `apps/Connectum/Connectum/Features/OperationalDB/UserDetailView.swift`

- [ ] **Step 1: AI card with regenerate + records section** — replace the AI-summary `card(...)` call with:
```swift
                card(title: "AI 총평") {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text(vm.aiSummary ?? "아직 생성되지 않았습니다.")
                            .font(Typography.body).foregroundStyle(vm.aiSummary == nil ? Palette.muted : Palette.body)
                        Button { Task { await vm.regenerate() } } label: {
                            Text(vm.isRegenerating ? "생성 중…" : "재생성")
                                .font(Typography.caption).foregroundStyle(Palette.ink)
                                .padding(.horizontal, Spacing.md).frame(height: 28)
                                .background(Palette.surfaceElevated).clipShape(Capsule())
                        }.buttonStyle(.plain).disabled(vm.isRegenerating)
                    }
                }
```
and add a records section before the "최근 이벤트" card:
```swift
                RecordsSection(vm: vm)
```
Add the `RecordsSection` view at file scope (below `UserDetailView`):
```swift
private struct RecordsSection: View {
    @Bindable var vm: UserDetailViewModel
    @State private var channel = "email"
    @State private var date = ""
    @State private var body = ""
    private let channels = ["email", "kakao", "sms", "interview", "memo"]

    var content: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ForEach(vm.records) { r in
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Text(r.channel).font(Typography.caption).foregroundStyle(Palette.accentBlue)
                        .frame(width: 64, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.body).font(Typography.body).foregroundStyle(Palette.body)
                        Text(r.occurredAt ?? "").font(Typography.caption).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                }
            }
            if vm.records.isEmpty { Text("기록 없음").font(Typography.caption).foregroundStyle(Palette.muted) }
            Divider().overlay(Palette.hairline)
            HStack(spacing: Spacing.sm) {
                Picker("", selection: $channel) { ForEach(channels, id: \.self) { Text($0).tag($0) } }
                    .labelsHidden().frame(width: 110)
                TextField("날짜 (예: 2026-06-08)", text: $date).textFieldStyle(.plain)
                    .padding(Spacing.xs).background(Palette.surfaceElevated).clipShape(RoundedRectangle(cornerRadius: Radius.button)).frame(width: 150)
            }
            TextField("내용", text: $body, axis: .vertical).textFieldStyle(.plain).lineLimit(2...5)
                .padding(Spacing.sm).background(Palette.surfaceElevated).clipShape(RoundedRectangle(cornerRadius: Radius.button))
            Button {
                let b = body; let d = date; let c = channel
                Task { await vm.addRecord(channel: c, occurredAt: d, body: b); body = ""; date = "" }
            } label: {
                Text("기록 추가").font(Typography.caption).foregroundStyle(Palette.ctaText)
                    .padding(.horizontal, Spacing.md).frame(height: 28).background(Palette.ctaFill).clipShape(Capsule())
            }.buttonStyle(.plain).disabled(body.isEmpty)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("기록 (이메일/카톡/문자/인터뷰/메모)").font(Typography.caption).foregroundStyle(Palette.muted)
            content
        }
        .padding(Spacing.lg).frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceCard).clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Palette.hairline))
        .task { await vm.loadRecords() }
    }
}
```

- [ ] **Step 2: build + test** — `cd apps/Connectum && xcodegen generate && cd - && xcodebuild ... test CODE_SIGNING_ALLOWED=NO` → SUCCEEDED, all tests pass (12 prior + 1 ChannelRecord = 13).

- [ ] **Step 3: commit**
```bash
git add apps/Connectum/Connectum/Features/OperationalDB/UserDetailView.swift
git commit -m "feat(app): user detail AI regenerate button + channel records section"
```

---

## Done — Definition of Done
- [ ] `xcodebuild test` passes (13 tests).
- [ ] Controller live-runs (or verifies the data path): adding a channel record inserts a `page_block` row; the regenerate button calls `summarize-user` (force) and updates the summary.

## Self-Review Notes (author)
- **Spec coverage:** §8.2 channel records (email/kakao/sms/interview/memo) + §8.5 AI regenerate. History tab (image+memo) and the full free-block editor remain follow-ups.
- **Placeholders:** None. Date is a free-text field per spec ("날짜도 직접 입력").
- **Type consistency:** `ChannelRecord`/`PageBlockRow` match the test + repository; `regenerateSummary`/`fetchChannelRecords`/`addChannelRecord` match the protocol, VM, and view. `page_block` columns (`crm_user_id`, `type`, `position`, `content`) match Phase 0 `0001`.
```
