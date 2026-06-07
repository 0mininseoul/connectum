# Connectum — 기획/설계 문서 (Design Spec)

- **작성일**: 2026-06-07 (Mac 네이티브 피벗 반영 — 웹/PWA 안 대체)
- **상태**: 설계 확정 (구현 계획 작성 대기)
- **한 줄 정의**: 팀이 운영하는 여러 서비스별로, 가입 유저의 CRM 데이터를 자동 수집·병합하고 수동으로 운영(컨택/기록/메모)할 수 있는 **네이티브 macOS 앱** CRM 툴.

---

## 1. 개요 (Overview)

Connectum은 우리 팀이 운영하는 **여러 서비스**의 유저 데이터를 한곳에서 관리하는 운영 CRM 도구다. 두 종류의 데이터를 **자동 수집**한다.

1. **Supabase 테이블 데이터** — 서비스별 가입 유저 정보 (다중 Supabase 계정/프로젝트)
2. **Amplitude 행동 데이터** — 라이브 이벤트 + 유저별 프로필 속성(OS/브라우저 등)

여기에 **Axiom 런타임 로그**(기술/에러 신호)를 더하고, **Vertex AI Gemini**가 유저별 3줄 총평을 생성한다. 수집된 데이터는 **대시보드**와 **운영 DB**로 구성되며, 팀원이 직접 **컨택 여부·채널 기록·히스토리·커스텀 페이지/뷰**를 수동 관리한다.

- **형태**: **네이티브 macOS 앱 (SwiftUI)** — 사용성 최우선. 처음부터 네이티브로 개발
- **백엔드/DB**: Supabase (Connectum 자체 프로젝트) — Edge Functions로 동기화까지 서버사이드 처리
- **디자인**: Raycast 디자인 시스템 (단일 다크 모드). *Raycast 자체가 네이티브 macOS 앱이므로 정합성 높음*
- **배포**: 공증(notarized) DMG 직접 배포 (Developer ID). 내부 팀 도구라 Mac App Store는 불필요(추후 재검토)
- **플랫폼**: 초기 **macOS 전용**. Windows는 추후 별도 검토(SwiftUI 비공유 → 재작성 또는 크로스플랫폼 재검토)

---

## 2. 목표 & 비목표

### 목표
- 서비스별 유저 CRM 데이터의 **자동 수집·병합·동기화** (서버사이드, 앱이 꺼져 있어도 동작)
- 유저별 **운영(컨택/기록/메모/히스토리)** 의 수동 관리
- 유저별 **AI 3줄 총평** 자동 제공
- **노션 수준의 커스텀 뷰**(필터/정렬/그룹/뷰타입)
- Raycast 미학의 빠르고 조밀한 **네이티브** 도구형 UX (Command-K 1급 패턴)

### 비목표 (YAGNI)
- 범용 옵저버빌리티/APM 대체 (Axiom는 CRM 맥락 보강 용도로만)
- 소스 데이터의 양방향 쓰기(write-back) — 본 도구는 **읽기 중심**, 운영 데이터만 Connectum DB에 기록
- 외부 고객/엔드유저 노출 — 내부 팀 도구
- 마케팅 자동화/대량 발송
- **초기 Windows 지원** — macOS 우선, 추후 별도 검토

---

## 3. 핵심 결정 요약 (Decision Log)

