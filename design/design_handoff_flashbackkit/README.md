# Handoff: FlashbackKit — Brand & ReportView UI/UX

## Overview
**FlashbackKit** is an iOS bug-report SDK for mobile QA. It continuously keeps the *moments before* an issue (a short screen recording, a title, device info), then hands a trimmed clip back to the host app. The SDK's job is narrow: **record → trim → hand off (Share)**. AI summaries / Slack posting are the host app's responsibility, not the SDK's.

- **Name:** FlashbackKit
- **Tagline:** "Recall the moment before the bug." (keep in English)
- **UI language:** Japanese labels. Brand name & tagline stay English.
- **Audience:** QA engineers / developers (Debug / Staging / TestFlight / internal QA builds). Not for end users.
- **Personality:** Something QA *wants* to use — zero-friction, trustworthy, a touch of warmth.

This handoff covers the **confirmed direction: "Quiet"** (system-native, neutral, with a single warm action color). Two earlier directions (Instruments / Rewind) and a half-modal alternative are preserved in the design file as references but are **not** the chosen design.

## About the Design Files
The files in this bundle are **design references created in HTML/React (Babel JSX)** — prototypes showing intended look and behavior. **They are not production code to copy.** The task is to **recreate these designs natively in SwiftUI** (iOS 16+, light & dark, SF Symbols, Dynamic Type, VoiceOver), using the host project's existing patterns where they exist. The HTML uses absolute pixel positioning and inline styles for layout convenience; do **not** port that literally — rebuild with SwiftUI stacks, `Color`, `Font`, and standard components.

Open `FlashbackKit - Phase 2.html` to browse. It's a pan/zoom canvas (drag to pan, scroll/pinch to zoom); each card has a ⤢ control to open it fullscreen. The relevant sections are: **ReportView 完成形（確定：フルスクリーン）**, **設定画面**, **トリガー & 付随 UI**, **権限オフ（おやすみ）時の UX**, **UX フロー**, **SwiftUI トークン表**.

## Fidelity
**High-fidelity.** Final colors, type roles, spacing, component structure, and interaction model are decided. Recreate pixel-faithfully in SwiftUI, but prefer native system components (lists, sheets, toggles, share sheet) over visual clones. All colors below map to iOS system colors wherever possible — use the semantic system color, not a hardcoded hex, when one is named.

---

## Confirmed Decisions (read first)
1. **Presentation:** ReportView is a **full-screen modal** (`.fullScreenCover`). A half-modal sheet was explored and **rejected** (kept as reference only).
2. **Single exit = Share.** Top-right is the **Share** button (`square.and.arrow.up`) → OS share sheet (Photos / Files / AirDrop / other apps). No send button, no auto-save. Top-left is **✕** (cancel).
3. **No 完了 button, no success toast.** The user leaves by tapping ✕ themselves. (Earlier "完了" / "保存しました" affordances were removed.)
4. **Title = one generic single-line field.** No multi-field repro-steps form. The title field is shown **only when a clip exists** (it has no destination otherwise).
5. **Device info is quiet & unframed** — left-aligned, stacked rows (icon + monospace text), gray. Not boxed.
6. **Trim UI:** real-aspect video preview (no letterbox) + thumbnail filmstrip + two end handles + selection-range loop playback + playhead. Min selection 1 second.
7. **Trigger:** a persistent floating button (FAB) + shake. Overlay is transparent / pass-through; the FAB is a small real subview.
8. **Color rule (important):** **Orange = recording / actionable. Gray = not recording.** Brand neutral is Slate. Orange is used for: logo wedge, "Kit" wordmark, FAB while recording, all functional controls in ReportView (play, trim selection & handles, ✕, share, gear). In the **Settings screen only**, use **standard iOS colors** (green toggles, blue nav/links) — Settings is meant to feel system-native.

---

## Brand System

### Logo — "Time Slice" (Clean variant)
A clock with a **wedge/sector** cut from 12 o'clock clockwise — "the clock of time" + "the last N seconds captured." Build as an SVG/`Shape`, **not** a ladybug.

