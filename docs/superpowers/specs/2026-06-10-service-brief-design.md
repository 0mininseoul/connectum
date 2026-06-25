# 서비스 브리프 (Service Brief) — 설계 스펙

> Historical note (2026-06-25): this spec predates the local-first AI implementation. Service brief UX concepts may still be useful, but any implementation must use the current local-first trust boundary in `AGENTS.md`: local storage, Keychain tokens, no maintainer-hosted AI proxy, and no default telemetry.

작성일: 2026-06-10
상태: 설계 확정, 구현 예정 (별도 브랜치)

## 1. 문제와 목표

Connectum 내장 AI 채팅(`ai-chat` 엣지 함수, Claude OAuth)은 현재 유저 **데이터**는 알지만 **서비스가 무엇인지**는 전혀 모른다. `ai-chat/index.ts`의 `systemPrompt()`에 주입되는 컨텍스트는 `get_service_overview` 하나뿐이고, 그것은 순수 정량 데이터(유저 수, contact_status 분포, 최근 7일 가입, 컬럼 스키마)다. 제품·고객·핵심 행동의 **질적 맥락**이 없어 전략적/유의미한 대화가 불가능하다.

목표: 유저가 자기 서비스의 맥락을 쉽게 주입하게 하여, AI 채팅이 "이 서비스가 무엇이고 누구를 위한 것이며 무엇이 중요한지"를 알고 답하도록 만든다.

## 2. 핵심 개념 — 하나의 AI-유지 산출물

서비스마다 **"서비스 브리프"** 하나. 구조화된 6개 섹션의 자연어 텍스트로, **Claude가 작성·유지**한다.

핵심 원칙:
- **직접 텍스트 편집 없음.** 유저는 프롬프트(자연어 의도)만 입력하고, Claude가 판단하여 브리프를 재작성한다. 브리프는 다운스트림 LLM(채팅)이 가장 잘 이해하는 포맷으로 유지되어야 하므로, 사람이 원문을 직접 고치면 품질이 떨어진다.
- **생성과 수정이 같은 연산.** 자동 초안 / 문서 추출 / 인터뷰 / 프롬프트 수정 — 모두 "현재 입력으로 6섹션을 산출하라"는 동일한 Claude 호출의 변형이다.
- **프로바이더: Claude.** 기존 `ai-chat`의 OAuth 경로(`_shared/claude_env.ts`, `_shared/claude_token.ts`, `claudeHeaders()` + Claude Code identity 첫 블록 규칙)를 재사용한다. Gemini는 쓰지 않는다.

## 3. 브리프 스키마 (6 섹션)

`sections` jsonb, 각 값은 문자열(자연어):

| 키 | 섹션 | 담는 것 |
|----|------|---------|
| `one_liner` | 한 줄 소개 | 이 서비스가 뭘 하는지 1–2문장 |
| `icp` | 타깃 고객(ICP) | 누구를 위한 건지, 주요 세그먼트 |
| `activation` | 핵심 활성화·성공 기준 | "제대로 쓴다"는 게 뭔지, aha moment, 핵심 지표 |
| `signal_glossary` | 핵심 행동·상태 신호의 의미 | 주요 `event_type` **또는** 컬럼/상태가 비즈니스적으로 뭘 뜻하는지 |
| `business_model` | 비즈니스 모델 | 어떻게 돈 버는지, 무료/유료, 전환 포인트 |
| `current_focus` | 현재 집중 목표 | 지금 가장 신경 쓰는 것 (온보딩 전환·리텐션·세그먼트 등) |

`signal_glossary`는 일반화된 섹션이다 (4절 참조). 채팅 우선순위에 가장 영향이 큰 것은 `signal_glossary`(행동 해석)와 `current_focus`(대화 관점).

## 4. 시그널 수집과 우아한 degrade (로그 없는 경우)

유저가 Supabase만 연동하고 Amplitude/Axiom을 연동하지 않으면 **이벤트 로그가 없을 수 있다.** 브리프 구조는 이를 견뎌야 한다.

`service-brief` 함수는 `service_id`로 **가용 시그널**을 수집한다:
- **항상 가능**: `service.name`, `service.supabase_project_name`, `service_table`의 user_table `column_map`/`display_columns`(컬럼명/구조)
- **분석 연동이 있고 이벤트가 있을 때만**: `crm_user_event`에서 상위 N개 `event_type`(빈도순)
- **연결 플래그**: supabase / amplitude / axiom 각각 연동 여부

`signal_glossary` 시드 규칙:
- 이벤트가 있으면 → `event_type` 목록에서 시드
- Supabase만 있으면 → 컬럼/상태에서 시드 (예: `plan`=요금제, `onboarded_at`=온보딩 완료 시점)

