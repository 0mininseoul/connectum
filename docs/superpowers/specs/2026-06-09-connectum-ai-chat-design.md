# Connectum AI Chat — 설계 스펙

- 작성일: 2026-06-09
- 상태: 승인됨 (구현 진행)
- 범위: Connectum macOS 앱에 데이터-그라운디드 AI Chat 추가 + Claude 구독 OAuth 우회 연동

## 1. 목표 / 비목표

### 목표
- 사이드바에서 선택된 **현재 서비스의 모든 CRM 데이터를 이해한 상태**로 대화하는 AI Chat.
- **Claude API 키가 아닌 Claude 구독(Pro) OAuth 토큰**으로 동작 (개인용, 본인 계정).
- macOS 우측 **inspector 슬라이드 패널**, **⌘I 단축키**로 토글.
- 기존 앱 아키텍처(Edge Function 프록시 + Vault + Raycast 디자인 토큰)와 일관.

### 비목표 (이번 범위 아님 / YAGNI)
- 대화 영구 저장(세션 메모리만; `ai_message` 테이블은 후속).
- 워크스페이스 전체(여러 서비스) 교차 질의 — 현재 선택 서비스로 한정.
- 공식 API 키 과금 경로(폴백 분기만 코드에 남김, 활성화는 후속).
- 멀티-계정 Claude 연결(단일 워크스페이스 전역 1계정).

## 2. 사용자 결정 사항 (확정)

| 항목 | 결정 |
|---|---|
| UI 배치 | 우측 슬라이드 패널 (SwiftUI `.inspector`), ⌘I 토글 |
| 데이터 범위 | 현재 선택 서비스 전체 (tool-use로 드릴다운) |
| 실행 위치 | Supabase Edge Function 프록시, 토큰은 Vault |

## 3. 아키텍처 개요

```
[macOS 앱]                          [Edge Functions]                [Anthropic]
 AIChatView (.inspector, ⌘I)
   ├─ 대화 전송 (SSE, URLSession) ─▶ ai-chat
   │                                  ├─ claude_token.ts: Vault 토큰 로드/갱신
   │                                  ├─ 시스템 프롬프트 구성
   │                                  │   (Claude Code 스푸프 블록 + 서비스 컨텍스트)
   │                                  ├─ tool-use 루프 ◀──┐
   │                                  │   ├ get_service_overview │ api.anthropic.com
   │                                  │   ├ search_users         │ /v1/messages
   │                                  │   ├ get_user_detail      │ (Bearer + oauth beta)
   │                                  │   ├ get_user_events      │
   │                                  │   └ get_metrics ─────────┤
   │                                  │   (adminClient,          │
   │                                  │    service_id 스코프)     │
   │  ◀── SSE: status/text/done ──────┤◀─────────────────────────┘
 ClaudeConnectCard (연동 탭)
   └─ 루프백 + PKCE ───────────────▶ ai-connect (코드→토큰 교환 → Vault)
```

기존 패턴 재사용:
- OAuth 루프백 수신: `SupabaseOAuthLoopbackReceiver`(있음) → 범용화하여 재사용.
- 토큰 저장/갱신: `oauth-supabase` + `supabase_token.ts` 패턴을 `claude_token.ts`로 복제.
- LLM 호출: `summarize-user`의 "데이터 모아 프롬프트 구성 → 호출" 패턴 확장(대화·tool 루프).
- 시크릿: `vault.ts`(`vault_get`/`vault_set`), 테이블엔 ref만.

## 4. Claude 구독 OAuth 우회 메커니즘

Claude Code가 사용하는 공개 OAuth 클라이언트 + PKCE(시크릿 없음) 흐름.

### 4.1 상수 (config / 환경변수로 주입, 하드코딩 금지)
- `CLAUDE_OAUTH_CLIENT_ID` — Claude Code 공개 client_id.
- `CLAUDE_OAUTH_AUTHORIZE_URL` — `https://claude.ai/oauth/authorize`.
- `CLAUDE_OAUTH_TOKEN_URL` — `https://console.anthropic.com/v1/oauth/token`.
- `CLAUDE_OAUTH_SCOPE` — 예: `org:create_api_key user:profile user:inference`.
- `CLAUDE_API_URL` — `https://api.anthropic.com/v1/messages`.
- `CLAUDE_OAUTH_BETA` — `oauth-2025-04-20`.
- `CLAUDE_MODEL` — 기본 `claude-sonnet-4-6`(구독 한도/툴루프 경제성), `claude-opus-4-8`로 교체 가능.
- **검증 필요(2단계 라이브 확정):** 정확한 client_id, 허용 redirect_uri(루프백 `localhost` vs `127.0.0.1`, 포트), scope 문자열, OAuth 엔드포인트가 수락하는 model id. 이 값들은 앱 `config.json` / Edge `secrets`에서 교체 가능해야 한다.

