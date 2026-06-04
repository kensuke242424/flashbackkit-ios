<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="design/brand_assets/lockup/flashbackkit-lockup-on-dark-2x.png">
    <img src="design/brand_assets/lockup/flashbackkit-lockup-on-light-2x.png" alt="FlashbackKit" width="440">
  </picture>
</p>

<p align="center"><em>Recall the moment <strong>before</strong> the bug.</em></p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-iOS%2016%2B-blue" alt="iOS 16+">
  <img src="https://img.shields.io/badge/Swift-6-orange" alt="Swift 6">
  <img src="https://img.shields.io/badge/SwiftPM-compatible-brightgreen" alt="SwiftPM">
  <img src="https://img.shields.io/badge/dependencies-none-success" alt="Zero dependencies">
  <img src="https://img.shields.io/badge/license-MIT-black" alt="MIT">
</p>

---

A zero-dependency iOS SDK that captures the **context right before a bug happens** — the
last N seconds of screen recording, a one-line note, and full device info — and hands it
off to your pipeline (AI summarizer, Slack, Jira, your own backend) in one callback.

Testers always notice the bug *after* it happens. By then the steps that led there are
gone. FlashbackKit keeps a rolling buffer of the screen, so when a tester files a report,
the seconds **leading up to the bug** are already captured — sparing you the "can you
reproduce it?" round-trips.

> [!NOTE]
> **Status: PoC / WIP.** Built for Debug / Staging / TestFlight / internal QA builds —
> not for shipping to end users. The design bias is making testers *want* to use it and
> improving reproducibility, over architectural purity. The public API may change before
> a 1.0 release.

<details>
<summary>UI preview (design mockups)</summary>

<br>

![FlashbackKit screens](design/design_handoff_flashbackkit/screenshots/all-screens.png)

</details>

## Contents

