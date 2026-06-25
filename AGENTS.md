# Connectum Agent Context

Read this before making changes in this repository.

## Product

Connectum is a local-first native macOS CRM for operating users from an existing service database. It is intended to be open-source friendly for sensitive internal operations data.

The core trust promise is simple: the Connectum maintainer must not receive, store, or be able to inspect a user's customer data, service operations data, credentials, AI prompts, notes, usage logs, or source rows by default.

## Non-Negotiable Trust Boundaries

- No maintainer-hosted Supabase or Connectum backend is required by default.
- Do not reintroduce a Connectum account/login gate for normal app launch.
- Do not ask users to create a Supabase project just to use Connectum.
- Supabase is a source connector for an existing production or staging service project.
- Connectum-owned data is stored locally at `~/Library/Application Support/Connectum/Local/store.json`.
- Provider credentials and OAuth tokens are stored in macOS Keychain, not in JSON files.
- Do not collect in-app telemetry or per-user usage logs by default.
- Do not send source rows, CRM notes, screenshots, service briefs, prompts, or usage logs to maintainer infrastructure.
- User data may leave the device only for a user-connected provider action: source reads from the user's provider, or AI requests to the user's selected AI provider.

If a feature needs sync, analytics, release checks, crash reporting, or hosted collaboration, it must be explicit, opt-in, documented, and designed so the maintainer cannot silently inspect customer data.

## Current Architecture

- Main app: `apps/Connectum/`, native SwiftUI macOS.
- Default repository: `typealias CrmRepository = LocalCrmRepository`.
- Local state: `LocalConnectumStore`.
- Secrets: `KeychainSecretStore`.
- Source sync: direct Supabase Management API calls from the macOS app using the user's connected PAT by default. A user-owned OAuth token path may exist, but do not silently wire it to maintainer infrastructure or present hosted Connectum OAuth as the default source connection.
- Legacy hosted implementation: `HostedSupabaseCrmRepository`.
- Legacy backend files: `supabase/` and many older `docs/superpowers/*` specs/plans are retained for reference and prior deployments. Do not treat them as the default product architecture.
- Bundled backend config: `apps/Connectum/Connectum/Resources/BackendConfig.json` must stay non-secret and must not point at a maintainer Supabase project.

## AI Provider Direction

The product currently targets Claude OAuth, not API keys. The app does not support a user-pasted Anthropic API key flow.

Current Claude path:

- `ClaudeOAuthFlow` opens Anthropic/Claude OAuth with PKCE.
- The user completes the browser flow and pastes the returned code into Connectum.
- Claude access/refresh tokens are stored in Keychain.
- `AIChatStreamClient` calls `https://api.anthropic.com/v1/messages` directly from the local macOS app.
- Service context used for chat is assembled locally from the selected service and sent to Claude only when the user invokes AI.
- Do not proxy Claude prompts through Supabase Edge Functions or maintainer infrastructure.

Keep this distinction clear in UI and docs: the maintainer does not see AI prompts, but the external AI provider receives whatever local context the app sends for a user-initiated AI request.

## Product And UI Guidance

- UI copy is primarily short Korean labels.
- The app should feel compact, native, keyboard-friendly, and operational.
- Prefer split views, tables, popovers, context menus, and macOS-native controls.
- Avoid marketing pages, large instructional panels, decorative gradients, and card-heavy layouts.
- Settings should show local trust state and preferences, not hosted backend internals.
- Connections should separate provider account management from service setup.

## Documentation Priority

When documents conflict, prefer this order:

1. `AGENTS.md` and `CLAUDE.md`.
2. `README.md`, `PRODUCT.md`, `DESIGN.md`.
3. Current code in `apps/Connectum`.
4. `docs/superpowers/plans/2026-06-24-local-first-open-source.md`.
5. Older `docs/superpowers/*` specs/plans, which may describe the pre-local-first hosted architecture.

When changing architecture or trust boundaries, update `AGENTS.md`, `CLAUDE.md`, `README.md`, and the relevant product/design docs in the same change.

## Development Commands

Generate/open the Xcode project:

```bash
cd apps/Connectum
xcodegen generate
open Connectum.xcodeproj
```

Run tests:

```bash
cd apps/Connectum
xcodegen generate
xcodebuild test -project Connectum.xcodeproj -scheme Connectum -destination 'platform=macOS'
```

Build, install, and launch the local macOS app for QA:

```bash
# from the repository root
./script/build_and_run.sh --install-verify
```
