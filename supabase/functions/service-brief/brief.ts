export const BRIEF_SECTIONS = [
  "one_liner", "icp", "activation", "signal_glossary", "business_model", "current_focus",
] as const;
export type SectionKey = typeof BRIEF_SECTIONS[number];
export type BriefSections = Record<SectionKey, string>;

export function emptyBrief(): BriefSections {
  return Object.fromEntries(BRIEF_SECTIONS.map((k) => [k, ""])) as BriefSections;
}

function extractJSON(text: string): Record<string, unknown> {
  // Scan for the first *balanced* {...} object, tracking string state so braces
  // inside strings don't miscount. A greedy first-`{`-to-last-`}` regex breaks on
  // prose containing multiple objects (it spans across them) and on output
  // truncated mid-object by max_tokens (it grabs a stray inner `}`).
  const t = text.replace(/```(?:json)?/gi, "");
  const start = t.indexOf("{");
  if (start === -1) throw new Error("Claude가 JSON을 반환하지 않았습니다: " + text.slice(0, 200));
  let depth = 0, inStr = false, esc = false;
  for (let i = start; i < t.length; i++) {
    const ch = t[i];
    if (inStr) {
      if (esc) esc = false;
      else if (ch === "\\") esc = true;
      else if (ch === '"') inStr = false;
    } else if (ch === '"') inStr = true;
    else if (ch === "{") depth++;
    else if (ch === "}") {
      depth--;
      if (depth === 0) return JSON.parse(t.slice(start, i + 1));
    }
  }
  throw new Error("Claude JSON이 잘렸거나 불완전합니다(max_tokens?): " + text.slice(0, 200));
}

export function parseSectionsJSON(text: string): BriefSections {
  const raw = extractJSON(text);
  const out = emptyBrief();
  for (const k of BRIEF_SECTIONS) {
    const v = (raw as Record<string, unknown>)[k];
    if (typeof v === "string") out[k] = v.trim();
  }
  return out;
}

// A section is a "gap" if blank or shorter than 12 chars (placeholder-ish).
export function detectGaps(sections: BriefSections): SectionKey[] {
  return BRIEF_SECTIONS.filter((k) => (sections[k] ?? "").trim().length < 12);
}

export interface InterviewStep { question?: string; options?: string[]; done?: boolean }
export function parseInterviewJSON(text: string): InterviewStep {
  const raw = extractJSON(text) as InterviewStep;
  if (raw.done === true) return { done: true };
  const question = typeof raw.question === "string" ? raw.question.trim() : "";
  // Off-spec output (neither done nor a real question) → end the interview rather
  // than handing the client a blank prompt that would stall the conversation.
  if (!question) return { done: true };
  return {
    question,
    options: Array.isArray(raw.options) ? raw.options.filter((o) => typeof o === "string") : undefined,
  };
}

const SECTION_LABELS: Record<SectionKey, string> = {
  one_liner: "한 줄 소개 (무엇을 하는 서비스인가)",
  icp: "타깃 고객 / ICP",
  activation: "핵심 활성화·성공 기준 (제대로 쓴다는 것, aha moment)",
  signal_glossary: "핵심 행동·상태 신호의 의미 (이벤트 또는 컬럼/상태가 비즈니스적으로 뜻하는 것)",
  business_model: "비즈니스 모델 (수익화, 무료/유료, 전환 포인트)",
  current_focus: "현재 집중 목표 (지금 가장 신경 쓰는 것)",
};

export function buildSynthesizePrompt(args: {
  signals: string;
  document?: string;
  transcript?: { role: string; content: string }[];
  current?: BriefSections;
  userPrompt?: string;
}): string {
  const lines = [
    "당신은 Connectum의 '서비스 브리프' 작성자입니다. 한 서비스의 맥락을 6개 섹션으로 정리합니다.",
    "이 브리프는 다른 LLM(내장 CRM 채팅)이 소비하므로, 각 섹션을 명확·고밀도·모호성 없는 자연어로 쓰세요.",
    "추측 금지: 입력으로 알 수 없는 섹션은 빈 문자열(\"\")로 두세요(거짓을 지어내지 마세요).",
    "브리프는 유저의 언어(한국어/영어)로 작성하세요.",
    "",
    "섹션:",
    ...BRIEF_SECTIONS.map((k) => `- ${k}: ${SECTION_LABELS[k]}`),
    "",
    "[연동/데이터 시그널]", args.signals,
  ];
  if (args.current) {
    lines.push("", "[현재 브리프]", JSON.stringify(args.current));
  }
  if (args.userPrompt) {
    lines.push(
      "",
      "[유저 수정 지시]",
      args.userPrompt,
      "유저가 명시적으로 바꾸라고 한 섹션만 갱신하고 나머지는 그대로 보존하세요.",
    );
  }
  if (args.document) {
    lines.push("", "[첨부 문서]", args.document.slice(0, 24000));
  }
  if (args.transcript?.length) {
    lines.push(
      "",
      "[인터뷰 대화]",
      args.transcript.map((m) => `${m.role}: ${m.content}`).join("\n"),
    );
  }
  lines.push(
    "",
    "다음 JSON만 출력하세요(코드펜스·설명·머리말 금지):",
    '{"one_liner":"...","icp":"...","activation":"...","signal_glossary":"...","business_model":"...","current_focus":"..."}',
  );
  return lines.join("\n");
}

export function buildInterviewPrompt(args: {
  signals: string;
  transcript: { role: string; content: string }[];
  targetSections?: SectionKey[];
}): string {
  const targets = (args.targetSections?.length ? args.targetSections : BRIEF_SECTIONS)
    .map((k) => `- ${k}: ${SECTION_LABELS[k]}`);
  return [
    "당신은 서비스 맥락을 캐내는 온보딩 인터뷰어입니다. 원칙:",
    "1) 한 번에 한 질문만. 2) 객관식이 가능한 질문은 옵션을 제시. 3) 시그널로 이미 알 수 있는 건 묻지 않음.",
    "4) 모호한 답은 구체화를 요구('고객이 누구?'에 '헬스케어 기업들'은 답이 아님 — 역할·상황을 캐묻기).",
    "5) 유저의 언어(한국어/영어)로 질문.",
    "아래 섹션을 채우기 위한 정보를 얻는 게 목표입니다. 충분히 모였으면 종료하세요.",
    "",
    "[채울 섹션]", ...targets,
    "",
    "[연동/데이터 시그널]", args.signals,
    "",
    "[지금까지 대화]",
    args.transcript.length ? args.transcript.map((m) => `${m.role}: ${m.content}`).join("\n") : "(없음)",
    "",
    "다음 JSON만 출력하세요(코드펜스·설명 금지).",
    '아직 물을 게 있으면: {"question":"...","options":["...","..."]}  (options는 객관식일 때만, 생략 가능)',
    '충분하면: {"done":true}',
  ].join("\n");
}
