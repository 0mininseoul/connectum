type Row = Record<string, unknown>;
export interface PromptUser {
  email?: string | null; source_user_id: string; contact_status?: string;
  supabase_profile?: Row | null; amplitude_profile?: Row | null;
}
export interface PromptEvent { event_type: string; event_time: string; }
export interface PromptRecord { channel?: string; body?: string; occurred_at?: string; }

export function buildSummaryPrompt(user: PromptUser, events: PromptEvent[], records: PromptRecord[]): string {
  const sp = JSON.stringify(user.supabase_profile ?? {});
  const ap = JSON.stringify(user.amplitude_profile ?? {});
  const ev = events.slice(0, 30).map((e) => `${e.event_time} ${e.event_type}`).join("\n");
  const rec = records.map((r) => `[${r.channel ?? "memo"}] ${r.occurred_at ?? ""} ${r.body ?? ""}`).join("\n");
  return [
    "당신은 CRM 분석가입니다. 아래 유저를 한국어 3줄로 요약하세요. 각 줄은 간결하게, 가입 정보·제품 사용 행동·운영 맥락을 종합해 핵심만 담으세요.",
    "",
    `[유저] ${user.email ?? user.source_user_id} (컨택: ${user.contact_status ?? "?"})`,
    `[가입 프로필] ${sp}`,
    `[행동 프로필] ${ap}`,
    "[최근 이벤트]", ev || "없음",
    "[운영 기록]", rec || "없음",
    "", "3줄 요약:",
  ].join("\n");
}

export async function generateSummary(token: string, project: string, location: string, model: string, prompt: string): Promise<string> {
  const url = `https://aiplatform.googleapis.com/v1/projects/${project}/locations/${location}/publishers/google/models/${model}:generateContent`;
  const res = await fetch(url, {
    method: "POST", headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify({ contents: [{ role: "user", parts: [{ text: prompt }] }], generationConfig: { maxOutputTokens: 300, temperature: 0.4 } }),
  });
  const j = await res.json();
  if (!j.candidates) throw new Error("gemini error: " + JSON.stringify(j).slice(0, 300));
  return (j.candidates[0].content.parts as Array<{ text?: string }>).map((p) => p.text ?? "").join("").trim();
}