Construction (viewBox 64×64, center 32,32):
- **Ring:** `Circle` stroke, radius 20, stroke width ~3.2 (scales with size). Color = label/neutral.
- **Wedge:** filled sector from angle −66° to 0° measured from 12 o'clock going clockwise (i.e. a ~66° pie slice starting at top). Apex at center, radius 20. Color = **action orange**.
- **Hub:** filled `Circle` radius 2.6 at center. Color = label/neutral.
- The **Clean** variant has **no clock hand** (a "Hand" variant with a needle to 12 was explored and dropped).

Wordmark: `Flashback` in label color + `Kit` in **orange**, SF Pro/Text semibold, letter-spacing ≈ −0.02em.

### Mark states (drives the FAB look)
| State | Ring | Wedge fill | Button bg | Shape |
|---|---|---|---|---|
| Recording (normal) | white | white @ 0.5 opacity | **orange** | circle |
| Long-press (firing) | white | white @ 0.5 | orange + progress ring | circle |
| Edge-tucked (parked, still recording) | white | **orange** @ 1.0 | gray, ~0.82 opacity | **half-pill** stuck to edge |
| Dormant (recording OFF) | white | **neutral** — white @ 0.6 on the gray button; gray @ ~0.55 on light surfaces | gray | circle |

**Dormant wedge = "Neutral"** (decided): on the gray FAB use white @ 0.6; on a light surface (e.g. the ReportView empty-state clock) use gray @ ~0.55 (a faint white disappears on light backgrounds). Orange is reserved for "recording."

### FAB sizing (decided: "mark large")
- Button **56×56** pt (circle). Mark glyph **36** pt inside it → ratio ≈ 0.64. Keep tap target ≥ 44 pt.
- Edge-tucked: half-pill, ~30×34, glyph ~19.

---

## Typography
- **Family:** SF Pro / SF Pro Text for all UI (system default). **SF Mono** for tabular data: timecodes (`0:00 ~ 0:12 (0:12)`), device info (`iPhone 16` / `iOS 18.4` / `v1.0 (1)`), and any version strings.
- **Dynamic Type:** must follow. Use text styles (`.body`, `.headline`, `.footnote`, etc.), not fixed sizes, in the real build. Approx mapping used in the mock:
  - Nav title "Flashback": 16–17, semibold (`.headline`)
  - Section header (e.g. body content headings): 16, bold (`.headline`/`.title3`)
  - Field label "タイトル": 13, semibold
  - Body / row text: 14–15 (`.body`/`.subheadline`)
  - Device-info rows: 13, **SF Mono** (`.footnote`, monospaced)
  - Section captions (環境情報): 11, semibold, gray
  - Timecode: 13, SF Mono, tabular figures

---

## Design Tokens — "Quiet" (confirmed)

Prefer the named **iOS system color** when given; the hex is the mock's rendering for reference.

### Light
| Token | Hex | iOS system equivalent |
|---|---|---|
| Background | `#FFFFFF` | `systemBackground` |
| Grouped background / Field | `#F2F2F7` | `systemGroupedBackground` / `secondarySystemBackground` |
| Cell (settings) | `#FFFFFF` | `systemBackground` (grouped cell) |
| Label | `#000000` | `label` |
| Secondary label | `#8E8E93` | `secondaryLabel` |
| Tertiary label | `#B8B8BE` | `tertiaryLabel` |
| Separator | `#E3E3E8` | `separator` |
| **Brand neutral (Slate)** | `#5B6472` | custom |
| **Action / Control (Orange)** | `#D9821C` | custom (brand) |
| On-action | `#FFFFFF` | — |
| Success | `#34C759` | `systemGreen` |
| Warning | `#FF9F0A` | `systemOrange` |
| Danger | `#FF3B30` | `systemRed` |
| Settings nav/link & toggle | blue `#007AFF` / green `#34C759` | `systemBlue` / `systemGreen` |

