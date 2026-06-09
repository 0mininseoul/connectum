# KPI Dashboard Customization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the Connections tab resize clipping, remove the sidebar bottom separator, and add a customizable KPI dashboard where users can add Gemini-confirmed KPI cards, reorder/delete cards, and click each card to see its date chart.

**Architecture:** Keep the dashboard feature local-first: default and custom KPI definitions are stored per service in `UserDefaults`, while existing server metrics continue to come from `CrmRepository.fetchMetrics`. A new Supabase Edge Function asks Vertex Gemini to confirm the user-entered KPI calculation definition; confirming adds the KPI immediately and starts non-blocking chart preparation. Connections layout is fixed by replacing fixed-width horizontal composition with a responsive layout that stacks before clipping.

**Tech Stack:** macOS SwiftUI, Swift Charts, Observation, Supabase Swift Functions, Supabase Edge Functions on Deno, Vertex Gemini helper already present in `supabase/functions/_shared/vertex.ts`.

---

### Task 1: Add Dashboard KPI Models, Store, And Chart Builder

**Files:**
- Create: `apps/Connectum/Connectum/Features/Dashboard/DashboardKPIModels.swift`
- Test: `apps/Connectum/ConnectumTests/DashboardKPIStoreTests.swift`
- Test: `apps/Connectum/ConnectumTests/DashboardChartBuilderTests.swift`

- [ ] **Step 1: Write failing tests**

Add tests proving:
- default dashboard state includes only `전체 유저`, `컨택률`, `컨택 완료`
- `프로필 보유` and `최근 7일 가입` are not default KPI cards
- custom KPI definitions persist per service
- deleting/reordering cards persists
- built-in date series are generated from `CrmUser.createdAt`

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
cd apps/Connectum
xcodegen generate
xcodebuild test -scheme Connectum -destination 'platform=macOS' -only-testing:ConnectumTests/DashboardKPIStoreTests -only-testing:ConnectumTests/DashboardChartBuilderTests
```

Expected: tests fail to compile because `DashboardKPIState`, `DashboardKPIStore`, and `DashboardChartBuilder` do not exist yet.

- [ ] **Step 3: Implement minimal model/store/chart code**

Create `DashboardKPIModels.swift` with:
- `DashboardKPIKind`
- `DashboardKPIDefinition`
- `DashboardKPIState`
- `DashboardKPIStore`
- `DashboardKPIConfirmation`
- `DashboardKPIChartPoint`
- `DashboardChartBuilder`

The initial state must be exactly:

```swift
[.totalUsers, .contactRate, .contacted]
```

- [ ] **Step 4: Run tests and verify GREEN**

Run the same focused `xcodebuild test` command. Expected: focused dashboard tests pass.

### Task 2: Wire Gemini KPI Confirmation

**Files:**
- Modify: `apps/Connectum/Connectum/Data/CrmRepository.swift`
- Create: `supabase/functions/kpi-confirm/index.ts`

- [ ] **Step 1: Add repository API surface**

Extend `CrmDataProviding` with:

```swift
func confirmDashboardKPI(serviceId: String, title: String, prompt: String) async throws -> DashboardKPIConfirmation
```

Implement it in `CrmRepository` via Supabase function `kpi-confirm`.

- [ ] **Step 2: Add Edge Function**

Create `supabase/functions/kpi-confirm/index.ts` that:
- accepts `{ service_id, title, prompt }`
- loads service/table context
- calls Vertex Gemini using existing `getAccessToken` and `generateSummary`
- returns `{ title, summary, calculation_plan, chart_plan, warnings }`

- [ ] **Step 3: Verify compile**

Run:

```bash
cd apps/Connectum
xcodebuild build -scheme Connectum -destination 'platform=macOS'
```

Expected: app compiles with the new repository method.

### Task 3: Implement Customizable Dashboard UI

**Files:**
- Modify: `apps/Connectum/Connectum/Features/Dashboard/DashboardView.swift`

- [ ] **Step 1: Replace static metric grid**

Remove the hardcoded `프로필 보유` and `최근 7일 가입` metric cards. Render cards from `DashboardKPIState`.

- [ ] **Step 2: Add KPI creation sheet**

Add a sheet with:
- KPI title input
- calculation prompt input
- `Gemini 확인 요청` button
- Gemini confirmation preview
- `컨펌하고 추가` button

The UI must add the KPI card immediately after confirmation and avoid blocking on chart generation.

- [ ] **Step 3: Add reorder/delete/select**

Cards must:
- be selectable by click
- show selected state
- support drag reorder using `.onDrag` and `.onDrop`
- expose a delete button per card
- persist layout after reorder/delete

- [ ] **Step 4: Add main chart panel**

Clicking any card updates the main chart panel. Built-in cards use date series generated from users. Custom cards show background generation state and use a safe built-in series only when the prompt clearly maps to an existing built-in metric; otherwise they remain registered with a pending chart message.

- [ ] **Step 5: Verify build**

Run:

```bash
cd apps/Connectum
xcodebuild build -scheme Connectum -destination 'platform=macOS'
```

Expected: app builds.

### Task 4: Fix Connections Resize Clipping

**Files:**
- Modify: `apps/Connectum/Connectum/Features/Connections/ConnectionsView.swift`

- [ ] **Step 1: Replace fixed horizontal layout**

Replace the real-service `HStack` with a responsive `ViewThatFits(in: .horizontal)` layout:
- wide: connected accounts and action column side-by-side
- narrow: action column stacks below connected accounts

Do not keep `.frame(width: 380)` as a hard requirement.

- [ ] **Step 2: Verify no horizontal clipping**

Run build and inspect the code path. If local app launch is practical, open the app and resize around the prior failing width.

### Task 5: Remove Sidebar Bottom Separator

**Files:**
- Modify: `apps/Connectum/Connectum/App/RootView.swift`

- [ ] **Step 1: Remove the divider**

Remove the `Divider().overlay(Palette.hairline)` from `sidebarActionBar`.

- [ ] **Step 2: Verify build**

Run app build after this small visual change.

### Task 6: Final Verification

**Files:**
- Review all touched files

- [ ] **Step 1: Run tests**

Run:

```bash
cd apps/Connectum
xcodebuild test -scheme Connectum -destination 'platform=macOS'
```

- [ ] **Step 2: Check git diff**

Run:

```bash
git status --short
git diff --stat
```

- [ ] **Step 3: Summarize outcome**

Report:
- worktree path and branch
- implemented behavior
- test/build results
- any limitations, especially that arbitrary KPI execution is registered and confirmed now, while unknown formulas wait for the backend calculation engine/chart job.
