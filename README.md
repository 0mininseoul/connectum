# Connectum

Native macOS CRM tool that ingests per-service user data from Supabase + Amplitude,
generates AI summaries (Vertex AI Gemini), and lets the team manage contact status,
records, history, custom views, and a dashboard. See `docs/superpowers/specs/2026-06-07-connectum-design.md`.

## Layout
- `supabase/` — Postgres migrations + Deno Edge Functions (connect/discovery, sync, summarize)
- `scripts/` — Deno helpers: validation spikes + dev seed scripts (real credentials in `.env.local`)
- `apps/Connectum/` — SwiftUI macOS app (generate the Xcode project with `xcodegen generate`)
- `docs/superpowers/{specs,plans}/` — design spec + implementation plans

## Local dev quickstart
1. `cp .env.example .env.local` and fill in credentials (SUPABASE_PAT, AMPLITUDE_API_KEY/SECRET_KEY/REGION, AXIOM_TOKEN). The GCP service-account key + GCP_PROJECT/GCP_LOCATION/GCP_MODEL also live here (base64 as `GCP_SA_KEY_B64`).
2. `supabase start` (applies migrations).
3. Seed a service for testing: `LOCAL_SERVICE_ROLE_KEY=... deno run -A --env-file=.env.local scripts/seed_supabase_account.ts` then `scripts/seed_service.ts`.
4. Serve functions with secrets: `supabase functions serve --env-file .env.local` (the summarize-user function needs the GCP vars).
5. Trigger a full sync: `POST /functions/v1/sync` (orchestrates Supabase + Amplitude sync + bounded AI-summary generation per service).
6. App: `cd apps/Connectum && xcodegen generate && open Connectum.xcodeproj` → set the run scheme env `SUPABASE_URL=http://127.0.0.1:54321` and `SUPABASE_ANON_KEY=<supabase status ANON_KEY>` → run → sign in.

## Edge Functions
- `supabase-list-projects` / `supabase-list-tables` — Management API discovery
- `amplitude-connect` / `axiom-connect` — validate + store credentials, list sources
- `oauth-supabase` — OAuth code→token exchange (loopback redirect `http://127.0.0.1:53682/callback`)
- `supabase-sync-tables` — Supabase tables → `crm_user` / `mirrored_row` (incremental, idempotent)
- `amplitude-sync` — Amplitude Export → `crm_user_event` + profiles (dedup on `event_uuid`)
- `summarize-user` — Vertex AI Gemini 3-line summary (input-hash skip)
- `sync` — orchestrator (all of the above per service); the pg_cron target

## Production deployment (Supabase + Vercel-free)
- **Secrets**: `supabase secrets set GCP_SA_KEY_B64=... GCP_PROJECT=... GCP_LOCATION=global GCP_MODEL=gemini-3.1-flash-lite SUPABASE_OAUTH_CLIENT_ID=... SUPABASE_OAUTH_CLIENT_SECRET=...` (so all Edge Functions can read them). Deploy with `supabase functions deploy`.
- **pg_cron**: migration `0004_cron_sync.sql` registers a 30-min job calling `/functions/v1/sync`. In production set the DB settings it reads:
  ```sql
  alter database postgres set app.sync_function_url = 'https://<project-ref>.supabase.co/functions/v1/sync';
  alter database postgres set app.service_role_key  = '<service-role-key>';
  ```
- **App distribution**: build the macOS app, sign with a Developer ID, notarize, ship as a DMG.

## Models / data
- Gemini model for AI summaries: `gemini-3.1-flash-lite` (Vertex AI, `global` location) — chosen for efficiency at per-user volume (reviewed vs flash/pro).