### Dark
| Token | Hex | iOS system equivalent |
|---|---|---|
| Background | `#000000` | `systemBackground` |
| Grouped background / Field / Cell | `#1C1C1E` | `secondarySystemBackground` |
| Label | `#FFFFFF` | `label` |
| Secondary label | `#98989F` | `secondaryLabel` |
| Tertiary label | `#5A5A5F` | `tertiaryLabel` |
| Separator | `#2C2C2E` | `separator` |
| Brand neutral (Slate) | `#8B94A3` | custom |
| **Action / Control (Orange)** | `#E8A23E` | custom (brand) |
| On-action | `#2A1B08` | — |
| Success | `#30D158` | `systemGreen` |
| Warning | `#FF9F0A` | `systemOrange` |
| Danger | `#FF453A` | `systemRed` |
| Settings nav/link | blue `#0A84FF` | `systemBlue` |

### Geometry
- Field / input corner radius: **10**
- Settings grouped cell radius: **11**
- Video preview radius: **12–14**
- Filmstrip radius: **6–7**; trim selection border **2.5** pt in action color, with a 2 pt background-colored outer ring; handles **12–14** pt wide
- Toast capsule radius: **20** (pill), bg `rgba(20,20,24,0.9)` light / near-white in dark, text **12** pt
- FAB shadow: `0 4px 12px rgba(0,0,0,0.22)`
- Standard horizontal screen padding: **16**

---

## Screens / Views

### 1. ReportView (main UI) — full-screen modal
**Purpose:** review the auto-captured clip, trim it, optionally title it, and Share.

**Layout (top → bottom):**
1. **Status bar** (system).
2. **Nav bar (44pt):** left `✕` (orange, cancel) · center "Flashback" (16, semibold, label) · right group = **Share** (`square.and.arrow.up`, orange) then **gear** (`gearshape`, orange) with ~16pt gap. The gear is **always present regardless of permission state**.
3. **Body (16pt side padding):**
   - **Video preview**, centered, real aspect ratio (portrait clip ≈ 110×196 in mock), no letterbox, rounded 12–14, with a centered play affordance.
   - **Play control + range row:** small circular orange play button (30pt) + monospace `0:00 ~ 0:12 (0:12)` in secondary color.
   - **Filmstrip + trim:** full-width thumbnail strip; selection outlined in orange (2.5pt) with both end **handles** in orange (grip line inside); **playhead** thin vertical bar in label color. Min selection 1s; selection range loops on playback.
   - **タイトル** (only if clip exists): label (13, semibold) + single-line text field (height 38, radius 10, field bg, 1px separator border, placeholder "タイトルを入力" in tertiary).
   - **環境情報:** caption (11, semibold, tertiary) then stacked rows, each = SF-Symbol icon (iphone / gearshape / app) + **SF Mono** text. Quiet, unframed, left-aligned. Rows: `iPhone 16`, `iOS 18.4`, `v1.0 (1)`.
4. **Home indicator** (system).

**Empty / no-clip state** (Simulator, screen-recording unsupported, or recording OFF): same nav **but right side shows only the gear** (no Share, no 完了). Body shows a dashed placeholder box containing the **dormant clock mark** (gray ring + neutral wedge) and "録画はオフです", then a line "オンにすると、次回から直前の画面録画を自動で保持します。", then an orange **"録画をオンにする"** row, then 環境情報. **No title field** in this state. (Avoid QA-specific "不具合/バグ" wording — see copy note below.)

> **Copy note (decided):** Avoid QA-specific framing like "不具合" (bug) in the recording-feature description — the SDK only states that it can *recall the recording of the moments just before*; what the user does with it is up to them. Prefer phrasing like "オンにすると、直前の操作の録画を自動で保持します。" Keep this neutral wording in the build. (The mock may still show an older "不具合" string in places — use the neutral version.)