| # | 항목 | 결정 |
|---|------|------|
| 1 | 서비스↔데이터 매핑 | **1 서비스 = 1 Supabase 프로젝트**, CRM 유저는 서비스별 독립 |
| 2 | 데이터 처리 방식 | Connectum 자체 Supabase로 **ETL 캐싱 + 주기 동기화** |
| 3 | 팀/권한 | **공유 워크스페이스**, 로그인 후 전원 보기/편집 (MVP). 역할/권한은 추후 |
| 4 | Phase 1 범위 | 두 연동(Supabase+Amplitude) 적재 + 운영 DB + 유저 상세/수동 기록 |
| 5 | Supabase 연동 | **OAuth (Management API)** — 프로젝트/테이블 자동 목록, 다중 계정 |
| 6 | Amplitude 수집 범위 | **전체 이벤트 타임라인** (단, **매칭 유저 한정**) |
| 7 | 동기화 범위 (무료플랜) | **매칭 유저 한정 + 가능한 전체 기간** (보존 한도 내) |
| 8 | AI 총평 | **Vertex AI Gemini**, 병합 데이터 기반, 동기화 시 자동 + 수동 재생성, 3줄 |
| 9 | 유저 페이지 커스텀 | **자유 블록 편집** (노션 페이지형) |
| 10 | Axiom 로그 | 포함 (넓은 범위: 유저 신호 + 서비스 헬스 미니 대시보드), **Phase 3** |
| 11 | 조인 키 | **Amplitude `user_id` = Supabase user id** (기본값, 서비스별 오버라이드 옵션) |
| 12 | **앱 프레임워크** | **SwiftUI 네이티브 macOS** (가장 네이티브한 사용성) |
| 13 | **동기화 엔진** | **Supabase Edge Functions + pg_cron**(서버사이드). 수동 동기화는 앱이 Edge Function 호출 |
| 14 | Vertex 인증 | **운영자가 인프라 레벨 1회 인증**(서버 공용 크리덴셜, Edge Function에서 호출). 엔드유저 연동 불필요 |
| 15 | 인프라 | Supabase / Amplitude / Axiom 모두 **무료 플랜**. Vercel 미사용 |
| 16 | 폰트 | **Paperlogy로 통일** (한/영) |
| 17 | 국제화 | **한국어(기본) + 영어** i18n (네이티브 String Catalogs) |
| 18 | 배포 | **공증 DMG 직접 배포** (Developer ID), App Store 추후 검토 |

---

## 4. 시스템 아키텍처

```
┌──────────────────────────────────────────────────────────────┐
│  Connectum.app — 네이티브 macOS (SwiftUI / AppKit)            │
│  ├─ UI: Raycast 디자인 시스템 · Paperlogy · 다크 단일 · i18n   │
│  ├─ Command-K 팔레트 (네이티브 오버레이)                       │
│  ├─ supabase-swift: Auth / DB 읽기·쓰기 / Storage             │
│  └─ ASWebAuthenticationSession: 소스 OAuth 시작               │
└───────────────┬──────────────────────────┬───────────────────┘
                │ 읽기/쓰기 (RLS)            │ 수동 "지금 동기화" / OAuth code
                ▼                          ▼  (Edge Function 호출)
┌────────────────────────────────────────────────────────────┐
│  Connectum Supabase (백엔드)                                 │
│  ├─ Postgres: 운영 DB + 미러링 데이터                        │
│  ├─ Auth: 팀 로그인        ├─ Storage: 히스토리 이미지        │
│  ├─ Vault: 소스 토큰/키 + Vertex 키 암호화                   │
│  ├─ Edge Functions (Deno/TS): ETL · OAuth 토큰교환 · Vertex  │
│  └─ pg_cron + pg_net: 주기적으로 sync Edge Function 호출      │
└───────────────┬────────────────────────────────────────────┘
                │ Edge Function이 소스에서 당겨옴 (증분, 청크)
   ┌────────────┼───────────────┬──────────────┐
   ▼            ▼               ▼              ▼
[Supabase     [Amplitude     [Vertex AI     [Axiom
 Mgmt API]     Export/User    Gemini]        APL API]
 다중 계정     API]           3줄 총평        런타임 로그
                              (서버 공용 인증) (Phase 3)
```

핵심: **앱은 클라이언트**(읽기 + 편집 + 동기화 트리거)이고, **모든 외부 연동·동기화·AI 호출은 Supabase Edge Functions(서버사이드)** 에서 일어난다. 자격증명은 절대 클라이언트에 노출되지 않는다.

### 데이터 흐름 (동기화)
수동 "지금 동기화" 버튼도 동일 경로(앱 → Edge Function)를 사용한다.