### 4.2 인증 플로우 (앱 + Edge)
1. 앱: `code_verifier`(43~128 char) + `code_challenge=BASE64URL(SHA256(verifier))` + `state` 로컬 생성 (`SecRandomCopyBytes`).
2. 앱: authorize URL 구성(`response_type=code`, `code_challenge`, `code_challenge_method=S256`, `state`, `scope`, `redirect_uri`=루프백) → 브라우저 오픈.
3. 앱: 루프백 리스너로 `code`/`state` 수신, `state` 일치 검증.
4. 앱→Edge `ai-connect`: `{ code, code_verifier, redirect_uri }` 전송.
5. Edge: `CLAUDE_OAUTH_TOKEN_URL`에 `grant_type=authorization_code` + `code` + `code_verifier` + `client_id` + `redirect_uri` POST → `access_token`/`refresh_token`/`expires_in`.
6. Edge: 토큰을 Vault에 저장(`claude_oauth_access_*`, `claude_oauth_refresh_*`), `ai_account` 행에 ref + `expires_at` 기록.

### 4.3 토큰 사용 (messages 호출)
- `POST $CLAUDE_API_URL`
- 헤더: `Authorization: Bearer <access>`, `anthropic-version: 2023-06-01`, `anthropic-beta: oauth-2025-04-20`, `content-type: application/json`. (**`x-api-key` 금지**)
- 바디: `model`, `max_tokens`, `system`(아래), `messages`, `tools`, `stream`.
- **시스템 프롬프트 첫 블록은 반드시 Claude Code 정체성**으로 시작:
  ```
  system: [
    { type:"text", text:"You are Claude Code, Anthropic's official CLI for Claude." },
    { type:"text", text:"<Connectum 실제 지시 + 서비스 컨텍스트>", cache_control:{type:"ephemeral"} }
  ]
  ```
- 첫 블록 누락 시 구독 토큰이 거부될 수 있음. 실제 Connectum 지시는 두 번째 블록.

### 4.4 토큰 갱신 (`claude_token.ts`)
- `tokenForClaudeAccount(accountId)`: Vault에서 access 로드 → `expires_at`가 5분 내면 refresh.
- refresh: `CLAUDE_OAUTH_TOKEN_URL`에 `grant_type=refresh_token` + `refresh_token` + `client_id` POST → 새 access(있으면 refresh) Vault 갱신 + `ai_account.expires_at` 업데이트.
- `supabase_token.ts`와 동일 구조, 시크릿 없음(PKCE 공개 클라이언트).

### 4.5 공식 API 키 폴백 (분기만, 비활성)
- `CLAUDE_API_KEY` 환경변수가 있으면 OAuth 대신 `x-api-key` + (oauth beta 제거)로 호출하는 분기를 `claude_request.ts`에 둔다. 기본 비활성. OAuth 경로가 깨질 때 한 줄로 전환.

## 5. 데이터 그라운딩 (tool 정의)

`ai-chat`이 Claude에 노출하는 읽기 전용 tool들. 모두 `adminClient`로 **요청 body의 `service_id`에 스코프**. 임의 SQL 미노출.

| tool | input | 반환(요약) |
|---|---|---|
| `get_service_overview` | — | 서비스명, 총 유저수, contact_status 분포, 최근 7일 가입수, 표시 컬럼 스키마 |
| `search_users` | `query?`, `contact_status?`, `limit?(≤50)` | 매칭 유저 목록(id, email, display_name, contact_status, ai_summary 일부) |
| `get_user_detail` | `crm_user_id` | supabase_profile + amplitude_profile + ai_summary + 메모/채널기록 |
| `get_user_events` | `crm_user_id`, `limit?(≤50)` | 최근 이벤트(event_type, event_time, platform 등) |
| `get_metrics` | — | total/contacted/profiled/recentSignups (대시보드와 동일) |

- 대화 시작 시 시스템 두 번째 블록에 `get_service_overview` 결과 요약을 **자동 주입**(첫 tool 왕복 절감) — 토큰 효율 하이브리드.
- tool 결과 행수/길이 캡으로 토큰 폭주 방지(레이트리밋 보호).
- `crm_user_id`는 `crm_user.id`(uuid). search → detail/events 드릴다운 체인.

