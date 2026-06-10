#if canImport(SwiftUI) && canImport(UIKit) && canImport(AVFoundation)
import SwiftUI
import UIKit
import AVFoundation

/// Report input UI ("Quiet" design, full screen).
///
/// Lets the user review the recent clip preview with trimming, title, and device
/// info, then hand it off to the OS share sheet (Photos / Files / AirDrop / other
/// apps) via the single **share (↑)** button in the top right. The only exits are
/// share or ✕ (cancel); there is no done/send button or success toast.
///
/// When there is no clip, one of three empty states is shown (none of which commit
/// an artifact, i.e. `onReport` is not fired):
/// - **dormant**: recording is off but the device can record (`isRecordingAvailable() == true`).
///   Shows "recording is off" plus an "enable recording" retry CTA.
/// - **just-enabled**: the moment the dormant CTA succeeds. Orange recording mark plus
///   "recording enabled / ● recording" (no CTA; still no clip this time around).
/// - **unavailable**: the device/environment can't record (`isRecordingAvailable() == false`:
///   Simulator, unsupported device, mirroring). Shows an informational notice only;
///   no CTA, since tapping it would never succeed.
///
/// Only used by the Presenter (UIKit + SwiftUI context), so UIKit/AVFoundation are assumed.
struct ReportView: View {
    /// Recent clip. `nil` shows the dormant (recording off) state.
    let clipURL: URL?
    /// Device info bundled into the report, displayed for QA to verify.
    /// `DeviceInfo.current()` is `@MainActor`, so the caller (Presenter) collects and passes it in.
    let device: DeviceInfo
    /// Share: trim the selected range, commit it, and return the final clip URL for the share sheet.
    let onShare: (String, ClosedRange<Double>?) async -> URL?
    /// Cancel (✕).
    let onCancel: () -> Void
    /// Request to expand the sheet to `.large` (call before pushing settings, which is cramped at half).
    let onRequestExpand: () -> Void
    /// Settings store (pushed from the gear or the dormant-state "enable recording" CTA).
    @ObservedObject var settings: FlashbackSettingsStore
    /// Half-modal expansion state (`.large` enlarges the video preview).
    @ObservedObject var detent: SheetDetentModel

    @State private var title = ""
    /// Selected range (seconds). `0...0` is uncommitted; the trimmer widens it to the full clip once the duration is known.
    @State private var selection: ClosedRange<Double> = 0...0
    @State private var shareItem: ShareItem?
    @State private var isWorking = false
    @State private var showingSettings = false
    @State private var showingPriming = false
    /// Title field focus state (when focused, the device info scrolls above the keyboard).
    @FocusState private var titleFocused: Bool