1. **pg_cron**이 스케줄에 따라 `pg_net`으로 sync Edge Function을 호출 (앱 미실행 시에도 동작)
2. Edge Function이 `sync_cursor`(마지막 동기화 지점)를 읽어 **증분**으로 당김 — Edge Function 실행 시간 한도 회피를 위해 **청크 단위** 처리, 한 번에 못 끝내면 다음 실행이 이어감
3. **Supabase 소스**: Management API로 선택 테이블 행을 읽어 `crm_user`(지정 유저 테이블) + `mirrored_row`(기타 테이블)에 upsert
4. **Amplitude**: Export API로 이벤트 증분 적재 → **매칭 유저(`user_id`=Supabase id)만** `crm_user_event` + 프로필 속성(OS/브라우저/디바이스/지역/최근접속) 갱신
5. 데이터가 갱신된 유저는 Vertex Edge Function이 **Gemini**로 3줄 총평 재생성 (입력 해시가 바뀐 경우에만)
6. `sync_run`에 결과/통계/에러 기록 → 앱이 이를 읽어 마지막 동기화 시각·상태 표시 (선택: Supabase Realtime으로 실시간 갱신)

---

## 5. 데이터 모델

> Postgres(Connectum Supabase). 프레임워크와 무관(백엔드). 모든 테이블은 워크스페이스 범위 RLS로 격리. 시간 컬럼은 `created_at/updated_at` 공통.

### 연결/인증
- **`team_member`** — Connectum 팀원. Supabase Auth(`auth.users`)와 1:1. (이름, 이메일, 아바타)
- **`supabase_account`** — OAuth 연동된 Supabase 계정. `label`, `access_token`/`refresh_token`(Vault 참조), `expires_at`. **다중 행** 허용
- **`amplitude_account`** — Amplitude 프로젝트 자격증명. `label`, `api_key`/`secret_key`(Vault 참조)
- **`axiom_account`** — Axiom 자격증명. `label`, `api_token`(Vault 참조)
- (Vertex AI는 테이블 없음 — Vault/secret의 운영자 공용 크리덴셜)

### 서비스 구성
- **`service`** — 운영 서비스 1개. `name`, `supabase_account_id`, `supabase_project_ref`, `amplitude_account_id`(nullable), `axiom_account_id`(nullable), `axiom_dataset`(nullable), `join_key_config`(jsonb; 기본 `amplitude.user_id = supabase.id`)
- **`service_table`** — 서비스에서 적재할 선택 테이블(복수). `service_id`, `source_schema`, `source_table`, `role`(`user_table` | `related`), `column_map`(jsonb; user_id·email 등 매핑), `cursor_column`(증분 기준, 예 `updated_at`)

### 미러링 데이터 (소스 → 동기화)
- **`crm_user`** — **운영 DB의 핵심 아이템.** 한 행 = (service, 유저). 컬럼:
  - `service_id`, `source_user_id`(= Supabase id = Amplitude user_id)
  - `email`, `display_name`, 기타 표시 필드
  - `supabase_profile`(jsonb) — 유저 테이블 원본 행
  - `amplitude_profile`(jsonb) — OS/브라우저/디바이스/지역/최근접속 등
  - `contact_status`(enum: `not_contacted` | `contacted`; 추후 상태 확장 가능)
  - `custom_fields`(jsonb) — 커스텀 속성 값 (뷰에서 필터/정렬 대상)
  - `ai_summary`(text), `ai_summary_generated_at`, `ai_summary_input_hash`
  - `axiom_signals`(jsonb, Phase 3) — 최근 에러수/마지막 활동 등
  - `last_synced_at`
- **`crm_user_event`** — 매칭 유저의 Amplitude 이벤트 타임라인. `crm_user_id`, `event_type`, `event_time`, `props`(jsonb), `platform/os/browser`. 인덱스: `(crm_user_id, event_time desc)`. 보존 한도(prune) 정책 적용
- **`mirrored_row`** — 유저 테이블 외 선택 테이블의 범용 미러. `service_id`, `service_table_id`, `source_pk`, `data`(jsonb), `linked_crm_user_id`(nullable)

### 수동 운영 데이터 (편집 레이어)
- **`custom_field`** — 운영 DB/뷰용 속성 정의. `scope`(`workspace` | `service`), `service_id`(nullable), `name`, `type`(`text`|`select`|`multi_select`|`date`|`checkbox`|`url`|`number`|`person`), `options`(jsonb). 값은 `crm_user.custom_fields`(jsonb)에 저장
- **`page_block`** — 유저 상세 페이지의 **자유 블록 문서**. `crm_user_id`, `position`, `type`, `content`(jsonb). 블록 타입:
  - `channel_record` — `channel`(`email`|`kakao`|`sms`|`interview`|`memo`), `occurred_at`(날짜), `body`, `attachments`
  - 일반: `text`, `heading`, `image`, `divider`, `field_ref`(커스텀 속성 표시) 등
