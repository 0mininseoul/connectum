# Claude Code Context

This repository uses `AGENTS.md` as the canonical AI-agent context. Read it before making changes.

Critical summary:

- Connectum is a local-first, open-source-oriented native macOS CRM for sensitive internal operations data.
- The maintainer must not receive or be able to inspect customer data, source rows, CRM notes, credentials, AI prompts, screenshots, service briefs, or usage logs by default.
- Do not reintroduce a hosted Connectum backend, required Connectum login, default telemetry, or a requirement that users create a Supabase project for Connectum itself.
- Default app data lives in `~/Library/Application Support/Connectum/Local/store.json`; credentials and OAuth tokens live in macOS Keychain.
- `CrmRepository` currently aliases `LocalCrmRepository`; `HostedSupabaseCrmRepository` and `supabase/` are legacy/reference paths.
- Claude AI uses local OAuth tokens and direct local app calls to Anthropic/Claude. Do not add an Anthropic API-key product flow or a maintainer-hosted AI proxy unless the product direction explicitly changes.
- Older `docs/superpowers/*` files may describe the pre-local-first hosted architecture. Prefer `AGENTS.md`, `README.md`, `PRODUCT.md`, `DESIGN.md`, and current code when there is a conflict.

