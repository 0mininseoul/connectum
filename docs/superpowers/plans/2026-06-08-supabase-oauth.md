# Supabase OAuth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Supabase PAT-first onboarding with browser-based OAuth as the default connection path, keeping PAT as an advanced fallback.

**Architecture:** The macOS app asks a Connectum Edge Function for a Supabase OAuth authorize URL, opens it in the system browser, listens on a loopback callback URL for the authorization code, and sends that code to the existing token exchange Edge Function. OAuth secrets and scopes stay on the backend. PAT remains available only behind an advanced disclosure.

**Tech Stack:** SwiftUI, AppKit `NSWorkspace`, Network.framework loopback HTTP listener, Supabase Swift Edge Function invocations, Supabase Edge Functions in Deno.

---

### Task 1: OAuth URL And Callback Primitives

**Files:**
- Create: `apps/Connectum/Connectum/Features/Connections/SupabaseOAuthFlow.swift`
- Test: `apps/Connectum/ConnectumTests/SupabaseOAuthFlowTests.swift`

- [ ] **Step 1: Write the failing Swift tests**

```swift
func testCallbackParserExtractsCodeAndState() throws {
    let request = "GET /callback?code=abc123&state=state-1 HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
    let callback = try SupabaseOAuthCallbackParser.parse(request)
    XCTAssertEqual(callback.code, "abc123")
    XCTAssertEqual(callback.state, "state-1")
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -quiet -project Connectum.xcodeproj -scheme Connectum -destination 'platform=macOS' -only-testing:ConnectumTests/SupabaseOAuthFlowTests`

Expected: compile failure because `SupabaseOAuthCallbackParser` does not exist.

- [ ] **Step 3: Implement the primitives**

Add a callback parser, random state generator, fixed loopback redirect URI, and loopback receiver.

- [ ] **Step 4: Verify green**

Run the same focused test and then the full macOS test suite.

### Task 2: Backend OAuth Start And Exchange

**Files:**
- Create: `supabase/functions/oauth-supabase-start/index.ts`
- Modify: `supabase/functions/oauth-supabase/index.ts`
- Modify: `supabase/functions/oauth-supabase/exchange.ts`
- Test: `supabase/functions/oauth-supabase/exchange.test.ts`

- [ ] **Step 1: Add failing Deno tests**

Add tests that assert the authorize URL contains `client_id`, `redirect_uri`, `response_type=code`, `state`, and optional `scope`.

- [ ] **Step 2: Implement start URL builder and exchange profile storage**

`oauth-supabase-start` returns `{ authorize_url }`. `oauth-supabase` exchanges the code, fetches `/v1/profile`, stores account display name, and saves access/refresh token refs in Vault.

- [ ] **Step 3: Verify Deno tests**

Run: `deno test supabase/functions/oauth-supabase/exchange.test.ts`

### Task 3: App Repository And View Model

**Files:**
- Modify: `apps/Connectum/Connectum/Data/CrmRepository.swift`
- Modify: `apps/Connectum/Connectum/Features/Connections/ConnectionsView.swift`

- [ ] **Step 1: Add protocol methods**

`supabaseOAuthAuthorizeURL(state:)` and `connectSupabaseOAuth(code:state:)`.

- [ ] **Step 2: Make OAuth the default UI**

Show a primary `Supabase로 계속하기` button. Move PAT fields into `수동 연결` disclosure.

- [ ] **Step 3: Wire the flow**

Start loopback listener, open browser, validate state, call the exchange function, reload accounts.

### Task 4: Verification And Packaging

**Files:**
- Update: `dist/Connectum-1.0.dmg`

- [ ] **Step 1: Run full tests**

Run: `xcodebuild test -quiet -project Connectum.xcodeproj -scheme Connectum -destination 'platform=macOS'`

- [ ] **Step 2: Build Release**

Run: `xcodebuild build -quiet -project Connectum.xcodeproj -scheme Connectum -configuration Release -destination 'platform=macOS'`

- [ ] **Step 3: Visual QA**

Launch the Release app, confirm first-run Supabase connection uses OAuth by default and PAT is hidden under advanced manual connection.

- [ ] **Step 4: Recreate DMG**

Run `hdiutil create` and `hdiutil verify`.
