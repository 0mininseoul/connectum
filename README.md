# Connectum

Native macOS CRM for operating users from an existing Supabase service database. Connectum's product direction is local-first for open-source distribution: Connectum-owned data stays on the user's Mac, provider credentials stay in Keychain, and the app should not require a Connectum-hosted backend or a Connectum-specific Supabase project.

## Trust Model

- No maintainer Supabase is used by default.
- No Connectum account is required to open the app.
- Connectum workspace data is stored at `~/Library/Application Support/Connectum/Local/store.json`.
- Source credentials are stored in macOS Keychain, not in the JSON store.
- No in-app telemetry or user usage logs are collected by default.
- AI chat uses the user's Claude OAuth connection, not a user-pasted API key. Claude tokens are stored in macOS Keychain; prompts and selected local service context are sent directly from the local app to Claude only when the user invokes AI. They do not pass through maintainer infrastructure.

## Source Connector Model

Supabase is a source connector only. Users connect an existing production or staging Supabase project with a Personal Access Token, choose the user table and display columns, and Connectum mirrors selected rows into the local store for CRM operation.

Users should not create a new Supabase project just to run Connectum.

## Layout

- `apps/Connectum/` — SwiftUI macOS app.
- `supabase/` — legacy hosted-backend migrations and Edge Functions kept for reference and prior deployments.
- `scripts/` — legacy Deno helper scripts.
- `script/` — local app build/run/install helper used by the Codex Run action.
- `docs/superpowers/{specs,plans}/` — design specs and implementation plans.

## AI Agent Context

Future Codex CLI and Claude Code sessions should read `AGENTS.md` and `CLAUDE.md` first. They document the local-first/open-source trust boundary, the intended local repository path, the Claude OAuth direction, and how to treat older hosted-backend design docs.

Older files under `docs/superpowers/` may describe the pre-local-first architecture where Connectum used its own hosted Supabase backend. Treat those as historical unless a current top-level doc or current app code confirms the same direction.

## Local Dev

```bash
cd apps/Connectum
xcodegen generate
open Connectum.xcodeproj
```

Run the `Connectum` scheme. The app opens directly into the local workspace. In the Connections tab, add a Supabase Personal Access Token for an existing Supabase account, then create a service from one of that account's projects.

To build and replace the locally installed macOS app for QA:

```bash
# from the repository root
./script/build_and_run.sh --install-verify
```

## Verification

```bash
cd apps/Connectum
xcodegen generate
xcodebuild test -project Connectum.xcodeproj -scheme Connectum -destination 'platform=macOS'
```
