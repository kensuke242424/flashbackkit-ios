import SwiftUI
import UIKit
import FlashbackKit

/// Host screen for exercising FlashbackKit's report loop.
///
/// Calling `Flashback.start()` at launch makes the SDK install the default triggers
/// (shake / floating button) on its overlay window.
/// Any trigger → ReportView → title input → share runs the loop.
///
/// To make recording easy to verify, the screen provides visible "motion":
/// - Home tab … a continuously animating object + elapsed time
/// - Tab switches / per-tab scrolling … screen transitions show up clearly in the clip
struct ContentView: View {
    @State private var startDate = Date()

    var body: some View {
        TabView {
            HomeTab(startDate: startDate)
                .tabItem { Label("Home", systemImage: "house") }
            DummyListTab()
                .tabItem { Label("List", systemImage: "list.bullet") }
            DummyGalleryTab()
                .tabItem { Label("Gallery", systemImage: "square.grid.2x2") }
            #if DEBUG
            DebugTab()
                .tabItem { Label("Debug", systemImage: "ladybug") }
            #endif
        }
        .onAppear {
            // triggers unspecified, so the defaults (shake + floating button) apply.
            // The Example sets runsOnSimulator=true to check the SDK's UI/behavior on the Simulator too.
            // (A real host defaults to false = doesn't start on the Sim.)
            Flashback.start(
                configuration: .init(runsOnSimulator: true),
                // Handoff: the finished artifact (recorded → trimmed → shared) arrives here.
                // AI summary / Slack delivery / your own integration go host-side (logged here as a demo).
                onReport: { report in
                    print("[Flashback] onReport: \(report.device.displayModel) / \(report.title)")
                    if let clip = report.clipURL {
                        print("[Flashback] clip: \(clip.path)")
                    }
                }
            )
            #if DEBUG
            Self.presentDemosFromEnvironment()
            #endif
        }
    }

    #if DEBUG
    /// Auto-presents a state specified via environment variable right after launch (for Simulator / automated checks).
    static func presentDemosFromEnvironment() {
        let env = ProcessInfo.processInfo.environment
        func after(_ delay: TimeInterval, _ action: @escaping () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
        }
        if env["FLASHBACK_TRIM_DEMO"] != nil { after(0.5) { Flashback.debugPresentSampleReport() } }
        if env["FLASHBACK_EMPTY_DEMO"] != nil { after(0.5) { Flashback.debugPresentEmptyReport() } }
        if env["FLASHBACK_JUST_ENABLED_DEMO"] != nil { after(0.5) { Flashback.debugPresentRecordingJustEnabled() } }
        if env["FLASHBACK_UNAVAILABLE_DEMO"] != nil { after(0.5) { Flashback.debugPresentReportUnavailable() } }
        if env["FLASHBACK_PRIMING_DEMO"] != nil { after(0.5) { Flashback.debugPresentPriming() } }
        if let toastKind = env["FLASHBACK_TOAST_DEMO"] { after(0.6) { Flashback.debugShowToast(toastKind) } }
        if env["FLASHBACK_SETTINGS_DEMO"] != nil { after(0.5) { Flashback.debugPresentSettings() } }
        if env["FLASHBACK_SHAKE_HINT_DEMO"] != nil { after(0.5) { Flashback.debugPresentShakeHint() } }
        // Auto-expands the report sheet to .large ~1.5s after it presents, to verify the .large
        // window backdrop (issue #20) without a manual swipe. Combine with a report demo (EMPTY/TRIM).
        if env["FLASHBACK_EXPAND_DEMO"] != nil { after(1.5) { Flashback.debugExpandReport() } }
        // Rotates the device to landscape (~2s) then back to portrait (~8s) to verify the FAB
        // re-clamps into the new bounds on rotation. Uses the iOS16+ public geometry-update API.
        if env["FLASHBACK_ROTATE_DEMO"] != nil {
            after(2.0) { rotate(to: .landscapeRight) }
            after(8.0) { rotate(to: .portrait) }
        }
    }

    /// Requests a window-scene orientation change (iOS 16+ public API). Used by the rotate demo.
    private static func rotate(to orientation: UIInterfaceOrientationMask) {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        scene?.requestGeometryUpdate(.iOS(interfaceOrientations: orientation))
    }
    #endif
}

// MARK: - Home tab

/// Home screen with launch status, a continuous animation, and debug entry points.
private struct HomeTab: View {
    let startDate: Date

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("FlashbackKit Example")
                    .font(.title2.bold())

                // Continuous animation for verifying recording (horizontal move + rotation + color change).
                MotionDemo(start: startDate)
                    .frame(height: 84)
                    .padding(.horizontal, 24)