- **`history_entry`** — 히스토리 탭 항목. `crm_user_id`, `entry_date`(수동 입력), `image_url`(Storage), `memo`, `position`. UI에서 날짜별 섹션화

### 뷰/대시보드/동기화 상태
- **`view`** — 커스텀 뷰. `name`, `scope`(`workspace`|`service`), `config`(jsonb: `filters`, `sorts`, `visible_columns`, `group_by`, `view_type` `table`|`board`)
- **`dashboard_widget`** (Phase 2) — `service_id`(nullable), `type`, `config`(jsonb)
- **`sync_run`** — 동기화 실행 이력. `service_id`, `source`, `status`, `started_at`, `finished_at`, `stats`(jsonb), `error`
- **`sync_cursor`** — 증분 커서. `service_id`, `source`, `scope_key`(테이블/이벤트), `cursor_value`, `updated_at`

### 핵심 설계 포인트
노션처럼 한 유저는 **두 레이어**를 갖는다:
- **속성(properties)** — `custom_field` + `crm_user.custom_fields`(jsonb). 운영 DB 컬럼 & 커스텀 뷰의 필터/정렬 대상
- **페이지 본문(blocks)** — `page_block`. 자유 형식 편집

이 이중 구조가 "운영 DB 컬럼"과 "자유 커스텀 페이지" 요구를 동시에 충족한다.

---

## 6. 연동 상세

> 공통 패턴: **"계정 연동 → 소스 자동 로드 → 서비스에 매핑"**. 모든 토큰/키는 Vault 암호화, **서버(Edge Function) 전용**. 앱은 자격증명을 보관/사용하지 않는다.

### 6.1 Supabase (다중 계정, OAuth Management API)
- **연동**: 앱이 `ASWebAuthenticationSession`으로 Supabase OAuth를 시작 → 사용자가 동의 → 커스텀 스킴(`connectum://oauth/callback`)으로 `code` 수신 → **앱이 code를 Edge Function에 전달** → Edge Function이 **client secret으로 토큰 교환**(secret은 서버에만) → access/refresh 토큰 Vault 저장. **여러 계정** 연결(계정별 레이블)
- **자동 로드**: Management API `GET /v1/projects`로 프로젝트 목록 → 프로젝트 선택 → 스키마 조회로 **테이블 복수 선택**
- **데이터 읽기**: Management API로 프로젝트 API 키 취득(`/v1/projects/{ref}/api-keys`) → PostgREST로 행 읽기. `cursor_column`(예 `updated_at`)로 증분
- **유저 테이블 지정**: 선택 테이블 중 하나를 `user_table`로 지정, `user_id`(=Supabase auth id)·`email` 컬럼 매핑

### 6.2 Amplitude (프로젝트별 API Key + Secret)
- **연동**: 앱에서 API Key + Secret 입력 → Edge Function 경유로 Vault 저장(암호화). (Amplitude는 OAuth 미지원)
- **자동 로드**: Events/Taxonomy API로 **라이브 이벤트(저장·라벨된 이벤트)** 자동 조회
- **데이터**: Export API로 이벤트 증분 적재 → **매칭 유저만** `crm_user_event` + 프로필 속성 갱신. 필요 시 User Activity API로 개별 유저 보강
- **무료 플랜 리스크**: 호출 한도·이벤트 볼륨 제한 → 증분/청크 + 매칭 유저 한정으로 관리. **Phase 0 스파이크에서 무료 플랜 Export API 접근을 실제 검증** (막히면 User Activity API 폴백)

### 6.3 Axiom (계정 연동 → 데이터셋 자동 로드)
- **연동**: 앱에서 Axiom API 토큰 입력 → Edge Function 경유 Vault 저장
- **자동 로드**: `GET /v1/datasets`로 데이터셋 목록 → **서비스별 데이터셋 선택** (Supabase/Amplitude와 동일 UX)
- **데이터**: APL 쿼리로 `user_id` 기준 최근 에러/활동 신호 집계 + 서비스 헬스 집계. **30일 보존** → 최근 윈도우만 (Phase 3)