인터뷰도 적응한다: 로그가 없으면 이벤트 관련 질문을 건너뛰고 컬럼/상태 기반으로 묻는다. 항상 "추론으로 알 수 없는 것 + 현재 연결 상황에 맞는 것"만 질문한다.

## 5. 통합 원시 연산 — `service-brief` 엣지 함수

신규 함수 `supabase/functions/service-brief/`. 기존 Claude 플러밍 재사용. 2개 모드(요청 본문 `mode`):

### 5.1 `synthesize`
입력: `{ service_id, mode:"synthesize", document?, transcript?, current_sections?, user_prompt? }`
출력: `{ sections: {6키}, gaps: string[] }`

함수는 항상 시그널을 수집해 프롬프트에 주입한 뒤, 들어온 입력 조합으로 6섹션을 산출한다:
- **autodraft**: 입력 없음(시그널만) → 초안
- **extract**: `document` → 문서에서 추출
- **interview 종료**: `transcript` → 대화 종합
- **prompt-edit**: `current_sections` + `user_prompt` → 현재 브리프를 의도대로 재작성

`gaps`: 산출 후에도 구조적으로 빈약/누락된 섹션 키 배열. 추출 후 자동 인터뷰 트리거에 사용.

프롬프트 설계 노트: Claude에게 각 섹션을 다운스트림 LLM 소비에 최적화된 **명확·고밀도·모호성 없는** 자연어로 쓰게 한다. 추측 금지(모르면 빈 값 + gaps 보고). prompt-edit 시 유저가 건드리지 않은 섹션은 보존.

### 5.2 `interview_step`
입력: `{ service_id, mode:"interview_step", transcript, target_sections? }`
출력: `{ question, options?: string[] } | { done: true }`

`target_sections`가 주어지면(gap 채우기) 그 섹션만 겨냥한다. 인터뷰 방법론은 세 스킬의 정수를 옮긴 전용 프롬프트:
- **brainstorming**: 한 번에 한 질문, 객관식 우선, 종합→확인 리듬
- **spec**: 추론으로 알 수 있는 건 묻지 않음(시그널 선반영), 끝에 확인
- **office-hours(startup)**: "구체성이 유일한 화폐" — 모호한 답은 되묻기, ICP/웨지 프레이밍

스킬 파일을 문자 그대로 복사하지 않는다(telemetry·brain-sync 등 운영 스캐폴딩은 소비자 온보딩에 부적합). 메커니즘만 추려 서버사이드 프롬프트 상수로 작성.

대화는 짧게(목표 5–8 질문, 빈 섹션만 채우면 더 짧음). `done`이면 클라이언트가 `synthesize`(transcript 포함)를 호출해 최종 브리프 산출.

### 5.3 `ai-chat` 주입 변경
`ai-chat/index.ts`의 `systemPrompt()`에 브리프를 **새 캐시 블록**으로 추가한다(기존 정량 overview 블록은 유지). `status='ready'`일 때만 주입하고 `empty`면 주입하지 않는다. `cache_control: ephemeral` 적용.

## 6. 데이터 모델

신규 테이블 `public.service_brief` (service와 1:1). 마이그레이션 `supabase/migrations/<ts>_service_brief.sql`.

```sql
create table public.service_brief (
  service_id uuid primary key references public.service(id) on delete cascade,
  sections jsonb not null default '{}'::jsonb,  -- {one_liner, icp, activation, signal_glossary, business_model, current_focus}
  status text not null default 'empty',          -- 'empty' | 'ready'
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
```

- 원본 문서는 저장하지 않는다(노이즈·프라이버시·YAGNI). 추출 결과(sections)만 보관.
- `status`: 프롬프트 기반 모델이라 명시적 "확인" 단계가 없다. 6섹션이 전부 비면 `empty`, 하나라도 채워지면 `ready`. 엣지 함수는 `adminClient()`(service role)로 접근하므로 RLS는 기존 service-scoped 테이블과 동일 정책(authenticated 허용).

## 7. 흐름

### 7.1 서비스 생성 직후 (온보딩 막지 않음)
서비스 생성은 기존대로 끝낸다. 직후 "이 서비스에 대해 알려주기" 카드(건너뛰기 가능):
> "이 서비스에 대해 알려주면 AI가 훨씬 똑똑해집니다"
> [문서로 채우기] [질문으로 채우기] [나중에]