                // Elapsed time since launch (mm:ss.SSS). Updates at 20fps; timestamps the motion.
                TimelineView(.periodic(from: startDate, by: 0.05)) { context in
                    Text(Self.elapsedString(from: startDate, to: context.date))
                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.tint)
                }

                Text("If the moving object, tab switches, and scrolling show up in the recorded clip, that's proof the last N seconds were captured correctly.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text("Shake the device (handheld) or long-press the floating button (stationary) to open the report UI.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                #if DEBUG
                // On-device HUD for observing recording state (interruption-detection behavior). Updates every 0.25s.
                TimelineView(.periodic(from: startDate, by: 0.25)) { _ in
                    Text(Flashback.debugRecordingStatusLine())
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 12)
                        .multilineTextAlignment(.center)
                }
                #endif
            }
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
    }

    /// Formats elapsed time as mm:ss.SSS.
    private static func elapsedString(from start: Date, to now: Date) -> String {
        let elapsed = max(0, now.timeIntervalSince(start))
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        let millis = Int((elapsed - elapsed.rounded(.down)) * 1000)
        return String(format: "%02d:%02d.%03d", minutes, seconds, millis)
    }
}

// MARK: - Dummy UI tabs (to leave screen transitions in the recording)

/// Scrolling dummy list. Tab switches + scrolling leave motion in the recording.
private struct DummyListTab: View {
    private let symbols = ["star.fill", "bell.fill", "bolt.fill", "leaf.fill", "flame.fill",
                           "drop.fill", "moon.fill", "heart.fill", "cloud.fill", "sun.max.fill"]
    var body: some View {
        NavigationStack {
            List(0..<30, id: \.self) { i in
                HStack(spacing: 12) {
                    Image(systemName: symbols[i % symbols.count])
                        .font(.title3)
                        .foregroundStyle(Color(hue: Double(i % 10) / 10, saturation: 0.7, brightness: 0.9))
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Item \(i + 1)").font(.body)
                        Text("Dummy row — scroll to see motion").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("List")
        }
    }
}

/// Grid of colored cards. Scrolling produces motion.
private struct DummyGalleryTab: View {
    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 12)]
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(0..<24, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(hue: Double(i) / 24, saturation: 0.65, brightness: 0.92))
                            .frame(height: 100)
                            .overlay(
                                Text("\(i + 1)")
                                    .font(.title.bold())
                                    .foregroundStyle(.white.opacity(0.9))
                            )
                    }
                }
                .padding(16)
            }
            .navigationTitle("Gallery")
        }
    }
}

// MARK: - Debug tab (instant preview of each state; DEBUG only)