### 6.4 Vertex AI Gemini (운영자 인프라 인증)
- **연동**: **엔드유저 연동 불필요.** 운영자가 GCP 서비스계정 키 + 프로젝트/리전을 Supabase secret/Vault에 1회 설정
- **사용**: **Edge Function**이 유저 병합 데이터(프로필 + 이벤트 요약 + 컨택 기록 + Axiom 신호)로 프롬프트 구성 → Gemini 호출 → **3줄 총평** 저장. 동기화 시 자동 + 앱의 수동 재생성 버튼. **입력 해시 비교로 불필요한 재호출 차단**(비용 절약)

---

## 7. 동기화 엔진 (Supabase Edge Functions + pg_cron)

- **위치**: 모든 ETL·OAuth 토큰교환·Vertex 호출 로직은 **Supabase Edge Functions (Deno/TypeScript)**
- **스케줄 트리거**: **pg_cron**이 주기적으로 **pg_net**을 통해 sync Edge Function을 HTTP 호출 → 앱이 꺼져 있어도 백그라운드 동기화 유지, 무료로 유연한 주기
- **수동 트리거**: 앱의 "지금 동기화" 버튼 → 같은 Edge Function 직접 호출
- **타임아웃 대응**: Edge Function 실행 시간 한도를 고려해 **증분 + 청크** 처리, `sync_cursor`로 진행 상태 저장 → 한 실행에서 못 끝내면 다음 실행이 이어감
- **관측**: `sync_run`에 실행/통계/에러 기록. 앱이 이를 읽어 표시 (선택: Realtime 구독)
- **진화 경로**: 동기화 부하가 커지면 Supabase Queues + 워커로 큐 기반 처리로 확장

---

## 8. 기능 상세

> 모든 UI는 **SwiftUI 네이티브**로 구현. 복잡 UI(노션식 블록 에디터, 커스텀 뷰)는 네이티브 직접 구현이 핵심 작업(§13 리스크).

### 8.1 운영 DB (메인 화면)
- `crm_user` 목록 = 기본 테이블 뷰(SwiftUI `Table`). **서비스 선택** → 해당 서비스 유저 목록
- 컬럼: 동기화 프로필 + 컨택 상태 + 커스텀 속성 + AI 총평 미리보기 + 최근 활동
- 행 클릭 → 유저 상세 페이지

### 8.2 유저 상세 페이지 (운영 DB의 각 아이템)
- **헤더**: 동기화 프로필(이름/이메일/OS/브라우저/디바이스/지역/가입일/최근접속) + **컨택 여부 토글** + **AI 3줄 총평**(재생성 버튼)
- **본문**: 노션식 **자유 블록 편집기**(네이티브)
  - 채널 기록 블록: 이메일/카톡/문자/인터뷰/기타 메모 (각 날짜·내용·첨부)
  - 일반 블록: 텍스트/제목/이미지/구분선/커스텀 속성 표시
- **탭 [개요] [히스토리]**
- **히스토리 탭**: 날짜별 섹션, 각 항목 = **좌측 이미지 + 우측 메모**, **날짜 수동 입력**, 항목 추가/정렬. 이미지는 Supabase Storage 업로드

### 8.3 커스텀 속성 & 커스텀 뷰 (Phase 2)
- **속성**: 워크스페이스/서비스 범위로 필드 정의 (text/select/multi/date/checkbox/url/number/person)
- **커스텀 뷰**: 기본 운영 DB와 별개로 **새 뷰 생성** → 필터/정렬/표시컬럼/그룹핑/뷰타입(테이블·보드). 노션 DB 기능 대부분 지원
- 뷰는 `view` 테이블에 저장·공유

### 8.4 대시보드 (Phase 2)
- 서비스별 핵심 지표: 유저 수, 컨택률, 신규 유입, 활성도(Amplitude), 에러율(Axiom, Phase 3). 네이티브 차트(Swift Charts)

### 8.5 AI 총평
- §6.4 참조. 유저별 3줄, 동기화 시 자동 + 수동 재생성, 입력 해시로 비용 최적화

---

## 9. 디자인 시스템 (Raycast + Paperlogy, 네이티브)