### 7.2 문서 경로 (주 경로)
붙여넣기/파일 → 텍스트 확보 → `synthesize(document)` → `gaps` 검사 → gaps 있으면 `interview_step(target_sections=gaps)` 루프 → `synthesize(transcript)` 최종 → 표시. (#2 요구사항)

### 7.3 인터뷰 경로
`interview_step` 루프(시그널로 시드) → `done` → `synthesize(transcript)` → 표시.

### 7.4 자동 초안 (받쳐주기)
문서/인터뷰를 건너뛰어도 빈 화면이 안 되게, 필요 시 `synthesize`(시그널만)로 초안을 깐다.

### 7.5 프롬프트 수정 (상시)
어떤 경로로 만들었든, 유저가 프롬프트 입력 → `synthesize(current_sections + user_prompt)` → 재작성. (#1 요구사항)

## 8. 프론트엔드 (SwiftUI)

신규 `apps/Connectum/Connectum/Features/ServiceBrief/`:
- `ServiceBriefView` — 6섹션 **읽기 전용** 렌더 + 프롬프트 입력 박스 + 문서 첨부 + 인터뷰 진입. 직접 필드 편집 없음. (선택: "저장된 원문 보기" 읽기 전용 토글)
- `ServiceBriefViewModel` (`@Observable`) — 로드/저장, 4개 작업(autodraft/extract/interview/prompt-edit) 호출, gap→인터뷰 오케스트레이션.
- 문서 입력: 붙여넣기 `TextEditor` + `.fileImporter`(.md/.txt/.pdf). PDF는 **PDFKit**으로 텍스트 추출. 스캔 PDF(텍스트 없음)는 안내 후 붙여넣기/인터뷰로 폴백.
- 인터뷰 UI: `AIChatView`의 턴 UI 패턴 재사용, 객관식 옵션은 버튼.
- 엣지 함수 호출: `SupabaseClientProvider.functionsURL(for:)` + `authHeaders()` 패턴 재사용. 데이터 접근은 `CrmRepository`(`CrmDataProviding`) 확장.

진입점 3곳:
1. 서비스 생성 직후 카드(7.1)
2. AI 채팅 패널: 브리프 비었거나 빈약하면 상단에 은근한 배너("AI가 이 서비스를 더 잘 이해하게 하기 →")
3. 서비스 설정에서 "서비스 브리프" 진입

## 9. 에러 처리
- `synthesize`/`interview_step` 실패 → 재시도 + (인터뷰면) 수동 진행 폴백. Claude 401/403 → 기존 재연동 흐름(`ai_reauth_required`) 재사용.
- 스캔 PDF/텍스트 없음 → 안내 후 붙여넣기·인터뷰 유도.
- 시그널 0(연결 직후) → autodraft 최소화, 인터뷰가 전적으로 유저 답에 의존.
- `synthesize`가 JSON 비반환 → `extractJSON` 유사 가드(kpi-preview 패턴) + 422.

## 10. 테스트
- Edge(Deno, 기존 `tools.test.ts`/`kpi_spec.test.ts` 패턴):
  - 시그널 수집: 이벤트 유/무 분기, Supabase-only degrade
  - `synthesize`: 모드별 입력 조합 → 6섹션 + gaps, JSON 파싱 가드, prompt-edit 시 비대상 섹션 보존
  - `interview_step`: 다음 질문/옵션/종료, target_sections 한정
- Swift(기존 `AIChatStreamParserTests` 패턴):
  - VM 로드/저장, gap→인터뷰 오케스트레이션 상태 전이
  - PDFKit 텍스트 추출, 빈 텍스트 폴백
  - 객관식 옵션 처리

## 11. 단계화 (가치 순서, 한 번에 끝까지)
- **P1**: 마이그레이션 + 시그널 수집 + `synthesize`(autodraft/prompt-edit) + `ai-chat` 주입 + 읽기전용 표시 + 프롬프트 박스 + 진입점 → 이것만으로 AI가 즉시 똑똑해지고 상시 수정 가능
- **P2**: 문서 추출(붙여넣기 + .md/.txt/.pdf) + gap 검사
- **P3**: 가이드 인터뷰(`interview_step`) + gap 자동 채우기 오케스트레이션

세 단계 모두 이 순서로 구현하되 단계별 컨펌 없이 진행. (#3)

## 12. 범위 밖 (YAGNI)
- 원본 문서 저장/버전 관리
- .docx 등 PDF/MD/TXT 외 파일 파싱
- 다국어 브리프 분리(브리프는 유저 언어로 유지)
- 브리프 변경 이력/감사 로그
- 직접 텍스트 편집 UI (의도적으로 제외 — #1)

## 13. 가정
- 워크스페이스에 단일 Claude OAuth 계정(`ai_account`)이 연결되어 있다(기존 `ai-chat`과 동일 전제).
- 브리프 Claude 호출은 `CLAUDE_MODEL`(기본 claude-sonnet-4-6)을 재사용한다.
- Claude OAuth 토큰 사용 시 시스템 프롬프트 첫 블록 = Claude Code identity 규칙을 준수한다(`ai-chat`과 동일).
