-- Serialize Claude OAuth token refreshes. Anthropic's subscription refresh
-- tokens are single-use and rotate on every refresh; if two requests refresh
-- concurrently, the second reuses an already-consumed token, which Anthropic
-- treats as token theft and revokes the entire token family — bricking the
-- connection until a manual reconnect. tokenForClaudeAccount() claims this
-- timestamp with an atomic conditional update so exactly one caller refreshes.
alter table public.ai_account
  add column if not exists refresh_lock_at timestamptz;