## 6. Edge Function `ai-chat` 동작

요청 body: `{ service_id: string, messages: [{role, content}] }` (대화 히스토리).

1. `tokenForClaudeAccount` 로 access 확보(없으면 401 `ai_not_connected`).
2. 시스템 프롬프트 구성: Claude Code 블록 + (서비스 overview 요약 + 행동 지침).
3. tool-use 루프 (수동, 최대 N=8 라운드):
   - `/v1/messages` 호출(tools 포함, 비스트리밍) → `stop_reason`.
   - `tool_use`면 각 tool을 service_id 스코프로 실행 → `tool_result` 추가 → 반복.
   - 그 사이 앱에 SSE `status`(예: `"유저 조회 중"`) 방출.
   - `end_turn`이면 마지막 어시스턴트 응답을 SSE `text` 델타로 스트리밍(이 라운드만 `stream:true`).
4. SSE 이벤트: `status`(tool 알림) → `text`(델타) → `done`(usage 포함) / `error`.
5. `max_tokens` 기본 4096(비스트리밍 라운드), 최종 라운드 스트리밍.

레이트리밋/오류: 429/5xx는 메시지로 SSE `error` 방출(앱이 토스트). OAuth 거부(401/403)는 `ai_reauth_required` 코드.

## 7. 앱 UI/UX

### 7.1 패널
- `MainShell` detail에 `.inspector(isPresented: $shell.aiPanelVisible) { AIChatView(serviceId: shell.selectedDataServiceId) }`.
- ⌘I 토글, Esc/⌘I 닫기. 열리면 입력창 포커스.
- 구성: 헤더(현재 서비스명 "Archy 기준") · 메시지 스트림(마크다운) · tool status 칩 · 입력창(⏎ 전송, ⇧⏎ 줄바꿈).
- Palette/Spacing/Typography 토큰만 사용, 새 색 없음.
- 서비스 전환 시 헤더의 기준 서비스 갱신. 드래프트 서비스면 비활성 안내.

### 7.2 상태/모델
- `ShellModel`에 `var aiPanelVisible = false` + `toggleAIPanel()`.
- `AIChatViewModel`(@MainActor @Observable): `messages: [ChatMessage]`, `isStreaming`, `statusText`, `inputText`, `send()`, `cancel()`. 세션 메모리(앱 켜진 동안).
- `ChatMessage { id, role(.user/.assistant), text, isStreaming }`.

### 7.3 스트리밍 클라이언트
- Supabase `functions.invoke`는 스트리밍 약함 → 함수 URL에 raw `URLSession.bytes(for:)` SSE 호출. `Authorization: Bearer <supabase anon/user jwt>` + `apikey` 헤더 수동 부착(기존 SupabaseClientProvider에서 값 획득).
- 비스트리밍 폴백(전체 응답 await) 포함.

### 7.4 단축키
- `ConnectumCommands`에 ⌘I "AI 채팅" 추가(기존 ⌘N/F/1·2·3/±/0/⇧L/₩와 무충돌). `shell.toggleAIPanel()`.

### 7.5 연동 카드
- 연동 탭에 "Claude (AI)" 카드: 연결 상태 표시 + "Claude 계정 연결"/"연결 해제". Supabase 연결 카드와 동일 UX. 워크스페이스 전역(서비스당 아님)임을 라벨로 명시.
- 미연결 시 AIChatView는 "Claude 계정을 연결하세요 → 연동 탭" CTA.

## 8. 스키마 / 마이그레이션

새 마이그레이션 `20260609_ai_account.sql`:
```sql
create table public.ai_account (
  id uuid primary key default gen_random_uuid(),
  label text not null default 'Claude',
  account_name text,
  access_token_ref text not null,
  refresh_token_ref text,
  expires_at timestamptz,
  scope text,
  created_at timestamptz not null default now()
);
alter table public.ai_account enable row level security;
-- 인증 사용자 읽기(메타만), 쓰기는 service_role(Edge)만. 기존 *_account RLS 패턴 미러.
create policy ai_account_select on public.ai_account for select to authenticated using (true);
```
(기존 `supabase_account` RLS 패턴을 그대로 따른다. 토큰 값은 Vault에만.)

## 9. 파일 변경 목록

