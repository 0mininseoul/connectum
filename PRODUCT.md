# Connectum Product

## One-Line Definition

Connectum is a local-first native macOS CRM for teams to operate users from existing service data sources, starting with Supabase, in one service-scoped operational database.

## Register

Product UI. Design serves repeated operational work, not marketing. The interface should feel compact, native, fast, and predictable.

## Primary Users

- Internal operators and founders who inspect users, exclude test accounts, record contact history, and decide who to contact next.
- Engineers who connect source systems, verify sync state, and debug whether data is coming from the right project or account.

## Product Principles

- One service is one operational context. A service maps to an existing Supabase project and its selected source tables.
- Connectum is read-heavy for source systems. Source credentials live in the user's Keychain, source rows are mirrored into local storage, and the app edits only Connectum-owned operational data.
- Connectum must not require users to create a Supabase project for Connectum itself.
- Connectum has no maintainer-hosted backend by default. Backend URLs, anon keys, and hosted deployment details must not appear in normal user-facing settings.
- No in-app telemetry or usage log collection is enabled by default.
- AI features must stay local-to-provider: Connectum may send selected local service context to the user's connected Claude account for a user-initiated AI request, but it must not send that context through maintainer infrastructure.
- The operating surface should stay dense and keyboard-first. Prefer shortcuts, context menus, split views, tables, and popovers over large instructional screens.
- Search, sorting, column visibility, row opening, exclusion, and sync should be available without moving through long forms.
- Local cache is part of the product. Opening the app should show cached operational data quickly, then sync in the background.
- Excluded users are not users for this service. Exclusion affects the operational DB, dashboard, and future sync inclusion.

## Core Workflows

1. Connect data sources.
   - Connect an existing Supabase account with a Personal Access Token.
   - Use connected accounts when creating services.
   - Do not ask for a provider connection again when a usable account already exists.
   - Connected source rows show the resource first and the account second: Supabase project name above the account label/name.

2. Create a service.
   - Choose an existing Supabase account connected by PAT.
   - Load projects.
   - Choose one project.
   - Pick source tables from a compact scrollable table selector.
   - Mark one selected table as the user table.
   - Choose user id, email, main, and display columns.

3. Operate users.
   - Select rows with pointer or keyboard.
   - Open a user with Enter or double-click.
   - Use right-click for uncommon actions such as exclusion.
   - Search with Command+F across all cell-like user values.
   - Open the user page in a resizable right-side pane by default.

4. Review a user.
   - Header shows the configured main column value first.
   - Tab switches between work and history immediately after the page opens.
   - Work tab combines records, notes, history, and profile context. AI-only content must stay hidden or disabled unless a supported AI provider is connected.
   - History tab captures dated evidence and screenshots.

5. Manage the app.
   - Settings expose local storage/privacy status, theme, user page open mode, and UI scale.
   - Settings do not expose hosted Connectum backend connection details.
   - Common commands appear in the macOS menu bar with visible shortcuts.

## Current Product Boundaries

- macOS only.
- Open-source local-first team tool.
- No customer-facing surfaces.
- No outbound marketing automation.
- No source write-back.
- No maintainer access to user source rows, CRM notes, credentials, prompts, or usage logs by default.
- AI chat requires the user to connect Claude with OAuth; Claude credentials stay in the user's Keychain. The product does not expose a user-pasted Anthropic API key flow.

## Tone

Short Korean labels by default. Avoid explaining obvious UI. Prefer nouns and actions: "테이블 선택", "서비스 생성", "계정 삭제", "유저 제외". Do not use internal credential nicknames such as "PAT (dev)" or provider names as connected-source row titles.

## Quality Bar

An experienced macOS user should understand the main affordances from shape, placement, and keyboard shortcuts. The UI should not rely on visible instructional paragraphs for normal operation.
