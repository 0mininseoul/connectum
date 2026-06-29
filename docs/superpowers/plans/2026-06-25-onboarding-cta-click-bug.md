# Onboarding "새 서비스 시작" CTA - click bug investigation

**Status:** Root-scale hit-test fix landed locally on 2026-06-25. The first-run
body CTA is restored, the duplicate sidebar first-run button is removed, and the
app no longer applies the persisted root `uiScale` transform. Debug build, unit
tests, Release verify build, and static grep checks pass. A real hardware-mouse
click in the currently running Release app is still the final authoritative
verification because automation could not reproduce the original failure.

**Env:** macOS 26.5.x beta, SwiftUI, NavigationSplitView, Apple Silicon,
non-integer Retina ("More Space") scaling.

## Symptom
On first run, the body onboarding `새 서비스 시작` button appeared visually correct
but did nothing on a real hardware-mouse click. AXPress and synthetic coordinate
clicks could trigger the action, so automation repeatedly gave false confidence.

The old sidebar `새 서비스 시작` entry point worked, but it was a duplicate first-run
CTA and should not remain in the sidebar.

## Confirmed facts
- `startNewService()` itself works: AXPress and synthetic coordinate clicks can
  navigate to the draft service setup flow.
- Synthetic clicks were not a reliable verification signal because they passed
  even while the real mouse failed.
- The user's app had a persisted `uiScale` value of `0.9`.
- `ConnectumApp` wrapped the whole `RootView` in a `GeometryReader`, divided the
  frame by `shell.uiScale`, then applied `.scaleEffect(shell.uiScale,
  anchor: .topLeading)`.
- Moving the CTA from the body to SwiftUI parent overlays, an AppKit
  `NSViewRepresentable`, and the top tab/chrome area still failed real-mouse
  testing in the open app.

## Current root cause
The most consistent cause is the app-level root scale transform. With
`uiScale = 0.9`, SwiftUI rendered the whole app at one coordinate scale while
hit-testing real hardware mouse events through a transformed view tree. AXPress
and synthetic clicks bypassed or compensated for enough of that path to succeed,
which is why they could not reproduce the bug.

This also explains why moving the CTA did not help: the body button, overlay
button, AppKit click target, and top chrome fallback all still lived under the
same scaled root view.

## Failed attempts
- SwiftUI overlay: moved the real button outside the `ScrollView` with a hidden
  placeholder and `overlayPreferenceValue`; real mouse still failed.
- AppKit click target: drew and handled the CTA with a custom `NSView`; real
  mouse still failed.
- Top chrome fallback: moved the first-run CTA into `ShellTabBar`; real mouse
  still failed, contradicting the earlier assumption that chrome buttons were
  unaffected.

These attempts were useful because they ruled out `ScrollView`-only gesture
loss as the full explanation.

## Current fix
- Removed root `GeometryReader` + divided frame + `.scaleEffect(shell.uiScale)`.
- Removed the persisted `uiScale` preference reader and app zoom model state.
- Removed zoom commands (`확대`, `축소`, `실제 크기`) that wrote the unsafe scale.
- Restored the first-run body `새 서비스 시작` button as the primary CTA.
- Removed the duplicate sidebar first-run CTA.
- Kept the sidebar action-bar `+ 새 서비스` hidden only on true first run; it
  returns after a real service or draft exists.

The old `uiScale=0.9` value may still exist in `UserDefaults`, but current app
code no longer reads or applies it.

## Verification after current candidate
- `xcodebuild build -quiet -project apps/Connectum/Connectum.xcodeproj -scheme Connectum -configuration Debug -derivedDataPath .build/xcode -destination 'platform=macOS'` passed.
- `xcodebuild test -quiet -project apps/Connectum/Connectum.xcodeproj -scheme Connectum -configuration Debug -derivedDataPath .build/xcode -destination 'platform=macOS'` passed.
- `./script/build_and_run.sh --verify` passed and launched the Release app from
  `.build/xcode/Build/Products/Release/Connectum.app`.
- `rg -n "uiScale|zoomIn|zoomOut|resetZoom|scaleEffect\(shell\.uiScale|확대|축소|실제 크기" apps/Connectum/Connectum apps/Connectum/ConnectumTests -S`
  finds no remaining references.
- `git diff --check` passed for touched files.

## Suggested next step
Verify with a real hardware mouse on the body `새 서비스 시작` CTA in the currently
running Release app. If it still fails after the root scale removal, the next
instrumentation should log mouse-down/mouse-up delivery at the window/root level
before returning to individual button implementations.

## Code state
- `ConnectumApp`: directly hosts `RootView`; no root scale transform.
- `ShellModel`: no `uiScale` state or zoom methods.
- `AppCommands`: no zoom menu commands.
- `FirstRunOnboardingView`: body CTA calls `shell.startNewService()`.
- `ShellTabBar`: no first-run CTA fallback.
- `EmptySidebarStart`: no duplicate first-run CTA.
