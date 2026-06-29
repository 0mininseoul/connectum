# Service Wizard Supabase Confirmation UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the post-Supabase-selection service setup screen clear, action-oriented, and scoped only to Supabase database setup.

**Architecture:** Keep the existing single `ServiceWizardView.swift` structure, but replace the mixed review/optional-integration layout with focused SwiftUI subviews for confirmation, source summary, advanced identity/display options, and the final create action. Fix Supabase account metadata in `LocalCrmRepository` so project names are not shown as account names.

**Tech Stack:** macOS SwiftUI, Observation, local-first `LocalCrmRepository`, XCTest.

---

## Files

- Modify: `apps/Connectum/Connectum/Data/LocalCrmRepository.swift`
  - Remove project-name fallback from Supabase account metadata.
- Modify: `apps/Connectum/Connectum/Features/Connections/ServiceWizardView.swift`
  - Rebuild the `.createService` step UI.
  - Remove Amplitude/Axiom selection from the Supabase wizard.
  - Add focused summary/action subviews.
- Modify: `apps/Connectum/ConnectumTests/LocalCrmRepositoryTests.swift`
  - Add a regression test proving a project name is not used as the Supabase account name when OAuth profile metadata is missing.

## Task 1: Fix Supabase Account Name Source

- [x] Add a regression test in `LocalCrmRepositoryTests`.
  - Use `FakeSupabaseOAuthAPI(tokens: SupabaseOAuthTokens(... accountName: nil))`.
  - Use `FakeSupabaseManagementAPI(projects: [ProjectInfo(ref: "archy-ref", name: "Archy", region: "ap-northeast-2")])`.
  - Assert `account.label == "Supabase"` and `account.accountName == nil`.
- [x] Run the targeted test and confirm it fails before the fix.
  - Command: `cd apps/Connectum && xcodegen generate && xcodebuild test -project Connectum.xcodeproj -scheme Connectum -configuration Debug -derivedDataPath ../../.build/xcode-test-account-name -destination 'platform=macOS' -only-testing:ConnectumTests/LocalCrmRepositoryTests/testSupabaseOAuthDoesNotUseProjectNameAsAccountName`
- [x] Update `connectSupabaseOAuth`:
  - `label: tokens.accountName ?? "Supabase"`
  - `accountName: tokens.accountName`
- [x] Update `connectSupabasePAT` with the same rule:
  - `accountName: nil`
  - Keep the user-entered PAT label as the label.
- [x] Re-run the targeted test and confirm it passes.

## Task 2: Rebuild The Create-Service Confirmation Step

- [x] Replace `createServiceStep` composition:
  - Use `completionPrompt`
  - Use `sourceSummaryPanel`
  - Use `advancedSetupSection`
  - Use `createActionPanel`
- [x] Remove `optionalConnectionsSection` from this step.
  - Do not show Amplitude/Axiom empty-state copy in the Supabase wizard.
- [x] Keep table and project change actions visible in the summary panel.
- [x] Keep user ID and email column controls available, but group them as "고급 설정" below the main action context.
- [x] Move the primary `서비스 만들기` action into its own bottom panel with concise copy.

## Task 3: Verify

- [x] `git diff --check`
- [x] `cd apps/Connectum && xcodegen generate`
- [x] `xcodebuild test -project apps/Connectum/Connectum.xcodeproj -scheme Connectum -configuration Debug -derivedDataPath .build/xcode-test-service-confirmation -destination 'platform=macOS'`
- [x] `xcodebuild build -project apps/Connectum/Connectum.xcodeproj -scheme Connectum -configuration Debug -derivedDataPath .build/xcode-build-service-confirmation -destination 'platform=macOS'`
- [x] `./script/build_and_run.sh --install-verify`
