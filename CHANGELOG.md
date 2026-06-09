# Changelog

All notable changes to FlashbackKit are documented here. This project is **pre-1.0
(PoC / WIP)**; the public API may change before a stable 1.0. Full release notes live on
the [Releases](https://github.com/kensuke242424/flashbackkit-ios/releases) page.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions
are pre-1.0 and bump the minor for each release.

## [0.8.0] - 2026-06-10

### Changed
- `FlashbackReport` and `DeviceInfo` now conform to `Codable`, `Equatable`, and `Hashable`,
  so a report can be serialized/compared without hand-mapping every field.
- `FlashbackError` is now `internal` — it was never part of the public contract (the host
  interacts only through `onReport`).

### Documentation
- Documented the remaining `DeviceInfo` fields, `FlashbackConfiguration` and its initializer,
  and `Flashback.stop()`. All source/comment text is now in English.

## [0.7.0] - 2026-06-08

### Fixed
- Trimmer preview: reaching the end now returns to the start and pauses, instead of leaving
  the play state stuck as "playing" — a single tap replays. (The selection no longer loops.)

## [0.6.0] - 2026-06-07

### Changed
- Clarified the capture-visibility toggle label so it's explicit that it governs **OS**
  screenshots/recording only — Flashback's own recorded clip never includes the floating button.

## [0.5.0] - 2026-06-07

### Added
- Settings toggle to optionally include the floating button in OS screenshots/recordings
  (off by default; otherwise excluded via the secure layer).

### Changed
- Priming sheet mark now uses the brand logo colors (adaptive ring/hand enclosing the orange
  wedge); tightened the settings footer copy.

## [0.4.0] - 2026-06-06

### Added
- The SDK's overlay UI (floating button, toasts) is excluded from OS screenshots, screen
  recording, AirPlay mirroring, and the SDK's own clip via a secure layer.
- External-capture conflict detection extended to devices whose in-app capture also sets
  `UIScreen.isCaptured` (e.g. iPhone 15 Pro); recording interrupt/resume toasts; long-press
  a tucked floating button to launch the report.

### Changed
- Trimmer opens at the end of the recording; a tucked button shows a direction chevron;
  unified priming/dormant marks; shared title rules for still & clip share; `｜`-separated
  device info in titles; smoother scroll when focusing the title field.

### Fixed
- Toasts no longer overlap the host app's tab bar.

## [0.3.0] - 2026-06-05

### Added
- Still capture from the trimmer — share the exact frame at the playhead as a full-resolution
  PNG; floating-button vertical flick inertia; recording on/off animation (wedge fill + radar
  ping, honors Reduce Motion); a "recording started" toast.

### Changed
- Long-press to open the report is slightly quicker (0.5s → 0.4s).

### Fixed
- The still-capture button no longer jumps to the left edge after returning from settings.

## [0.2.0] - 2026-06-04

### Added
- External-capture conflict detection: recording pauses when OS screen recording / mirroring
  takes over and auto-resumes once it ends.

### Fixed
- `start()` works regardless of call-site timing — it waits for scene connection if called
  before the `UIWindowScene` exists (e.g. from `didFinishLaunching`) (#19).
- The floating button no longer flickers grey/orange on static screens.

## [0.1.0] - 2026-06-04

- First public pre-release: capture the last N seconds of screen before a bug, let a tester
  trim + title it, and hand a `FlashbackReport` to your `onReport` callback. Zero dependencies,
  iOS 16+, Swift 6.

[0.8.0]: https://github.com/kensuke242424/flashbackkit-ios/releases/tag/0.8.0
[0.7.0]: https://github.com/kensuke242424/flashbackkit-ios/releases/tag/0.7.0
[0.6.0]: https://github.com/kensuke242424/flashbackkit-ios/releases/tag/0.6.0
[0.5.0]: https://github.com/kensuke242424/flashbackkit-ios/releases/tag/0.5.0
[0.4.0]: https://github.com/kensuke242424/flashbackkit-ios/releases/tag/0.4.0
[0.3.0]: https://github.com/kensuke242424/flashbackkit-ios/releases/tag/0.3.0
[0.2.0]: https://github.com/kensuke242424/flashbackkit-ios/releases/tag/0.2.0
[0.1.0]: https://github.com/kensuke242424/flashbackkit-ios/releases/tag/0.1.0