- [Highlights](#highlights)
- [How it works](#how-it-works)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [The `onReport` handoff](#the-onreport-handoff)
- [Triggers](#triggers)
- [Privacy & masking sensitive data](#privacy--masking-sensitive-data)
- [Security](#security)
- [Known constraints](#known-constraints)
- [Example app](#example-app)
- [Debug helpers](#debug-helpers)
- [Tests](#tests)
- [Roadmap](#roadmap)
- [Contributing](#contributing)
- [License](#license)

## Highlights

- **The "before" is already recorded** — an always-on ReplayKit ring buffer means the last
  N seconds are *already captured* when a report is triggered. ReplayKit can't rewind, so
  this is the only way to get the pre-bug context.
- **Zero dependencies** — just UIKit / SwiftUI / ReplayKit from the system SDK. No
  Firebase, Alamofire, or Rx, and no network client of its own. Drops into any app and
  keeps your dependency graph clean.
- **Two triggers, your choice** — shake the device twice, or a draggable floating button
  for fixed/kiosk devices. Pick either or both.
- **Trim before you send** — testers preview the clip and trim to the relevant moment in a
  built-in editor; the title and device info are baked into the exported file.
- **One handoff point** — a single `onReport` callback gives you the trimmed clip, the
  title, and device info. Route it anywhere. *The SDK's job ends at "here's the report."*
- **Unfiltered by design** — iOS excludes secure text fields from the recording for free,
  but masking everything else is the host app's responsibility (see
  [Privacy](#privacy--masking-sensitive-data)). The SDK does not redact the recording
  itself.

## How it works

```
 trigger (shake twice / floating button)
        │
        ▼
 export the last N seconds from the ring buffer
        │
        ▼
 Report UI  ──►  preview + trim  +  one-line title  +  auto device info
        │
        ▼
 Share (↑)  ──►  trims, bakes metadata, opens the system share sheet
        │         (save to Photos / Files / AirDrop / other apps)
        ▼
 onReport(FlashbackReport)  ──►  your pipeline (AI / Slack / Jira / backend)
```

## Requirements

| | |
|---|---|
| Platform | iOS 16+ |
| Toolchain | Swift 6 / Xcode 16+ |
| Dependencies | none |

## Installation

> [!NOTE]
> Latest release: **`0.1.0`** — pre-1.0, so the public API may change before a stable
> 1.0. Pin an exact version if you need stability.

### Swift Package Manager (Xcode)

**File → Add Package Dependencies…** and enter:

```
https://github.com/kensuke242424/flashbackkit-ios.git
```

Set **Dependency Rule = Up to Next Major Version** from `0.1.0` (or pin **Exact** `0.1.0`
while the API is pre-1.0).

### Package.swift

```swift
.package(url: "https://github.com/kensuke242424/flashbackkit-ios.git", from: "0.1.0")
```

```swift
.target(name: "YourApp", dependencies: ["FlashbackKit"])
```

## Quick Start

Call `Flashback.start()` **once** at app launch (e.g. in `App.init`,
`didFinishLaunching`, or your root view's `.onAppear`):

```swift
import FlashbackKit

Flashback.start(
    configuration: .init(bufferSeconds: 30),
    onReport: { report in
        // report.clipURL  — trimmed clip (temp file); nil when capture wasn't running
        // report.title    — the tester's one-line note
        // report.device   — model / OS / app version / locale …
        myBackend.upload(report)
    }
)
```

From here a tester triggers a report (shake twice, or the floating button), trims the
clip, types a title, and taps **Share (↑)** — which opens the system share sheet *and*
fires your `onReport`.

> [!IMPORTANT]
> **With the defaults (`promptOnLaunch: false`), nothing records and no iOS permission
> prompt appears at launch.** The tester starts recording by tapping the grey floating
> button (which shows a one-time priming sheet, then the iOS prompt). The trim → title →
> Share flow — and `onReport` — only happen once recording is on and a clip exists.
> Triggering *before* recording is enabled shows a "recording is off" screen with a
> one-tap enable, and does **not** fire `onReport`. To record from launch, set
> `promptOnLaunch: true`.

To halt recording and remove the triggers/overlay at runtime (e.g. when leaving a QA
session, or before a sensitive screen), call `Flashback.stop()` — the counterpart to
`start()`.

> [!IMPORTANT]
> `report.clipURL` points to a temporary file. If you need to keep it, copy or upload it
> **inside** the `onReport` callback.

## Configuration

All fields are optional; defaults shown.

```swift
Flashback.start(
    configuration: .init(
        bufferSeconds: 20,                 // rolling buffer length (seconds)
        isEnabled: true,                   // master switch — set false to no-op in Release
        triggers: .default,                // [.shake, .floatingButton]
        floatingButtonCorner: .bottomTrailing,
        promptOnLaunch: false,             // ask for screen-recording permission at launch
        runsOnSimulator: false             // ReplayKit can't record on the Simulator
    )
)
```

| Option | Type | Default | Notes |
|---|---|---|---|
| `bufferSeconds` | `TimeInterval` | `20` | How many seconds of "before" to retain. Also adjustable by the tester in-app. |
| `isEnabled` | `Bool` | `true` | Master kill-switch. Gate it so the SDK is inert in Release builds. |
| `triggers` | `FlashbackTrigger` | `.default` | OptionSet of `.shake` and/or `.floatingButton`. |
| `floatingButtonCorner` | `FloatingButtonCorner` | `.bottomTrailing` | Initial corner of the floating button. |
| `promptOnLaunch` | `Bool` | `false` | If `true`, requests screen-recording permission at launch (otherwise on first enable). |
| `runsOnSimulator` | `Bool` | `false` | The SDK no-ops on the Simulator unless you opt in (recording still won't work there). |

> [!NOTE]
> Several settings — `promptOnLaunch`, the buffer length (`bufferSeconds`), and
> floating-button visibility — are also adjustable by the tester in the in-app settings.
> The in-app choice is **persisted and takes precedence over the config default after
> first launch**, so the config value mainly governs the very first run. (A tester who
> once opted into launch recording will keep buffering at launch even if the config says
> `false`.)

> [!NOTE]
> With the default `runsOnSimulator: false`, `start()` is a **complete no-op on the
> Simulator** — no floating button, no overlay, no prompt. Set `runsOnSimulator: true` to
> see the UI on the Simulator, but recording still won't run there; test recording on a
> device.

## The `onReport` handoff

`onReport` is the **only** extension point. FlashbackKit captures, trims, and packages —
then hands you a `FlashbackReport`. Everything downstream (AI summary, Slack, Jira, your
own service) is yours to wire up.

`onReport` is delivered on the **main actor** (`@MainActor`). Do network/disk work inside
a `Task` (as shown below) so you don't block the UI.

```swift
public struct FlashbackReport: Sendable {
    public var title: String      // one-line note typed by the tester
    public var device: DeviceInfo // model, OS, app version, locale, …
    public var clipURL: URL?      // trimmed clip (temp file); nil when capture wasn't running
}
```

```swift
Flashback.start(onReport: { report in
    Task {
        // e.g. summarize with an LLM, then post to Slack with a link to the uploaded clip
        let summary = await llm.summarize(title: report.title, device: report.device)
        let link: String? = if let url = report.clipURL {
            await storage.upload(url)
        } else {
            nil
        }
        await slack.post(text: summary, videoLink: link)
    }
})
```

> [!TIP]
> FlashbackKit does **not** call any AI or Slack APIs itself — there's no embedded
> network client and no webhook config. This keeps the SDK dependency-free and lets you
> use whatever backend you already have.

### Required Info.plist key (only for "Save to Photos")

The share sheet's **Save to Photos** path writes to the camera roll, which needs a usage
description in the **host app's** Info.plist (omitting it crashes on permission request).
Not needed if you only use "Save to Files":

```xml
<key>NSPhotoLibraryAddUsageDescription</key>
<string>Saves the pre-bug screen clip from your report to your photo library.</string>
```

## Triggers

| Trigger | Best for | Gesture |
|---|---|---|
| `.shake` | handheld testing | shake the device twice (a deliberate double-shake; one weak shake won't fire) |
| `.floatingButton` | fixed / kiosk / one-handed | state-dependent: tap to start recording (grey), long-press to open the report (orange), drag to move — see below |

### Floating button interaction

The floating button doubles as a recording-state indicator, and its gesture depends on
that state so first-time users aren't stuck guessing:

- **Grey (recording off)** → **tap to start recording.** The first time, a short priming
  sheet explains why screen-recording permission is needed, then iOS asks.
- **Orange (recording on)** → **long-press (0.5s) to open the report.** A short tap shows
  a "long-press to open" hint instead of doing nothing.
- **Drag** to reposition; it snaps to the nearest edge and can tuck away.
- VoiceOver: double-tap activates the state-appropriate action (no long-press required).

When the floating button is turned off, the SDK shows a one-time "shake twice to open"
hint so testers know the shake trigger is available.

## Privacy & masking sensitive data

Screen recording captures **everything on screen** (customer names, tokens, inventory…).
FlashbackKit deliberately does **not** intercept the recording pipeline — masking is the
host app's responsibility, because only the host knows what's sensitive.

- **Password fields are handled for free.** iOS automatically excludes
  `isSecureTextEntry = true` `UITextField`s from ReplayKit and screenshots.
- **Everything else is up to you.** The most reliable approach is to use dummy data in QA
  builds, or not show sensitive screens while recording (you can call `Flashback.stop()`
  to suspend capture before one).
- **Secure-layer trick (unofficial).** Hosting a view inside a secure text field's layer
  keeps it visible to the user but excluded from capture. Behavior varies by iOS version,
  so prefer the operational approach when certainty matters.

  ```swift
  // Host-side utility (not part of FlashbackKit).
  extension UIView {
      func hideFromScreenCapture(_ content: UIView) {
          let field = UITextField()
          field.isSecureTextEntry = true
          guard let secureLayer = field.layer.sublayers?.first else { return }
          secureLayer.addSublayer(content.layer)
      }
  }
  ```

> Saving or sharing a clip to the photo library may sync it to iCloud. The destination is
> chosen by the tester at share time — keep that in mind for sensitive content.

## Security

This SDK records the screen, so clips can contain sensitive data. If you find a security
issue (e.g. a clip leak), please report it **privately** — use GitHub's
["Report a vulnerability"](https://github.com/kensuke242424/flashbackkit-ios/security/advisories/new)
flow rather than filing a public issue.

## Known constraints

These are platform realities the design works *around*, not bugs:

- **ReplayKit can't record retroactively** → an always-on ring buffer is required. This
  means a screen-recording permission prompt and some battery/thermal cost while active.
- **Slack Incoming Webhooks can't send video** → text/links only. For an actual video
  attachment, use a Bot token with `files.getUploadURLExternal` / `completeUploadExternal`,
  or host the clip elsewhere and link to it.
- **Claude / OpenAI can't analyze video directly** → extract keyframes, or use a
  video-native model.

## Example app

`Example/FlashbackExample.xcodeproj` is a host app that exercises the full loop.

- **Simulator** — builds as-is (no signing). ReplayKit capture doesn't work on the
  Simulator, so recording is disabled and the loop runs without a clip. The Example opts
  in via `runsOnSimulator: true` so you can still see the UI — your own app, with the
  default `runsOnSimulator: false`, will show nothing on the Simulator.
- **Device** — needs code signing. Team IDs aren't committed, so set yours:

  ```sh
  cp Example/Signing.example.xcconfig Example/Signing.xcconfig
  # edit Signing.xcconfig → set DEVELOPMENT_TEAM to your Apple Developer Team ID
  ```

  `Signing.xcconfig` is gitignored and included optionally, so Simulator builds pass even
  without it.

## Debug helpers

In `DEBUG` builds, `Flashback` exposes helpers to present each UI state directly (handy on
the Simulator or for re-testing first-run flows) — e.g.
`debugPresentSampleReport(seconds:)`, `debugPresentEmptyReport()`,
`debugPresentRecordingJustEnabled()`, `debugPresentReportUnavailable()`,
`debugPresentPriming()`, `debugResetPriming()`, `debugPresentShakeHint()`,
`debugResetShakeHint()`, `debugShowToast(_:)`, `debugPresentSettings()`. They require
`Flashback.start()` to have installed the overlay.

## Tests

```sh
xcodebuild test -scheme FlashbackKit -destination 'platform=iOS Simulator,name=iPhone 16'
```

> `swift build` is intentionally not used — it targets the macOS host and breaks on UIKit.
> Build for iOS instead:
> `xcodebuild -scheme FlashbackKit -destination 'generic/platform=iOS' build`.

## Roadmap

FlashbackKit currently covers: multi-trigger launch → pre-bug recording → trim → device
info → `onReport` handoff. Summarization and delivery (AI, Slack, etc.) live on the host
side by design.

## Contributing

Issues and PRs are welcome — file bugs and ideas in
[Issues](https://github.com/kensuke242424/flashbackkit-ios/issues) (for recording
behavior, please note whether you saw it on a device or the Simulator). Please keep the
**zero-dependency** rule (no third-party packages) and match the existing style: `public`
API gets doc comments, and types that touch UI / recording / shake detection are
`@MainActor`.

## License

[MIT](LICENSE)
