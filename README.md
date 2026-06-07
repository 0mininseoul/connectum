# Connectum

Native macOS CRM tool. See `docs/superpowers/specs/2026-06-07-connectum-design.md`.

## Layout
- `supabase/` — Postgres migrations + Deno Edge Functions (sync, OAuth, AI)
- `scripts/` — Deno validation spikes (run with real credentials, see `.env.example`)
- `apps/Connectum/` — SwiftUI macOS app (generate Xcode project with `xcodegen generate`)

## Phase 0 quickstart
1. `cp .env.example .env` and fill in credentials.
2. `supabase start`
3. Run spikes: `deno run -A --env-file=.env scripts/spike_*.ts`
4. `cd apps/Connectum && xcodegen generate && open Connectum.xcodeproj`
