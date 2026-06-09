# Connectum Design System

## Direction

Connectum is a compact native macOS operations tool. It should feel closer to Finder, Raycast, Linear, and Notion database views than to a SaaS landing page. The design favors density, alignment, keyboard access, restrained color, and clear table mechanics.

## Layout Principles

- Use stable panes: sidebar, tab bar, main work area, optional right-side user detail.
- Keep work surfaces unframed unless they are repeated items, popovers, settings panels, or destructive zones.
- Avoid nested cards. A card may contain rows, but cards should not sit inside other cards.
- Prefer popovers for compact configuration lists such as table selection and column visibility.
- Resize handles must look draggable. Use a visible grip, wider hit target, hover cursor, and persistent divider.
- Avoid visible instructional copy where the control itself can communicate the action.

## Typography

- Use the macOS system font only.
- Default text sizes:
  - Title: 22 semibold
  - Panel title: 17 semibold
  - Body and table text: 14 regular
  - Caption and metadata: 12 regular
- Do not use display fonts for product UI.
- Do not scale font size with window width. UI scale is controlled by app zoom commands.

## Color

Connectum uses adaptive dark and light themes.

- Canvas: translucent black in dark mode, quiet light neutral in light mode.
- Surface: subtle material-like layer for tab bars, headers, and panels.
- Elevated surface: controls, selected rows, active tabs.
- Card surface: settings, connected account groups, service setup panels.
- Hairline: one-pixel separators and strokes.
- Semantic accents:
  - Blue: links, active data-source icons, sync/status.
  - Green: success and connected state.
  - Red: destructive actions and errors.
  - Yellow: warnings.

Color is functional. Do not use accent colors as decoration.

## Controls

- Use icon buttons for compact toolbar actions.
- Use segmented controls only for small mode sets.
- Use pickers for account/project choices.
- Use popovers for long selectable lists.
- Use checkboxes for multi-select tables and columns.
- Use context menus for infrequent row actions such as user exclusion.
- Use confirmation alerts for destructive deletion.

## Operational DB

- The table is the primary product surface.
- No permanent search box. Command+F reveals and focuses search.
- Search matches every user value that can reasonably appear in a cell: main column, email, source id, profile fields, Amplitude profile fields, contact state, AI summary, and dates.
- Enter opens the selected user.
- Up and Down move row selection when the table is active.
- Right-click opens the selected row's context menu even when the click lands on whitespace.
- Column sort belongs in the header, not a separate dropdown.
- Column widths should start fitted to content and remain user-resizable.

## User Detail

- Default open mode is the right-side pane.
- The pane opens focused. Pressing Tab immediately switches between Work and History.
- The pane must not show a blue focus ring just because it is keyboard-ready.
- The divider between table and user detail has a visible grip and left-right resize cursor.
- Header title uses the selected main column value, not hardcoded email.

## Connections

- Separate account management from service setup.
- Connected source rows show the selected resource as the primary line: Supabase project name, Amplitude project name, or Axiom dataset name.
- The secondary line shows the source account name or email.
- Do not repeat provider names under provider sections.
- Do not show credential nicknames such as "PAT (dev)" in connected-source rows.
- Account add forms appear only for providers that do not already have a connected account.
- Service setup uses existing accounts. It should not look like the user is reconnecting the same provider.
- Supabase table selection is a compact dropdown/popover with scrolling checkboxes.

## Settings

- Settings are for user preferences and account state, not Connectum infrastructure.
- Do not show backend URLs, anon keys, config paths, or internal deployment details.
- The user detail open mode is labeled as "유저 페이지 열기 방식", not as a generic Operational DB preference.

## Shortcuts

- Command+1: Operational DB.
- Command+2: Dashboard.
- Command+3: Connections.
- Command+N: New service.
- Command+F: Find in operational DB.
- Enter: Open selected user from the table.
- Tab: Switch Work/History in the user page.
- Backslash key shown as `₩`: Toggle sidebar.
- Command++: Zoom in.
- Command+-: Zoom out.
- Command+0: Actual size.
- Command+Shift+L: Toggle light/dark mode.

## Anti-Patterns

- Long explanatory paragraphs inside ordinary panels.
- Permanent search fields that consume table toolbar space.
- Provider names repeated as row metadata.
- Huge inline table lists in setup flows.
- Hidden resize affordances.
- Decorative gradients, orbs, and card-heavy marketing composition.
