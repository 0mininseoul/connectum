# Connectum Phase 1b-i — Operational DB UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the placeholder authenticated shell with the real operational DB UI — a 3-pane macOS view (services sidebar → users list → user detail) that reads the synced `crm_user`/`crm_user_event` data from Connectum's Supabase via `supabase-swift`, shows each user's synced profile (Amplitude OS/device/geo) + AI summary slot + recent events, and lets the team toggle each user's contact status (persisted).

**Architecture:** A `CrmRepository` wraps `supabase-swift` reads/writes (services, users, events, contact-status update). `@Observable` view models (`OperationalDBViewModel`, `UserDetailViewModel`) hold state. SwiftUI views (`OperationalDBView` with `NavigationSplitView`, `UserDetailView`) render Raycast-styled. Codable models decode the relevant `crm_user` columns incl. the `amplitude_profile` jsonb. RLS allows any authenticated team member, so the logged-in session reads everything.

**Tech Stack:** SwiftUI (macOS 14), supabase-swift 2.x, `@Observable`. Builds on Phase 0 app (auth, design tokens, Paperlogy) and the populated local DB (357 users + events).

**Prerequisites:** Phases 0 + Plans 2-4 merged. Local stack running with data (357 `crm_user`, some `crm_user_event`). New branch: `git checkout -b phase1b-operational-db-ui`. The app reads `SUPABASE_URL`/`SUPABASE_ANON_KEY` from the run scheme env (local defaults `http://127.0.0.1:54321` + local anon key from `supabase status`).

---

## File Structure

```
apps/Connectum/Connectum/
├─ Models/
│  └─ CrmModels.swift            # Service, CrmUser, AmplitudeProfile, CrmUserEvent (Codable)
├─ Data/
│  └─ CrmRepository.swift        # supabase-swift queries + contact-status update
├─ Features/OperationalDB/
│  ├─ OperationalDBViewModel.swift
│  ├─ OperationalDBView.swift    # NavigationSplitView: services | users | detail
│  ├─ UserDetailViewModel.swift
│  └─ UserDetailView.swift
└─ App/RootView.swift            # MODIFY: authenticated → OperationalDBView
apps/Connectum/ConnectumTests/
└─ CrmModelsTests.swift          # decode sample JSON
```

---

## Task 1: Codable models

**Files:**
- Create: `apps/Connectum/Connectum/Models/CrmModels.swift`
- Test: `apps/Connectum/ConnectumTests/CrmModelsTests.swift`

- [ ] **Step 1: Write the failing test**

`apps/Connectum/ConnectumTests/CrmModelsTests.swift`:
```swift
import XCTest
@testable import Connectum

final class CrmModelsTests: XCTestCase {
    func testDecodeCrmUserWithAmplitudeProfile() throws {
        let json = """
        {"id":"11111111-1111-1111-1111-111111111111","source_user_id":"u1","email":"a@b.com",
         "display_name":null,"contact_status":"not_contacted",
         "amplitude_profile":{"os":"Chrome Mobile","country":"South Korea","region":"Seoul","device_family":"Android","last_event_time":"2026-06-07T12:00:00Z"},
         "ai_summary":null,"last_synced_at":null,"created_at":"2026-01-01T00:00:00Z"}
        """.data(using: .utf8)!
        let u = try JSONDecoder().decode(CrmUser.self, from: json)
        XCTAssertEqual(u.email, "a@b.com")
        XCTAssertEqual(u.contactStatus, "not_contacted")
        XCTAssertEqual(u.amplitudeProfile?.os, "Chrome Mobile")
        XCTAssertEqual(u.amplitudeProfile?.country, "South Korea")
        XCTAssertNil(u.aiSummary)
    }

    func testDecodeCrmUserWithEmptyProfile() throws {
        let json = """
        {"id":"22222222-2222-2222-2222-222222222222","source_user_id":"u2","email":null,
         "display_name":null,"contact_status":"contacted","amplitude_profile":{},
         "ai_summary":"3 line summary","last_synced_at":null,"created_at":"2026-01-01T00:00:00Z"}
        """.data(using: .utf8)!
        let u = try JSONDecoder().decode(CrmUser.self, from: json)
        XCTAssertEqual(u.contactStatus, "contacted")
        XCTAssertNil(u.amplitudeProfile?.os)
        XCTAssertEqual(u.aiSummary, "3 line summary")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild -project apps/Connectum/Connectum.xcodeproj -scheme Connectum -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO`