### Supabase (Deno)
- `supabase/functions/_shared/claude_oauth.ts` — authorize/token/refresh 요청 빌더 + 파서 + PKCE 검증(단위테스트 대상).
- `supabase/functions/_shared/claude_token.ts` — `tokenForClaudeAccount` (Vault + refresh).
- `supabase/functions/_shared/claude_request.ts` — messages 호출(헤더/스푸프/폴백 분기), tool 루프 헬퍼.
- `supabase/functions/_shared/claude_env.ts` — 상수 env 리졸버(`oauth_env.ts` 패턴).
- `supabase/functions/ai-connect/index.ts` — 코드→토큰 교환→Vault→`ai_account`.
- `supabase/functions/ai-chat/index.ts` — 대화 + tool 루프 + SSE.
- `supabase/functions/ai-chat/tools.ts` — 5개 tool 정의 + 실행(service_id 스코프, 단위테스트 대상).
- `supabase/migrations/20260609_ai_account.sql`.
- `supabase/config.toml` — `ai-chat`, `ai-connect` 함수 등록(필요 시 `--no-verify-jwt`는 쓰지 않음; 사용자 JWT로 호출).

### 앱 (Swift)
- `Features/AIChat/AIChatView.swift` — inspector 패널 UI.
- `Features/AIChat/AIChatViewModel.swift` — 상태 + 전송/스트리밍.
- `Features/AIChat/ClaudeOAuthFlow.swift` — PKCE 생성 + authorize URL + 루프백(기존 리시버 재사용/범용화).
- `Features/AIChat/AIChatStreamClient.swift` — URLSession SSE 파서.
- `App/ShellModel.swift` — `aiPanelVisible` + `toggleAIPanel()`.
- `App/RootView.swift` — `.inspector` 부착.
- `App/AppCommands.swift` — ⌘I.
- `Data/CrmRepository.swift` — `connectClaude(code, verifier, redirectURI)`, `fetchAIAccount()`, `disconnectClaude(id)`; (스트리밍은 별도 클라이언트).
- `Features/Connections/ConnectionsView.swift` — Claude 연동 카드.
- `Models/CrmModels.swift` — `ChatMessage`, `AIAccount` 등.
- `project.yml`은 폴더 글롭이면 자동 포함(신규 파일 확인).

## 10. 빌드 순서 (단계별 검증)

1. **마이그레이션 + `claude_oauth.ts`/`claude_token.ts`** — PKCE/토큰 빌더·갱신 단위테스트(deno). `supabase migration up`.
2. **`ai-connect` + 앱 PKCE/루프백 + 연동 카드** — 실제 Claude 계정 연결 **라이브 검증**(4.1 상수 확정).
3. **`ai-chat` 최소판**(tool 없이, Claude Code 스푸프 + overview만, 비스트리밍) — 1턴 응답 검증(스푸프 헤더/모델 id 확정).
4. **tool-use 루프 + 5 tool** — "가장 최근 가입 유저?" / "contacted 안 된 유저 수?" 류 검증.
5. **inspector UI + ⌘I + 마크다운 + status 칩**.
6. **SSE 스트리밍 전환** + 폴백.

각 단계: 브랜치 → TDD(가능 영역) → 검증 → main 머지.

## 11. 리스크 / 고지

- **약관:** 구독 OAuth 토큰의 임의 API 사용은 Anthropic 약관 위반 소지 + 계정 제재 가능성(이론). 개인용·비공개·본인 계정 전제로 진행.
- **취약성:** "You are Claude Code" 요구·beta 헤더·model id·엔드포인트 변경 시 깨짐 → `claude_request.ts`에 공식 API 키 폴백 분기 유지.
- **검증 필요 상수(§4.1):** 2단계에서 라이브 확정. 실패 시 manual-paste redirect(`console.anthropic.com/oauth/code/callback`) 폴백.
- **레이트리밋:** 구독 사용량 한도 → tool 결과 캡 + 대화 길이 캡 + tool 루프 N=8 상한.
- **보안:** 토큰은 Vault만, 테이블엔 ref. tool은 읽기 전용·service_id 스코프(데이터 경계 강제). Edge는 사용자 JWT 검증(익명 호출 차단).

## 12. 검증 기준 (완료 정의)

- 연동 탭에서 Claude 계정 연결 → `ai_account` 1행 + Vault 토큰 존재.
- ⌘I로 우측 패널 토글, 입력→응답 스트리밍 표시.
- "방금 가입한 유저 알려줘" → tool 호출로 실제 `crm_user` 데이터 기반 응답.
- 다른 서비스 선택 후 동일 질문 → 해당 서비스 데이터로 응답(스코프 격리).
- deno 테스트 그린, xcodebuild 그린.