#if DEBUG
/// Tab gathering dev entry points that instantly preview each ReportView state / settings / priming.
/// Kept here to keep Home tidy (also presentable right after launch via env vars).
private struct DebugTab: View {
    @State private var resetNote: String?
    @State private var secureFieldText = ""
    @State private var plainFieldText = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // ReplayKit can't actually record on the Simulator, so this entry checks
                    // the trimming UX with a synthetic sample video.
                    Button {
                        Flashback.debugPresentSampleReport()
                    } label: {
                        Label("Open trimmer with a sample video", systemImage: "scissors")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        Flashback.debugPresentEmptyReport()
                    } label: {
                        Label("Open the idle state", systemImage: "moon")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Flashback.debugPresentRecordingJustEnabled()
                    } label: {
                        Label("Open the just-enabled state", systemImage: "record.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Flashback.debugPresentReportUnavailable()
                    } label: {
                        Label("Open the recording-unavailable state", systemImage: "iphone.slash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Flashback.debugPresentPriming()
                    } label: {
                        Label("Open permission priming", systemImage: "hand.raised")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    // Reset the once-only priming read flag to re-test the first-run flow.
                    // After reset, tapping the FAB while recording is off (gray) shows it again.
                    Button(role: .destructive) {
                        Flashback.debugResetPriming()
                        resetNote = String(localized: "Priming read flag reset. Tap the FAB while recording is off (gray) to show it again.")
                    } label: {
                        Label("Reset priming read flag", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Flashback.debugPresentSettings()
                    } label: {
                        Label("Open settings", systemImage: "gearshape")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Flashback.debugPresentShakeHint()
                    } label: {
                        Label("Open the shake-twice hint", systemImage: "iphone.gen3.radiowaves.left.and.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    // Reset the once-only shake-hint read flag (once per device) to re-test the first presentation.
                    // After reset, it auto-presents again right after turning off the floating button in settings.
                    Button(role: .destructive) {
                        Flashback.debugResetShakeHint()
                        resetNote = String(localized: "Shake-hint read flag reset. Turn the FAB off in settings to show it again.")
                    } label: {
                        Label("Reset shake-hint read flag", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    if let resetNote {
                        Text(resetNote)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .transition(.opacity)
                    }

                    // Secure-input capture test: verifies what the SDK's own clip (ReplayKit
                    // in-app capture) actually records. iOS blanks secure text fields from
                    // *external* captures (OS recording / mirroring), but in-app capture renders
                    // the app's own content and may not get that protection. While recording,
                    // type into 1 / 2 / 4, then trigger a report and inspect the exported clip.
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Secure input capture test")
                            .font(.headline)
                        SecureField("1: SwiftUI SecureField", text: $secureFieldText)
                            .textFieldStyle(.roundedBorder)
                        SecureUIKitField()
                            .frame(height: 34)
                        SecureLayerTrickView()
                            .frame(height: 34)
                        TextField("4: plain TextField (control)", text: $plainFieldText)
                            .textFieldStyle(.roundedBorder)
                        Text("Check the clip for: the dots, the last-typed-character preview, and whether the red label (3) appears.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 12)
                }
                .padding(16)
                .animation(.easeInOut, value: resetNote)
                .task(id: resetNote) {
                    guard resetNote != nil else { return }
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    resetNote = nil
                }
            }
            .navigationTitle("Debug")
        }
    }
}

/// 2: a genuine UIKit `UITextField` with `isSecureTextEntry`, to compare against SwiftUI's
/// `SecureField` (1) in the capture test (their backing views could behave differently).
private struct SecureUIKitField: UIViewRepresentable {
    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.isSecureTextEntry = true
        field.borderStyle = .roundedRect
        field.placeholder = "2: UIKit isSecureTextEntry"
        return field
    }
    func updateUIView(_ uiView: UITextField, context: Context) {}
}

/// 3: the README's "secure-layer trick" — a label hosted inside a secure text field's internal
/// canvas layer (visible to the user, expected to be excluded from OS captures). Placed here to
/// test whether the SDK's own in-app capture excludes it as well.
private struct SecureLayerTrickView: UIViewRepresentable {
    /// Container keeping the field/label alive (the trick only moves *layers*; the views must
    /// stay retained or the label's layer contents could go stale).
    final class TrickContainer: UIView { var retained: [UIView] = [] }

    func makeUIView(context: Context) -> TrickContainer {
        let container = TrickContainer()
        let size = CGRect(x: 0, y: 0, width: 300, height: 34)

        let field = UITextField(frame: size)
        field.isSecureTextEntry = true
        field.isUserInteractionEnabled = false
        container.addSubview(field)

        let label = UILabel(frame: size)
        label.text = "3: SECRET via secure-layer trick"
        label.font = .boldSystemFont(ofSize: 15)
        label.textColor = .systemRed
        label.textAlignment = .center

        // README recipe: host the content's layer inside the secure field's canvas layer.
        if let secureCanvas = field.layer.sublayers?.first {
            secureCanvas.addSublayer(label.layer)
            label.layer.frame = size
        }
        container.retained = [field, label]
        return container
    }
    func updateUIView(_ uiView: TrickContainer, context: Context) {}
}
#endif

// MARK: - Continuous animation

/// Continuous animation for verifying recording (Example-only).
///
/// Combines three elements — horizontal movement (triangle-wave bounce) + rotation + hue cycle —
/// so any frame of the clip makes it obvious at a glance that things are "moving".
/// Driven by `TimelineView(.animation)` to animate smoothly in sync with display refresh.
private struct MotionDemo: View {
    let start: Date

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSince(start)
            let period = 2.4
            let phase = t.truncatingRemainder(dividingBy: period) / period   // 0..1
            let tri = phase < 0.5 ? phase * 2 : (1 - phase) * 2               // 0→1→0 (left/right bounce)
            let hue = (t / 6).truncatingRemainder(dividingBy: 1)             // cycle hue once every 6 seconds

            GeometryReader { geo in
                let size: CGFloat = 60
                let x = (geo.size.width - size) * tri
                let y = (geo.size.height - size) / 2
                ZStack(alignment: .topLeading) {
                    // Running lane (makes the position change easy to see).
                    Capsule()
                        .fill(Color(.secondarySystemBackground))
                        .frame(height: 6)
                        .frame(maxWidth: .infinity)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)

                    Circle()
                        .fill(Color(hue: hue, saturation: 0.75, brightness: 0.9))
                        .frame(width: size, height: size)
                        .overlay(
                            Image(systemName: "location.north.fill")     // rotation is visible via the heading
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.white)
                                .rotationEffect(.degrees(t * 120))        // 1.33 rotations/sec
                        )
                        .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                        .offset(x: x, y: y)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
