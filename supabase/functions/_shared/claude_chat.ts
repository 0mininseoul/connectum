import { claudeEnv } from "./claude_env.ts";
import { tokenForClaudeAccount } from "./claude_token.ts";

// OAuth subscription token only accepted when system block 1 is the Claude Code identity.
export const CLAUDE_CODE_IDENTITY = "You are Claude Code, Anthropic's official CLI for Claude.";

export async function claudeHeaders(): Promise<Record<string, string>> {
  const apiKey = claudeEnv.apiKey();
  if (apiKey) {
    // Official API-key fallback (kept for when the OAuth path breaks).
    return { "Content-Type": "application/json", "x-api-key": apiKey, "anthropic-version": "2023-06-01" };
  }
  const token = await tokenForClaudeAccount();
  return {
    "Content-Type": "application/json",
    "Authorization": `Bearer ${token}`,
    "anthropic-version": "2023-06-01",
    "anthropic-beta": claudeEnv.oauthBeta(),
  };
}

// Single-shot completion. `instructions` are system text blocks placed AFTER the
// required Claude Code identity block. Returns concatenated assistant text.
// Throws an Error whose message starts with "ai_reauth_required" on 401/403 so
// callers can surface a re-connect prompt.
export async function claudeComplete(
  instructions: string[],
  userText: string,
  maxTokens = 2048,
): Promise<string> {
  const system = [
    { type: "text", text: CLAUDE_CODE_IDENTITY },
    ...instructions.map((t) => ({ type: "text", text: t })),
  ];
  const res = await fetch(claudeEnv.apiUrl(), {
    method: "POST",
    headers: await claudeHeaders(),
    body: JSON.stringify({
      model: claudeEnv.model(),
      max_tokens: maxTokens,
      system,
      messages: [{ role: "user", content: userText }],
    }),
  });
  if (res.status === 401 || res.status === 403) {
    throw new Error("ai_reauth_required:" + (await res.text()));
  }
  if (!res.ok) throw new Error(`claude_error:${res.status}:${await res.text()}`);
  const msg = await res.json();
  return (msg.content as Array<{ type: string; text?: string }>)
    .filter((b) => b.type === "text").map((b) => b.text ?? "").join("").trim();
}