**정합성**: Raycast는 본래 **네이티브 macOS 앱**이라, 그 디자인 언어를 SwiftUI로 옮기는 것이 자연스럽다. 토큰을 **SwiftUI `Color`/`Font` 자산**으로 정의하고 컴포넌트는 토큰만 참조한다. **Command-K 팔레트는 네이티브 오버레이 윈도우**로 1급 패턴화(Raycast 본질과 일치).

| 토큰 | 값 | 적용 |
|------|-----|------|
| **Surface ladder** | Canvas `#07080a` → Surface `#0d0d0d` → Elevated `#101111` → Card `#121212` | 앱 배경 / 사이드바·패널 / 인풋·호버 / 카드·유저행. **드롭섀도우 금지, 깊이는 surface로만** |
| **Border** | hairline `#242728` 1px | 모든 카드·구분선 |
| **Text** | ink `#f4f4f6` / body `#cdcdcd` / muted `#9c9c9d` / ash(disabled) `#6a6b6c` | 우선순위별 |
| **Primary CTA** | 흰색 pill, 검정 텍스트, 36pt h, 8/16 pad, pressed `#e8e8e8` | 주요 액션 전용 |
| **Secondary / Tertiary** | 투명+흰 텍스트 / elevated 배경+흰 텍스트 | 보조 액션 |
| **Typography** | **Paperlogy**(한/영 통일, 앱 번들), 8pt 베이스 spacing | 웨이트 400/500/600 |
| **Type scale** | hero 64/600 · section 56/500 · card title 24/500 · body 16/400 · caption 12/400 | line-height 1.1~1.6 |
| **Radius** | 4(뱃지)→6(리스트행)→8(버튼·인풋)→10(카드)→16(모달) | 0px 금지 |
| **Semantic 액센트** | blue `#57c1ff` / red `#ff6161` / green `#59d499` / yellow `#ffc533` (+soft 15%) | **상태 표시 전용**(컨택상태·동기화·에러신호). 크롬/CTA엔 금지 |

- **폰트 적응**: Raycast의 시그니처(Inter `ss03`)는 Inter 전용 → Paperlogy 자체 자형으로 대체. 타입 스케일·웨이트·spacing 규칙은 유지. Paperlogy를 앱에 번들(한/영 커버)
- **레이아웃**: 좌측 사이드바(서비스/내비, Surface) + 메인(Canvas) + 상세 패널(Card). 네이티브 macOS 창/툴바/사이드바 관용구 활용
- **모션**: Raycast처럼 미니멀·스냅(빠른 트랜지션), 과한 애니메이션 금지

---

## 10. 국제화 (i18n)

- **지원 언어**: 한국어(기본) + 영어. 인앱 로케일 스위처 + 시스템 로케일 따름
- **전략**: 네이티브 **String Catalogs(.xcstrings)** 로 ko/en 관리. UI 문자열만 번역, **동기화된 소스 데이터 내용은 원문 유지**
- **로컬라이즈 대상**: UI 라벨, 날짜/숫자 포맷(`Locale`), 빈 상태/에러 메시지
- **폰트**: Paperlogy가 한/영 모두 커버

---

## 11. 보안 & 프라이버시

- **자격증명**: 모든 소스 토큰/키 → **Supabase Vault 암호화, Edge Function 전용**. **앱은 소스 자격증명을 보관/사용하지 않음**. OAuth client secret·Vertex 서비스계정 키도 서버에만. OAuth 토큰 교환은 Edge Function에서 수행
- **앱 세션**: Supabase Auth 세션 토큰은 macOS **Keychain**에 저장
- **접근 제어**: **RLS**로 워크스페이스 격리, 팀원 Supabase Auth 인증
- **동기화 경계**: 모든 ETL·외부 호출은 Edge Function(서버)에서만. sync Edge Function은 호출 인증(서비스 역할/시크릿) 필요
- **최소 권한**: 소스 자격증명은 가능하면 읽기 전용 스코프
- **PII**: 유저 데이터(이메일/행동)는 내부 팀 도구 범위에서만 취급, 외부 노출 없음
- **배포 무결성**: Developer ID 서명 + Apple 공증(notarization)

---

## 12. 단계별 로드맵

