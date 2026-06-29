# Supabase OAuth Additional Account Choice Plan

## Goal

When a user adds another Supabase account from the service setup flow, do not force the already-signed-in default browser session. Give the user an explicit choice:

- Open the OAuth URL in the default browser.
- Copy the OAuth URL so they can paste it into another browser, browser profile, or private window.

The app should keep waiting for the same loopback callback after either launch path.

## Scope

- Modify `apps/Connectum/Connectum/Features/Connections/ServiceWizardView.swift`.
- Keep the local-first trust boundary unchanged.
- Do not add a Connectum-hosted backend, account system, telemetry, or maintainer-visible data path.

## Implementation Steps

1. Add a small `SupabaseOAuthLaunchMode` enum.
2. Update `ServiceWizardViewModel.reconnectSupabaseOAuth` to accept a launch mode.
3. For default browser mode, keep the current `NSWorkspace.shared.open` behavior.
4. For copy-link mode, write the authorize URL to `NSPasteboard` and keep the loopback receiver waiting.
5. Add a compact SwiftUI sheet from the account menu explaining the session issue and offering both actions.
6. Keep first-time Supabase connection and reauthorization as direct browser actions.
7. Verify formatting, build, tests, and local app launch.

## Verification

- `git diff --check`
- `cd apps/Connectum && xcodegen generate`
- `xcodebuild build -project apps/Connectum/Connectum.xcodeproj -scheme Connectum -configuration Debug -derivedDataPath .build/xcode-oauth-account-choice -destination 'platform=macOS'`
- `xcodebuild test -project apps/Connectum/Connectum.xcodeproj -scheme Connectum -configuration Debug -derivedDataPath .build/xcode-test-oauth-account-choice -destination 'platform=macOS'`
- `./script/build_and_run.sh --install-verify`