**Recording-just-enabled state ("録画オン直後")** — the *continuation* of the dormant state after the user taps "録画をオンにする" and permission is granted. Same nav (gear only, no Share; ✕ exits). The placeholder box now shows the **Time Slice mark in ORANGE (recording state)**, a positive heading **"録画をオンにしました"**, and a small **"● 録画中"** status pill (orange dot + orange label on a faint orange-tint background). Body copy: **"次回の起動操作から、直前の操作を自動で保持します。"** Then 環境情報. **No CTA button** (recording is already on), **no title field**, **no Share** (no clip yet). See `screenshots/05-recording-just-enabled.png`.
- *Why:* ReplayKit in-app capture has **no iOS Settings permission toggle** — permission is asked once via a system dialog at launch; declining can be retried via "録画をオンにする", which may re-present the dialog and enable recording. After it's enabled there is still **no clip for this session** (the past can't be recovered), so the copy must communicate "from next time." Color rule holds: gray→orange = "now recording."
- State transition: `dormant (OFF)` → tap "録画をオンにする" → permission granted → **`recording-just-enabled` (this state)**. (If permission can't be obtained and no dialog re-appears, branch to an "アプリを再起動してください" state — out of scope here.)
- Drive via a state enum, e.g. `emptyReason: .dormant | .justEnabled | .noClip`. In the mock: `PhoneReportView(empty: true, justEnabled: true)`.

### 2. Settings — pushed screen (system-native look)
Reached from the gear. **Uses standard iOS colors** (this screen should feel like Settings.app).
- Nav: `‹ レポート` back (blue) · center "設定".
- **表示** section: grouped cell with row "フローティングボタンを表示" + **green system toggle**. Footer: "オフにすると、シェイク操作のみでレポートを起動します。"
- **保持する録画の長さ** section: grouped list of `10 秒 / 20 秒 / 30 秒 / 60 秒`, selected row shows a **checkmark in action color**. Default **20秒**. Footer: "選択した秒数の録画を常に保持し、発火時に書き出します。長いほどメモリを使います。"
- **録画 (permission)** section: row "画面収録の権限" with status `許可済み` (green) / `許可されていません` (red); row "iOS の設定を開く" (blue) with an up-right arrow → deep-link to OS settings via `UIApplication.openSettingsURLString`. Footer explains permission is required to keep clips.

**Settings entry must work regardless of permission** — both the nav gear and the empty-state path lead here; the OS-permission deep link lives inside this screen.

### 3. Trigger (FAB) & ancillary UI
- **FAB** states as in the table above (recording / long-press / edge-tucked / dormant). Long-press 0.35s to fire; draggable; snaps/tucks to edges. Shake also fires. Must fire reliably on stationary devices.
- **Status toasts** (bottom-center capsule) — **only two**, memory-themed:
  - In-progress: **"記憶を辿っています…"** (orange spinner).
  - Failure: **"記憶の書き出しに失敗しました"** (systemRed, with a tappable blue **再試行** affordance + chevron; does not auto-dismiss).
  - **No success toast.** Permission-OFF produces **no toast** (handled by dormant FAB + in-ReportView guidance).

### 4. Permission-OFF ("おやすみ") UX
Do **not** punish users who declined recording with an error. When recording is OFF: FAB is **gray/dormant**; on fire, **bypass the export step and open ReportView immediately** showing the gentle "録画はオフです" invitation + "録画をオンにする"; the user can enable later in Settings (optional). Toast is suppressed for this case.

### 5. Screen-Recording Priming (pre-permission)
**Purpose:** bridge to the un-customizable iOS screen-recording system alert (ReplayKit).
The OS alert body/buttons can't be themed — only the app display name. Prime *before* it.
**Presentation:** half-sheet `.presentationDetents([.medium])` over the dormant ReportView.
(full-screen & an in-ReportView `.priming` state are kept as alternatives.)
**Flow:** dormant → tap「録画をオンにする」→ priming →「許可へ進む」→ OS alert → granted → `justEnabled`.
「あとで」returns to dormant (no toast).
**Once per device** (`hasPrimed`); after that, 録画ON → OS alert directly.
**Launch:** default OFF (no launch prompt). Settings toggle「アプリ起動時に権限を確認する」(default off)
→ on fires `startCapture` right after launch. No「iOS の設定を開く」row (ReplayKit has no Settings toggle).
**Color:** CTA = Action-Orange (enabling recording). Hero Time Slice mark = Slate-neutral (not yet recording).
**Copy (default A):** 見出し「画面収録をオンにします」/ 本文「次に表示される iOS の確認で『許可』を選ぶと、
アプリ内の直前の操作を自動で保持できます。」/ CTA「許可へ進む」「あとで」. Avoid 不具合/バグ wording.
**Don't show** when granted or recording unsupported (Simulator).

---

## Interactions & Behavior
- **Fire:** shake **or** long-press FAB 0.35s → (if recording) prepare & export with "記憶を辿っています…" toast → ReportView (full-screen). If recording OFF → bypass export → ReportView empty/invite state, no toast.
- **Trim:** drag handles (min 1s), selection loops on play, playhead tracks position.
- **Share:** top-right → `UIActivityViewController` (OS share sheet). This is the only exit besides ✕.
- **Cancel:** ✕ (top-left) or, in the rejected half-modal, swipe down.
- **Settings:** gear (always available) → push Settings; "iOS の設定を開く" deep-links to OS permission.
- **Gestures:** FAB long-press (0.35s) vs drag must be disambiguated; FAB tucks to nearest edge on release.
- **Reduced motion / VoiceOver:** provide labels for FAB ("Flashback を起動"), ✕, Share, gear, handles; respect reduced motion for the long-press progress ring.

## State Management
- `recordingEnabled: Bool` (permission + user toggle) → drives FAB color (orange/gray) and ReportView clip vs empty state.
- `screenRecordPermission: .granted | .denied`.
- `clip: Clip?` (nil → empty state). `trimRange: ClosedRange<Double>` (≥1s). `isPlaying`, `playhead`.
- `title: String` (only when clip present). `retentionSeconds: 10|20|30|60` (default 20). `floatingButtonVisible: Bool`.
- `fabState: .recording | .longPressing | .tucked | .dormant`. `fabPosition` (edge-snapped).
- `toast: .progress("記憶を辿っています…") | .failure("記憶の書き出しに失敗しました") | none`.

## SwiftUI Implementation Notes
- ReportView: `.fullScreenCover`. (Rejected alt for reference: `.presentationDetents([.medium,.large])` + `.presentationDragIndicator(.visible)`.)
- Settings: `Form`/`List` grouped style; native `Toggle` (green), selection rows with `checkmark`; deep link `UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)`.
- Logo/mark: custom `Shape` for ring + wedge + hub; parameterize ring/wedge color & opacity to express the four FAB states.
- Use SF Symbols: `xmark`, `square.and.arrow.up`, `gearshape`, `iphone`, `app`, `play.fill`, `checkmark`, `arrow.up.forward`.
- Brand colors as an asset catalog color set with light/dark variants (Slate + Action-Orange). All other colors → system semantic colors.
- Share = `UIActivityViewController`. Overlay window for FAB = transparent, pass-through, hosting a small interactive subview.

## Assets
No bitmap assets. The logo "Time Slice" mark is vector (recreate as `Shape`). Icons are **SF Symbols** (system). Filmstrip thumbnails and the video are real content at runtime (the mock uses neutral gray placeholders).

## Screenshots (reference renders)
In `screenshots/` — clean renders of each confirmed screen (light & dark):
- `01-reportview-clip.png` — ReportView with a clip (full-screen), light + dark.
- `02-reportview-empty.png` — ReportView empty / recording-OFF state, light + dark.
- `03-settings.png` — Settings: light (granted) · dark · permission-off+button-hidden+60s.
- `04-trigger-toast.png` — FAB states (recording / long-press / edge-tucked / dormant) + the two toasts.
- `05-recording-just-enabled.png` — ReportView "録画オン直後" state (orange mark + 録画中), light + dark.

## Files in this bundle
- `FlashbackKit - Phase 2.html` — the canvas with all confirmed screens + references. Open this first.
- `components.jsx` — ReportView, Settings, FAB/Toast, the Time Slice mark, icons, tokens-in-use.
- `directions.jsx` — the three brand directions incl. confirmed **Quiet** tokens (`DIRECTIONS[2]`).
- `phase2.jsx` — token tables, SwiftUI token board, trigger/toast board, FAB-size board, dormant-UX board, UX flow.
- `halfmodal.jsx` — the **rejected** half-modal alternative (reference only).
- `design-canvas.jsx` — the canvas harness (not part of the product).

> Tokens live in `directions.jsx` → `DIRECTIONS[2]` (`key: 'C'`, "Quiet"), `.light` and `.dark`. `ctrl` = the Action Orange; `accent` = the Slate brand neutral.