- **Phase 0 — 기반 + 검증 스파이크**
  - SwiftUI 앱 스캐폴드(창/사이드바/Raycast 토큰·Paperlogy·i18n 기초), Connectum Supabase(Auth/Vault/Storage), Edge Functions + pg_cron 골격, supabase-swift 인증 연결
  - **무료 플랜 / 핵심 연동 실검증**: Amplitude Export, Supabase Management API, Axiom, **Edge Function 기반 동기화·OAuth 토큰교환 흐름**
- **Phase 1 — 핵심 (MVP)**
  - 팀 로그인(공유 워크스페이스)
  - 연동: Supabase OAuth(다중계정, ASWebAuthenticationSession+Edge Function)→프로젝트/테이블 선택, Amplitude 키→이벤트 적재, Axiom 토큰→데이터셋 선택(연결 UI까지; 신호 활용은 Phase 3)
  - 동기화 엔진(Edge Functions + pg_cron, 증분·청크, `sync_run`/`cursor`)
  - 운영 DB(`crm_user` 목록) + 유저 상세(헤더/컨택토글/자유블록/채널기록/히스토리탭)
  - Vertex Gemini 3줄 총평(자동 + 수동)
  - 공증 DMG 배포 파이프라인
- **Phase 2 — 커스텀 뷰 & 대시보드**
  - 커스텀 속성, 뷰 엔진(필터/정렬/그룹/보드), 대시보드(Swift Charts)
- **Phase 3 — Axiom 심화**
  - 유저 에러/활동 신호, AI 총평에 신호 주입, 서비스 헬스 미니 대시보드, 아웃리치 트리거
- **Phase 4 — (선택) Windows / 크로스플랫폼 재검토**
  - 수요 발생 시 별도 검토 (SwiftUI 비공유)

---

## 13. 리스크 & 오픈 이슈

| 리스크 | 영향 | 대응 |
|--------|------|------|
| **SwiftUI로 노션식 블록 에디터·커스텀 뷰 직접 구현** | Phase 1~2 공수 큼 | 핵심 난이도 인지. 블록 에디터 범위를 MVP에 맞게 단계화(채널기록+기본 블록 우선), 뷰는 Phase 2 |
| Amplitude 무료 플랜 Export API 접근/볼륨 제한 | Phase 1 핵심 | **Phase 0 스파이크로 선검증**, User Activity API 폴백 |
| Supabase 무료(DB 500MB / Storage 1GB) 용량 | 이벤트·이미지 적재 한도 | 매칭 유저 한정 + 이벤트 prune + 이미지 용량 모니터링 |
| Edge Function 실행 시간/리소스 한도(대량 Export) | 동기화 실패 | 증분·청크 + 커서 이어가기, 필요 시 Queues 워커 |
| Supabase OAuth 앱 등록/심사 | 연동 UX | Phase 0에 앱 등록 선행, ASWebAuthenticationSession+Edge Function 흐름 선검증 |
| supabase-swift / 네이티브 연동 성숙도 | 인증·Realtime | Phase 0에서 인증·읽기·Storage 검증 |
| Axiom 로그에 `user_id` 부재 가능성 | 유저 단위 신호 가치 | Phase 3 진입 시 로그 스키마 확인, 없으면 서비스 헬스 용도로 축소 |
| Vertex 호출 비용 | 운영비 | 입력 해시로 중복 호출 차단, 변경 시에만 재생성 |

---

## 14. 기술 스택 요약

- **앱(클라이언트)**: **SwiftUI / AppKit** (macOS 네이티브), supabase-swift, ASWebAuthenticationSession(OAuth), Keychain(세션), String Catalogs(i18n), Paperlogy(번들), Swift Charts(Phase 2)
- **백엔드/DB**: **Supabase** — Postgres + Auth + Storage + Vault + **Edge Functions(Deno/TS)** + **pg_cron/pg_net**, RLS
- **동기화/AI**: Edge Functions ETL (증분·청크) + pg_cron 스케줄, Vertex AI Gemini(서버 공용 인증)
- **소스 연동**: Supabase Management API(OAuth, 다중) · Amplitude API(Key+Secret) · Axiom API(Token)
- **배포**: Developer ID 서명 + Apple 공증 DMG 직접 배포 (App Store 추후 검토)
- **(추후)**: Windows/크로스플랫폼 재검토
