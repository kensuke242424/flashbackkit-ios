# Contributing to FlashbackKit

Thanks for your interest! FlashbackKit is a small, dependency-free iOS SDK
(PoC / WIP, pre-1.0). Issues and pull requests are welcome.

## Reporting issues

- File bugs and ideas in [Issues](https://github.com/kensuke242424/flashbackkit-ios/issues).
- For **recording behavior**, please note whether you saw it on a **physical device** or
  the **Simulator** — ReplayKit in-app capture does not actually produce frames on the
  Simulator, so much of the recording path can only be verified on device.
- Include iOS version, device/Simulator model, and reproduction steps.
- **Security issues:** do not open a public issue — see [SECURITY.md](SECURITY.md).

## Building & testing

This is a Swift Package targeting **iOS 16+ / Swift 6**.

```sh
# Build (iOS — do NOT use `swift build`; it targets the macOS host and breaks on UIKit)
xcodebuild -scheme FlashbackKit -destination 'generic/platform=iOS' build

# Test
xcodebuild test -scheme FlashbackKit -destination 'platform=iOS Simulator,name=iPhone 16'
```

There is also an Example app under `Example/` for exercising the UI and behavior. It uses
a gitignored `Example/Signing.xcconfig` for your Team ID (copy `Signing.example.xcconfig`).

## Code guidelines

- **Zero dependencies.** No third-party packages — standard frameworks only (URLSession,
  ReplayKit, AVFoundation, SwiftUI, etc.). This keeps SDK adoption frictionless.
- **`@MainActor`** on types that touch UI, recording, or shake detection.
- **Public API gets doc comments** (`///`), and public types use explicit access modifiers.
- **Comments in English.** Keep them about intent and non-obvious constraints, not history.
- Respect the design constraints (see [CLAUDE.md](CLAUDE.md) / the README): ReplayKit can't
  record retroactively (always buffer); Slack webhooks can't send video; AI APIs can't parse
  video directly.

## Pull requests

- Keep changes focused; explain the why in the description.
- Make sure `xcodebuild test` passes and there are no new warnings.
- Note any change that was only verified on Simulator vs. on a real device.

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