    private var hasClip: Bool { clipURL != nil }
    /// Scroll anchor ID for the device info section, used with `ScrollViewReader`.
    private static let deviceInfoAnchor = "fb.deviceInfo"

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let clipURL {
                            // At half the video is the focus (capped 200 so the clip bar stays visible).
                            // When expanded (.large) the sheet tends to have spare space at the bottom, so the video grows to fill it.
                            VideoTrimmerView(
                                url: clipURL,
                                // Slightly conservative (200) at half so the capture button at the bottom sits a
                                // little above the home-indicator band (insurance against OS gesture conflicts;
                                // the main fix is on the deferring side). Keep it from squeezing the recording view too much.
                                selection: $selection,
                                previewMaxHeight: detent.isExpanded ? 360 : 200,
                                // Render the frame at the playhead as an image and share it via the same OS share sheet as the clip.
                                onCaptureStill: { url in shareItem = ShareItem(url: url) },
                                // Reflect the title in the still's filename/metadata too (same as the clip).
                                currentTitle: { title },
                                // Keep the metadata description aligned with the clip share's device info string.
                                deviceDescription: "\(device.displayModel) / \(device.systemName) \(device.systemVersion)"
                            )
                            titleField
                        } else if settings.recordingJustEnabled {
                            justEnabledInvitation
                        } else if settings.isRecordingAvailable() {
                            dormantInvitation        // Recording off (e.g. denied). Retryable, so it has a CTA.
                        } else {
                            unavailableInvitation    // Recording unsupported here. No CTA.
                        }
                        DeviceInfoSection(device: device, insertionTitle: hasClip ? $title : nil)
                            .id(Self.deviceInfoAnchor)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: detent.isExpanded)
                }
                .scrollDismissesKeyboard(.interactively)
                // When the title gains focus, scroll the device info below it up above the keyboard so the user
                // can copy values into the title while reading them. Sync to `willShow` (when the keyboard starts
                // moving and the bottom inset is settled) rather than `didShow`, which would jolt with a separate
                // motion after the keyboard has fully appeared. Slide up in lockstep with the keyboard.
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { note in
                    if titleFocused { scrollDeviceInfoAboveKeyboard(proxy, note: note) }
                }
            }
            .background(FlashbackColor.background)
            .navigationTitle("レポート")           // Back-button label for the child (settings). Center title is overridden via principal.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .overlay { workingOverlay }
            .sheet(item: $shareItem) { ShareSheet(items: [$0.url]) }
            .sheet(isPresented: $showingPriming) {
                PermissionPrimingView(
                    onProceed: {
                        settings.hasPrimedScreenRecording = true   // Once per device
                        showingPriming = false
                        settings.retryRecording()                   // → startCapture (OS prompt) → just-enabled on success
                    },
                    onLater: { showingPriming = false }             // Back to dormant (no toast)
                )
                .presentationDetents([.medium])
            }
            .navigationDestination(isPresented: $showingSettings) {
                SettingsView(store: settings)
            }
        }
        .tint(FlashbackColor.action)   // ✕ / share / gear / controls in orange.
    }

    // MARK: - Navigation bar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text("Flashback")                       // Brand name stays English. Centered, label color.
                .font(FlashbackFont.navTitle)
                .foregroundStyle(FlashbackColor.label)
        }
        ToolbarItem(placement: .cancellationAction) {
            Button(action: onCancel) { Image(systemName: "xmark") }
                .accessibilityLabel("キャンセル")
                .disabled(isWorking)
        }
        // Right group: share (only when a clip exists) → gear (always).
        ToolbarItemGroup(placement: .primaryAction) {
            if hasClip {
                Button(action: share) { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("共有")
                    .disabled(isWorking)
            }
            Button {
                onRequestExpand()        // Settings is cramped at half, so expand to large before pushing.
                showingSettings = true
            } label: { Image(systemName: "gearshape") }
                .accessibilityLabel("設定")
                .disabled(isWorking)
        }
    }

    // MARK: - Title (only when a clip exists)

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("タイトル")
                .font(FlashbackFont.fieldLabel)
                .foregroundStyle(FlashbackColor.label)
            TextField(
                "",
                text: $title,
                prompt: Text("タイトルを入力").foregroundColor(FlashbackColor.tertiaryLabel)
            )
            .focused($titleFocused)
            .font(FlashbackFont.body)
            .foregroundStyle(FlashbackColor.label)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(FlashbackColor.field, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(FlashbackColor.separator, lineWidth: 1)
            )
            .submitLabel(.done)
        }
    }

    // MARK: - Dormant (recording off) state

    private var dormantInvitation: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Dashed placeholder box: dormant mark plus "recording is off".
            placeholderBox {
                TimeSliceMark.dormantOnSurface()
                    .frame(width: 40, height: 40)
                Text("録画はオフです")
                    .font(FlashbackFont.body)
                    .foregroundStyle(FlashbackColor.secondaryLabel)
            }

            // Neutral copy (avoids QA-specific "bug" wording; per README copy notes).
            Text("オンにすると、直前の操作の録画を自動で保持します。")
                .font(FlashbackFont.body)
                .foregroundStyle(FlashbackColor.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)

            // Enable recording (orange). First time goes through priming; afterward straight to the OS prompt (retry).
            Button(action: enableRecordingTapped) {
                HStack(spacing: 8) {
                    Image(systemName: "record.circle")
                    Text("録画をオンにする")
                }
                .font(FlashbackFont.body.weight(.semibold))
                .foregroundStyle(FlashbackColor.action)
            }
            .accessibilityLabel("録画をオンにする")
        }
    }

    // MARK: - Unavailable (Simulator / unsupported environment) state

    /// Empty state when the device/environment can't record (`isRecordingAvailable() == false`).
    /// Shows an informational notice only and **no CTA**, since "enable recording" would never succeed.
    /// Applies to the Simulator, unsupported devices, mirroring, etc.
    private var unavailableInvitation: some View {
        VStack(alignment: .leading, spacing: 16) {
            placeholderBox {
                TimeSliceMark.dormantOnSurface()           // Gray dormant mark
                    .frame(width: 40, height: 40)
                Text("この端末では画面収録を利用できません")
                    .font(FlashbackFont.body)
                    .foregroundStyle(FlashbackColor.secondaryLabel)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
            }

            // Neutral note on why it's unavailable. No CTA.
            Text("Simulator や画面収録に対応していない環境では録画できません。実機でお試しください。")
                .font(FlashbackFont.body)
                .foregroundStyle(FlashbackColor.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Just-enabled (recording on) state

    /// Continuation state right after the dormant "enable recording" CTA succeeds. The mark switches
    /// from gray dormant to orange recording, showing "recording enabled" plus a "● recording" pill.
    /// There's still no clip this time, so no share/title; exit via ✕ (the gear stays). No CTA.
    private var justEnabledInvitation: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Dashed placeholder box: recording mark (orange) + affirmative heading + "● recording" pill.
            placeholderBox {
                TimeSliceMark.recordingOnSurface()
                    .frame(width: 40, height: 40)
                Text("録画をオンにしました")
                    .font(FlashbackFont.body)
                    .foregroundStyle(FlashbackColor.label)
                recordingPill
            }

            // No clip this time, so neutral copy conveying "from next time on".
            Text("次回の起動操作から、直前の操作を自動で保持します。")
                .font(FlashbackFont.body)
                .foregroundStyle(FlashbackColor.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "● recording" status pill (orange dot + orange text on a faint orange tint background).
    private var recordingPill: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(FlashbackColor.action)
                .frame(width: 6, height: 6)
            Text("録画中")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(FlashbackColor.action)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(FlashbackColor.action.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("録画中")
    }

    /// Dashed placeholder box shared by the dormant and just-enabled states (corner radius 12, dashed border).
    private func placeholderBox<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 12, content: content)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        FlashbackColor.separator,
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                    )
            )
    }

    // MARK: - Working overlay (during share export)

    @ViewBuilder
    private var workingOverlay: some View {
        if isWorking {
            ProgressView()
                .controlSize(.large)
                .tint(FlashbackColor.secondaryLabel)   // Neutral gray for loading (cancels the inherited orange = actionable).
                .padding(24)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Actions

    /// Scroll the device info section up to the top of the keyboard (without moving the title).
    /// Title + device info fit comfortably in the space above the keyboard, so even with `.bottom`
    /// alignment the title stays visible, letting the user read the device info while typing.
    /// **Match the keyboard's animation duration and curve** so it rises smoothly together with the
    /// keyboard (matching only the duration with `.easeOut` starts faster than the keyboard's curve and
    /// gets ahead of it, which feels off).
    private func scrollDeviceInfoAboveKeyboard(_ proxy: ScrollViewProxy, note: Notification) {
        let info = note.userInfo
        let kbDuration = (info?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        // A touch faster than the keyboard (0.7x) for a snappier feel (curve kept matched).
        let duration = max(kbDuration * 0.7, 0.12)
        let curveRaw = (info?[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int) ?? 7
        let animation: Animation
        switch curveRaw {
        case 1: animation = .easeIn(duration: duration)
        case 2: animation = .easeOut(duration: duration)
        case 3: animation = .linear(duration: duration)
        default:
            // 0 = easeInOut / 7 = keyboard's default curve. Lean toward easeInOut, which starts
            // gently, to match the keyboard's rise in feel.
            animation = .easeInOut(duration: duration)
        }
        withAnimation(animation) {
            proxy.scrollTo(Self.deviceInfoAnchor, anchor: .bottom)
        }
    }

    /// Enable recording: show priming the first time on the device, go straight to the OS prompt (retry) afterward.
    private func enableRecordingTapped() {
        if settings.hasPrimedScreenRecording {
            settings.retryRecording()
        } else {
            showingPriming = true
        }
    }

    private func share() {
        isWorking = true
        Task {
            let url = await onShare(title, selection)
            isWorking = false
            if let url {
                shareItem = ShareItem(url: url)
            }
        }
    }
}

/// Device info. Shown supplementally in unboxed, muted gray text with SF Mono (left-aligned stack).
/// When a clip exists, each row gets a trailing ＋ button that inserts its value into the title's
/// trailing "｜…｜" segment. Once added, the button becomes − (remove) to take the value back out.
/// The buttons don't steal focus, so values can be inserted/removed while typing the title (keyboard up).
private struct DeviceInfoSection: View {
    let device: DeviceInfo
    /// Binding for inserting/removing device info into the title. When nil (no clip), no ＋/− is shown.
    var insertionTitle: Binding<String>? = nil
    /// Fields already added to the title, in insertion order, used to build "｜A｜B｜".
    @State private var added: [Field] = []

    /// The three displayed items.
    private enum Field: CaseIterable {
        case model, os, app
        var symbol: String {
            switch self {
            case .model: return "iphone"
            case .os: return "gearshape"
            case .app: return "app"
            }
        }
    }

    /// The value shown in the row (and inserted into the title).
    private func value(_ field: Field) -> String {
        switch field {
        case .model: return device.modelName
        case .os: return "\(device.systemName) \(device.systemVersion)"
        case .app: return "v\(device.appVersion) (\(device.buildNumber))"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("環境情報")
                .font(FlashbackFont.caption)
                .foregroundStyle(FlashbackColor.tertiaryLabel)
            // For human reading, so no identifiers (the record-keeping displayModel lives on the log side).
            ForEach(Field.allCases, id: \.self) { row($0) }
        }
    }

    private func row(_ field: Field) -> some View {
        HStack(spacing: 8) {
            Image(systemName: field.symbol)
                .frame(width: 16)
            Text(value(field))
                .font(FlashbackFont.mono)
            Spacer(minLength: 0)
            if let title = insertionTitle {
                insertButton(field, title: title)
            }
        }
        .foregroundStyle(FlashbackColor.secondaryLabel)
    }

    /// ＋ (add) / − (remove) toggle. Rebuilds the title's trailing "｜…｜" segment on tap.
    private func insertButton(_ field: Field, title: Binding<String>) -> some View {
        let isAdded = added.contains(field)
        return Button {
            toggle(field, title: title)
        } label: {
            Image(systemName: isAdded ? "minus.circle.fill" : "plus.circle")
                .font(.system(size: 18))
                .foregroundStyle(FlashbackColor.action)
                .frame(width: 28, height: 28)        // Ensure a tap target
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isAdded ? "タイトルから\(value(field))を除去" : "タイトルへ\(value(field))を追加")
    }

    /// Strip the title's trailing "｜…｜" to recover the base, toggle `added`, then rebuild.
    /// If the suffix isn't the expected "｜…｜" (the user hand-edited it), keep the base as-is and reappend.
    private func toggle(_ field: Field, title: Binding<String>) {
        let oldSuffix = suffix(for: added)
        var base = title.wrappedValue
        if !oldSuffix.isEmpty, base.hasSuffix(oldSuffix) {
            base.removeLast(oldSuffix.count)
        }
        if let idx = added.firstIndex(of: field) {
            added.remove(at: idx)
        } else {
            added.append(field)
        }
        title.wrappedValue = base + suffix(for: added)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Build "｜A｜B｜…｜" from the added fields (empty string if none).
    /// No surrounding brackets; place "｜" at every separator position (leading, between items, trailing).
    private func suffix(for fields: [Field]) -> String {
        guard !fields.isEmpty else { return "" }
        return "｜" + fields.map(value).joined(separator: "｜") + "｜"
    }
}

/// Identifiable share target for `.sheet(item:)`.
private struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// Bridges `UIActivityViewController` (the OS share sheet) into SwiftUI.
/// Saving to device (Photos / Files), AirDrop, and sending to other apps are all available here.
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif
