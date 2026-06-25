# Local-First Open Source Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert Connectum from a maintainer-hosted Supabase backend app into a local-first open-source macOS app that never sends product data to the maintainer.

**Architecture:** The app stores Connectum-owned data in local files under Application Support and stores provider credentials in Keychain. Supabase remains only a source system: the app calls the Supabase Management API directly with a user-provided PAT by default and mirrors selected source rows into the local store. A user-owned OAuth token path may exist, but it must not be silently wired to maintainer infrastructure or presented as the default source connection. AI must not call maintainer-hosted Edge Functions.

**Status note (2026-06-25):** the earlier "disable Claude subscription/OAuth" step below was superseded by the product decision to support Claude OAuth locally. The intended implementation stores Claude OAuth tokens in Keychain and calls Claude directly from the macOS app. Do not add an Anthropic API-key product flow or a maintainer-hosted AI proxy unless the product direction explicitly changes.

This plan may be used alongside local in-progress implementation work. If this document is merged before all code changes land, treat checked items as local migration intent/status, not proof that the base branch already contains every referenced file.

**Tech Stack:** SwiftUI macOS, Foundation URLSession, Security Keychain, local JSON persistence, existing Supabase Swift package retained for legacy code only.

---

### Task 1: Local Storage And Secrets

**Files:**
- Create: `apps/Connectum/Connectum/Data/LocalConnectumStore.swift`
- Create: `apps/Connectum/Connectum/Data/KeychainSecretStore.swift`
- Test: `apps/Connectum/ConnectumTests/LocalConnectumStoreTests.swift`

- [x] **Step 1: Add local state models and JSON store**

Create `LocalConnectumStore` with a `Snapshot` containing services, accounts, service tables, users, mirrored rows, records, history, views, KPIs, service briefs, and chat messages. Save atomically to `~/Library/Application Support/Connectum/Local/store.json` by default.

- [x] **Step 2: Add a Keychain abstraction**

Create `SecretStoring` plus `KeychainSecretStore` for production and an in-memory test double. Store only credential references in the JSON snapshot.

- [x] **Step 3: Add store tests**

Verify service/account/table/user rows round-trip through a temporary JSON file and that deleting a service removes its service-scoped local data.

Run: `cd apps/Connectum && xcodebuild test -project Connectum.xcodeproj -scheme Connectum -destination 'platform=macOS' -only-testing:ConnectumTests/LocalConnectumStoreTests`

Expected: PASS after implementation.

### Task 2: Local Repository

**Files:**
- Create: `apps/Connectum/Connectum/Data/LocalCrmRepository.swift`
- Modify: `apps/Connectum/Connectum/Data/CrmRepository.swift`
- Test: `apps/Connectum/ConnectumTests/LocalCrmRepositoryTests.swift`

- [x] **Step 1: Implement `LocalCrmRepository: CrmDataProviding`**

Implement local CRUD for services, accounts, imported tables, users, notes, records, history, KPIs, views, AI account metadata, chat messages, and service brief data.

- [x] **Step 2: Implement direct Supabase Management API client**

Use stored PATs to call:
- `GET https://api.supabase.com/v1/projects`
- `POST https://api.supabase.com/v1/projects/{projectRef}/database/query/read-only` for table/column discovery and row sync.

Use quoted SQL identifiers for schema/table/column names and keep queries read-only.

- [x] **Step 3: Make `CrmRepository` route to local by default**

Keep the existing hosted Supabase implementation as `HostedSupabaseCrmRepository` or `LegacySupabaseCrmRepository`, and make `CrmRepository` a facade whose default implementation is `LocalCrmRepository`.

- [x] **Step 4: Add repository tests**

Use a fake Supabase Management client to verify service creation, table specs, sync mapping, contact status changes, KPI counts, and display column updates.

### Task 3: App Launch Without Maintainer Backend

**Files:**
- Modify: `apps/Connectum/Connectum/App/RootView.swift`
- Modify: `apps/Connectum/Connectum/App/SettingsView.swift`
- Modify: `apps/Connectum/Connectum/Supabase/SupabaseClientProvider.swift`
- Modify: `apps/Connectum/Connectum/Resources/BackendConfig.json`

- [x] **Step 1: Remove login gate from root**

Start `MainShell` immediately. The app should not require a Connectum account.

- [x] **Step 2: Replace settings login card**

Show local storage path, privacy mode, and a short "no in-app telemetry" statement instead of account email/logout controls.

- [x] **Step 3: Remove bundled remote backend default**

Replace bundled `BackendConfig.json` with an empty/local placeholder so a release build cannot silently connect to the maintainer Supabase.

### Task 4: Superseded — Keep Claude OAuth Local-Only

**Files:**
- Modify: `apps/Connectum/Connectum/Features/Connections/ConnectionsView.swift`
- Modify: `apps/Connectum/Connectum/Features/AIChat/AIChatViewModel.swift`
- Modify: `apps/Connectum/Connectum/Features/AIChat/AIChatStreamClient.swift`

- [x] **Step 1: Keep Claude connection copy local-to-provider**

The connection card should present Claude OAuth as a user-owned provider connection. It must not imply Connectum maintainer infrastructure receives prompts, service context, or Claude tokens.

- [x] **Step 2: Block hosted AI calls**

`AIChatStreamClient` must not call the old Supabase Edge Function. AI requests should use local Claude OAuth tokens and call Claude directly from the macOS app.

### Task 5: Documentation And Verification

**Files:**
- Modify: `README.md`
- Modify: `PRODUCT.md`
- Modify: `DESIGN.md`

- [x] **Step 1: Document local-first trust model**

State that Connectum does not collect customer data, source DB rows, credentials, AI prompts, or in-app usage logs by default.

- [x] **Step 2: Document source connector model**

Make clear users connect existing production source systems; they do not create a Connectum-specific Supabase project.

- [x] **Step 3: Build and test**

Run:
`cd apps/Connectum && xcodegen generate && xcodebuild test -project Connectum.xcodeproj -scheme Connectum -destination 'platform=macOS'`

Expected: PASS or a clearly identified pre-existing blocker.