Expected: FAIL — `CrmUser` undefined. (Regenerate project first if the new test file isn't picked up: `cd apps/Connectum && xcodegen generate && cd -`.)

- [ ] **Step 3: Implement the models**

`apps/Connectum/Connectum/Models/CrmModels.swift`:
```swift
import Foundation

struct Service: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let supabaseProjectRef: String?
    enum CodingKeys: String, CodingKey { case id, name, supabaseProjectRef = "supabase_project_ref" }
}

struct AmplitudeProfile: Codable, Hashable {
    let os: String?
    let platform: String?
    let deviceFamily: String?
    let deviceType: String?
    let country: String?
    let region: String?
    let city: String?
    let lastEventTime: String?
    enum CodingKeys: String, CodingKey {
        case os, platform, country, region, city
        case deviceFamily = "device_family", deviceType = "device_type", lastEventTime = "last_event_time"
    }
}

struct CrmUser: Codable, Identifiable, Hashable {
    let id: String
    let sourceUserId: String
    let email: String?
    let displayName: String?
    let contactStatus: String
    let amplitudeProfile: AmplitudeProfile?
    let aiSummary: String?
    let lastSyncedAt: String?
    let createdAt: String?
    enum CodingKeys: String, CodingKey {
        case id, email
        case sourceUserId = "source_user_id"
        case displayName = "display_name"
        case contactStatus = "contact_status"
        case amplitudeProfile = "amplitude_profile"
        case aiSummary = "ai_summary"
        case lastSyncedAt = "last_synced_at"
        case createdAt = "created_at"
    }
}

struct CrmUserEvent: Codable, Identifiable, Hashable {
    let id: Int64
    let eventType: String
    let eventTime: String
    let os: String?
    let browser: String?
    let platform: String?
    enum CodingKeys: String, CodingKey {
        case id, os, browser, platform
        case eventType = "event_type", eventTime = "event_time"
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd apps/Connectum && xcodegen generate && cd - && xcodebuild -project apps/Connectum/Connectum.xcodeproj -scheme Connectum -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO`
Expected: PASS — `CrmModelsTests` green (plus existing 10).

- [ ] **Step 5: Commit**

```bash
git add apps/Connectum/Connectum/Models apps/Connectum/ConnectumTests/CrmModelsTests.swift
git commit -m "feat(app): Codable models for crm_user/events/services"
```

---

## Task 2: CrmRepository (supabase-swift)

**Files:**
- Create: `apps/Connectum/Connectum/Data/CrmRepository.swift`

- [ ] **Step 1: Implement the repository**

`apps/Connectum/Connectum/Data/CrmRepository.swift`:
```swift
import Foundation
import Supabase

// Reads/writes the operational DB via supabase-swift. RLS lets any authenticated
// team member access everything, so the logged-in session is sufficient.
protocol CrmDataProviding {
    func fetchServices() async throws -> [Service]
    func fetchUsers(serviceId: String) async throws -> [CrmUser]
    func fetchEvents(crmUserId: String, limit: Int) async throws -> [CrmUserEvent]
    func setContactStatus(crmUserId: String, status: String) async throws
}

struct CrmRepository: CrmDataProviding {
    let client: SupabaseClient
    init(client: SupabaseClient = SupabaseClientProvider.shared) { self.client = client }

    func fetchServices() async throws -> [Service] {
        try await client.from("service")
            .select("id,name,supabase_project_ref").order("name").execute().value
    }

    func fetchUsers(serviceId: String) async throws -> [CrmUser] {
        try await client.from("crm_user")
            .select("id,source_user_id,email,display_name,contact_status,amplitude_profile,ai_summary,last_synced_at,created_at")
            .eq("service_id", value: serviceId)
            .order("created_at", ascending: false)
            .limit(1000)
            .execute().value
    }

    func fetchEvents(crmUserId: String, limit: Int = 50) async throws -> [CrmUserEvent] {
        try await client.from("crm_user_event")
            .select("id,event_type,event_time,os,browser,platform")
            .eq("crm_user_id", value: crmUserId)
            .order("event_time", ascending: false)
            .limit(limit)
            .execute().value
    }

    func setContactStatus(crmUserId: String, status: String) async throws {
        try await client.from("crm_user")
            .update(["contact_status": status])
            .eq("id", value: crmUserId)
            .execute()
    }
}
```

- [ ] **Step 2: Type-check via build**

Run: `cd apps/Connectum && xcodegen generate && cd - && xcodebuild -project apps/Connectum/Connectum.xcodeproj -scheme Connectum -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add apps/Connectum/Connectum/Data/CrmRepository.swift
git commit -m "feat(app): CrmRepository over supabase-swift"
```

---

## Task 3: View models

**Files:**
- Create: `apps/Connectum/Connectum/Features/OperationalDB/OperationalDBViewModel.swift`
- Create: `apps/Connectum/Connectum/Features/OperationalDB/UserDetailViewModel.swift`

- [ ] **Step 1: Implement OperationalDBViewModel**

`apps/Connectum/Connectum/Features/OperationalDB/OperationalDBViewModel.swift`:
```swift
import Foundation
import Observation

@MainActor
@Observable
final class OperationalDBViewModel {
    var services: [Service] = []
    var selectedServiceId: String?
    var users: [CrmUser] = []
    var search: String = ""
    var isLoading = false
    var errorMessage: String?

    private let repo: CrmDataProviding
    init(repo: CrmDataProviding = CrmRepository()) { self.repo = repo }

    var filteredUsers: [CrmUser] {
        guard !search.isEmpty else { return users }
        let q = search.lowercased()
        return users.filter { ($0.email ?? "").lowercased().contains(q) || $0.sourceUserId.lowercased().contains(q) }
    }

    func loadServices() async {
        isLoading = true; defer { isLoading = false }
        do {
            services = try await repo.fetchServices()
            if selectedServiceId == nil { selectedServiceId = services.first?.id }
            if let sid = selectedServiceId { await loadUsers(serviceId: sid) }
        } catch { errorMessage = String(describing: error) }
    }

    func loadUsers(serviceId: String) async {
        isLoading = true; defer { isLoading = false }
        do { users = try await repo.fetchUsers(serviceId: serviceId) }
        catch { errorMessage = String(describing: error) }
    }

    func selectService(_ id: String) async {
        selectedServiceId = id
        await loadUsers(serviceId: id)
    }
}
```

- [ ] **Step 2: Implement UserDetailViewModel**

`apps/Connectum/Connectum/Features/OperationalDB/UserDetailViewModel.swift`:
```swift
import Foundation
import Observation

@MainActor
@Observable
final class UserDetailViewModel {
    var events: [CrmUserEvent] = []
    var contactStatus: String
    var isBusy = false
    var errorMessage: String?

    let user: CrmUser
    private let repo: CrmDataProviding
    init(user: CrmUser, repo: CrmDataProviding = CrmRepository()) {
        self.user = user; self.contactStatus = user.contactStatus; self.repo = repo
    }

    func loadEvents() async {
        do { events = try await repo.fetchEvents(crmUserId: user.id, limit: 50) }
        catch { errorMessage = String(describing: error) }
    }

    func toggleContacted() async {
        let next = contactStatus == "contacted" ? "not_contacted" : "contacted"
        isBusy = true; defer { isBusy = false }
        do { try await repo.setContactStatus(crmUserId: user.id, status: next); contactStatus = next }
        catch { errorMessage = String(describing: error) }
    }
}
```

- [ ] **Step 3: Type-check via build**

Run: `cd apps/Connectum && xcodegen generate && cd - && xcodebuild -project apps/Connectum/Connectum.xcodeproj -scheme Connectum -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add apps/Connectum/Connectum/Features/OperationalDB/OperationalDBViewModel.swift apps/Connectum/Connectum/Features/OperationalDB/UserDetailViewModel.swift
git commit -m "feat(app): operational DB + user detail view models"
```

---

## Task 4: Views + wire into RootView

**Files:**
- Create: `apps/Connectum/Connectum/Features/OperationalDB/OperationalDBView.swift`
- Create: `apps/Connectum/Connectum/Features/OperationalDB/UserDetailView.swift`
- Modify: `apps/Connectum/Connectum/App/RootView.swift`

- [ ] **Step 1: Implement OperationalDBView**

`apps/Connectum/Connectum/Features/OperationalDB/OperationalDBView.swift`:
```swift
import SwiftUI

struct OperationalDBView: View {
    @State private var vm = OperationalDBViewModel()
    @State private var selectedUser: CrmUser?

    var body: some View {
        NavigationSplitView {
            // Services sidebar
            List(vm.services, selection: Binding(
                get: { vm.selectedServiceId },
                set: { if let id = $0 { Task { await vm.selectService(id); selectedUser = nil } } })
            ) { svc in
                Text(svc.name).font(Typography.body).foregroundStyle(Palette.ink).tag(svc.id)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            .scrollContentBackground(.hidden)
            .background(Palette.surface)
        } content: {
            // Users list
            VStack(spacing: 0) {
                TextField("이메일/ID 검색", text: $vm.search)
                    .textFieldStyle(.plain).padding(Spacing.sm)
                    .background(Palette.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                    .padding(Spacing.sm)
                List(vm.filteredUsers, selection: $selectedUser) { u in
                    HStack(spacing: Spacing.sm) {
                        Circle().fill(u.contactStatus == "contacted" ? Palette.accentGreen : Palette.ash)
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(u.email ?? u.sourceUserId).font(Typography.body).foregroundStyle(Palette.ink)
                            if let p = u.amplitudeProfile, let os = p.os {
                                Text("\(os) · \(p.country ?? "")").font(Typography.caption).foregroundStyle(Palette.muted)
                            }
                        }
                        Spacer()
                    }.tag(u)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationSplitViewColumnWidth(min: 280, ideal: 340)
            .background(Palette.canvas)
            .overlay { if vm.isLoading { ProgressView() } }
        } detail: {
            if let u = selectedUser { UserDetailView(user: u) }
            else { Text("유저를 선택하세요").font(Typography.body).foregroundStyle(Palette.muted) }
        }
        .task { await vm.loadServices() }
    }
}
```

- [ ] **Step 2: Implement UserDetailView**

`apps/Connectum/Connectum/Features/OperationalDB/UserDetailView.swift`:
```swift
import SwiftUI

struct UserDetailView: View {
    @State private var vm: UserDetailViewModel
    init(user: CrmUser) { _vm = State(initialValue: UserDetailViewModel(user: user)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                // Header
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(vm.user.email ?? vm.user.sourceUserId).font(Typography.cardTitle).foregroundStyle(Palette.ink)
                    Text(vm.user.sourceUserId).font(Typography.caption).foregroundStyle(Palette.muted)
                }
                // Contact toggle
                Button { Task { await vm.toggleContacted() } } label: {
                    Text(vm.contactStatus == "contacted" ? "✓ 컨택함" : "컨택 안함")
                        .font(Typography.body).foregroundStyle(vm.contactStatus == "contacted" ? Palette.ctaText : Palette.ink)
                        .padding(.horizontal, Spacing.lg).frame(height: 36)
                        .background(vm.contactStatus == "contacted" ? Palette.ctaFill : Palette.surfaceElevated)
                        .clipShape(Capsule())
                }.buttonStyle(.plain).disabled(vm.isBusy)

                // AI summary
                card(title: "AI 총평") {
                    Text(vm.user.aiSummary ?? "아직 생성되지 않았습니다.")
                        .font(Typography.body).foregroundStyle(vm.user.aiSummary == nil ? Palette.muted : Palette.body)
                }
                // Profile
                card(title: "프로필") {
                    let p = vm.user.amplitudeProfile
                    profileRow("OS", p?.os); profileRow("디바이스", p?.deviceFamily ?? p?.deviceType)
                    profileRow("지역", [p?.city, p?.region, p?.country].compactMap { $0 }.joined(separator: ", "))
                    profileRow("최근 활동", p?.lastEventTime)
                }
                // Recent events
                card(title: "최근 이벤트") {
                    if vm.events.isEmpty { Text("없음").font(Typography.caption).foregroundStyle(Palette.muted) }
                    else {
                        ForEach(vm.events) { e in
                            HStack {
                                Text(e.eventType).font(Typography.caption).foregroundStyle(Palette.body)
                                Spacer()
                                Text(e.eventTime).font(Typography.caption).foregroundStyle(Palette.muted)
                            }
                        }
                    }
                }
            }
            .padding(Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.canvas)
        .task { await vm.loadEvents() }
    }

    @ViewBuilder private func card<Content: View>(title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title).font(Typography.caption).foregroundStyle(Palette.muted)
            content()
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Palette.hairline))
    }

    @ViewBuilder private func profileRow(_ label: String, _ value: String?) -> some View {
        HStack {
            Text(label).font(Typography.caption).foregroundStyle(Palette.muted).frame(width: 80, alignment: .leading)
            Text(value?.isEmpty == false ? value! : "-").font(Typography.body).foregroundStyle(Palette.body)
            Spacer()
        }
    }
}
```

- [ ] **Step 3: Wire into RootView (replace AuthenticatedShell body)**

In `apps/Connectum/Connectum/App/RootView.swift`, replace the `AuthenticatedShell` struct with:
```swift
struct AuthenticatedShell: View {
    var body: some View {
        OperationalDBView()
            .frame(minWidth: 1000, minHeight: 640)
    }
}
```

- [ ] **Step 4: Build + test**

Run: `cd apps/Connectum && xcodegen generate && cd - && xcodebuild -project apps/Connectum/Connectum.xcodeproj -scheme Connectum -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO`
Expected: `** BUILD SUCCEEDED **` and all tests pass (10 prior + CrmModels 2 = 12).

- [ ] **Step 5: Commit**

```bash
git add apps/Connectum/Connectum/Features/OperationalDB apps/Connectum/Connectum/App/RootView.swift
git commit -m "feat(app): operational DB UI (services/users/detail) + contact toggle"
```

---

## Done — Definition of Done

- [ ] `xcodebuild ... test` passes (12 tests: 10 prior + 2 model decode).
- [ ] Controller live-runs the app against local Supabase (`SUPABASE_URL=http://127.0.0.1:54321`, `SUPABASE_ANON_KEY=<local>`), signs in (`a@b.com`/`secret`), sees the service in the sidebar, the ~357 users in the list (email + OS/country where present), opens a user, and toggles contact status (persists — re-open shows the new state; verify via `select contact_status from crm_user where id=...`).
- [ ] Results recorded.

---

## Self-Review Notes (author)

- **Spec coverage:** Implements spec §8.1 (operational DB list, service-scoped) + §8.2 header/profile/contact-toggle + AI-summary slot + recent events. Deferred to later plans: the Notion-style free block editor + channel records + History tab (§8.2 body/tabs), custom views/dashboard (§8.3-8.4), and the Vertex AI summary generation (blocked on GCP creds; the UI already renders `ai_summary` when present).
- **Placeholders:** None in code. The AI-summary card intentionally shows an empty-state string until Vertex is wired — that is product behavior, not a plan placeholder.
- **Type consistency:** `CrmDataProviding` methods match across `CrmRepository` and both view models. Model `CodingKeys` map snake_case columns selected in the repository queries. `OperationalDBView` selection bindings use `Service.id` (String) and `CrmUser` (Hashable/Identifiable) consistently. Column/table names (`crm_user`, `crm_user_event`, `service`, `contact_status`, `amplitude_profile`) match the live schema.
- **Note:** `JSONDecoder()` in tests uses explicit `CodingKeys` (not `.convertFromSnakeCase`) so the same models decode identically whether supabase-swift applies a key strategy or not.
```
