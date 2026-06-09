# Connectum Product

## One-Line Definition

Connectum is a native macOS CRM for the team to operate users across multiple services by syncing source data from Supabase, Amplitude, and Axiom into one service-scoped operational database.

## Register

Product UI. Design serves repeated operational work, not marketing. The interface should feel compact, native, fast, and predictable.

## Primary Users

- Internal operators and founders who inspect users, exclude test accounts, record contact history, and decide who to contact next.
- Engineers who connect source systems, verify sync state, and debug whether data is coming from the right project or account.

## Product Principles

- One service is one operational context. A service maps to one Supabase project, optional Amplitude analytics, and optional Axiom logs.
- Connectum is read-heavy for source systems. Source credentials and ETL run through Supabase Edge Functions. The app edits only Connectum-owned operational data.
- Connectum backend configuration is internal infrastructure. Backend URLs, anon keys, and local config paths must not appear in normal user-facing settings.
- The operating surface should stay dense and keyboard-first. Prefer shortcuts, context menus, split views, tables, and popovers over large instructional screens.
- Search, sorting, column visibility, row opening, exclusion, and sync should be available without moving through long forms.
- Local cache is part of the product. Opening the app should show cached operational data quickly, then sync in the background.
- Excluded users are not users for this service. Exclusion affects the operational DB, dashboard, and future sync inclusion.

## Core Workflows

1. Connect data sources.
   - Connect Supabase, Amplitude, and Axiom accounts once.
   - Use connected accounts when creating services.
   - Do not ask for a provider connection again when a usable account already exists.
   - Connected source rows show the resource first and the account second: Supabase project name, Amplitude project name, or Axiom dataset name above the account email/name.

2. Create a service.
   - Choose an existing Supabase account.
   - Load projects.
   - Choose one project.
   - Pick source tables from a compact scrollable table selector.
   - Mark one selected table as the user table.
   - Choose user id, email, main, and display columns.
   - Optionally attach Amplitude and Axiom accounts.

3. Operate users.
   - Select rows with pointer or keyboard.
   - Open a user with Enter or double-click.
   - Use right-click for uncommon actions such as exclusion.
   - Search with Command+F across all cell-like user values.
   - Open the user page in a resizable right-side pane by default.

4. Review a user.
   - Header shows the configured main column value first.
   - Tab switches between work and history immediately after the page opens.
   - Work tab combines AI summary, records, notes, and profile context.
   - History tab captures dated evidence and screenshots.

5. Manage the app.
   - Settings expose login state, logout, theme, user page open mode, and UI scale.
   - Settings do not expose Connectum backend connection details.
   - Common commands appear in the macOS menu bar with visible shortcuts.

## Current Product Boundaries

- macOS only.
- Internal team tool.
- No customer-facing surfaces.
- No outbound marketing automation.
- No source write-back.
- No general observability replacement. Axiom is used only to enrich CRM context.

## Tone

Short Korean labels by default. Avoid explaining obvious UI. Prefer nouns and actions: "테이블 선택", "서비스 생성", "계정 삭제", "유저 제외". Do not use internal credential nicknames such as "PAT (dev)" or provider names as connected-source row titles.

## Quality Bar

An experienced macOS user should understand the main affordances from shape, placement, and keyboard shortcuts. The UI should not rely on visible instructional paragraphs for normal operation.
