#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit

/// One-time "shake the device twice to launch" hint (centered alert-style card).
///
/// Right after `FlashbackSettingsStore.floatingButtonVisible` is turned off, the FAB disappears and the
/// launch method is no longer visible, so this passive FYI tells the user once, on the spot, that
/// **a double shake also launches**. Suppressed after one showing per device (`hasSeenShakeHint`).
/// Its role differs from priming (`.sheet` / an active step), so it's a centered alert-style card to
/// distinguish it. Copy variant C (no heading).
///
/// Strict color rule: this is a neutral notice unrelated to recording, so **no orange**. The base is
/// Slate (neutral brand); OK uses the standard systemBlue (borderless, iOS alert convention).
struct ShakeHintView: View {
    /// Dismiss via OK.
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                // Animated device glyph (pivot at the bottom; ±12° / ±9pt double shake). Decorative, so hidden from VoiceOver.
                ShakeGlyph()
                    .frame(width: 132, height: 132)

                // Copy variant C: no heading, body only, always states "2 times" explicitly.
                Text("端末を 2 回振ると、レポートを起動できます。")
                    .font(.subheadline)
                    .foregroundStyle(FlashbackColor.secondaryLabel)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                    .padding(.horizontal, 4)
                    .accessibilitySortPriority(2)             // Read order: body → OK
            }
            .padding(.top, 18)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            // OK: iOS alert convention (0.5pt separator on top + borderless systemBlue).
            Divider()
            Button(action: onDismiss) {
                Text("OK")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(FlashbackColor.settingsLink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .contentShape(Rectangle())
            }
            .accessibilitySortPriority(1)
        }
        .frame(width: 270)                                   // Standard iOS alert width
        .background(Self.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 20, y: 12)
        .accessibilityElement(children: .contain)
    }

    /// Card surface. Light = systemBackground (white) / dark = secondarySystemBackground (#1C1C1E).
    /// Floats above the dimmed background (dormant Settings).
    static let cardBackground = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? .secondarySystemBackground : .systemBackground
    })
}

// MARK: - Animated device glyph

/// Looping animation of the device shaking left-right twice.
///
/// Spec: pivot = bottom center. **Rotation ±12° / translation ±9pt**, each swing ≈130ms ease-in-out.
/// **4 swings ≈520ms (= 2 shakes) → ~1480ms rest → 2000ms loop, infinite.** The motion arcs (Slate)
/// blink in sync with the swings (opacity 0→0.85→0). Device aspect ratio ≈ 0.50 (real-device proportions).
/// `keyframeAnimator` is iOS17+, so to also run on iOS16 the keyframes are reproduced with an async
/// loop plus `withAnimation(.easeInOut)`.
///
/// Under **Reduce Motion**, no transform is applied; only the static arcs and icon (the body text carries the meaning).
struct ShakeGlyph: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var angle: Double = 0
    @State private var translateX: CGFloat = 0
    @State private var arcsOpacity: Double = 0

    private let slate = FlashbackColor.slate

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let phoneHeight = side * 0.68
            let phoneWidth = phoneHeight * 0.50          // Real-device proportions

            ZStack {
                // Motion arcs (left/right, blinking in sync with the swings).
                ShakeArcs()
                    .stroke(slate, style: StrokeStyle(lineWidth: side * (3.0 / 150), lineCap: .round, lineJoin: .round))
                    .opacity(reduceMotion ? 0.8 : arcsOpacity)

                // Device glyph (rotates and translates left/right, pivoting at the bottom).
                PhoneGlyph(slate: slate)
                    .frame(width: phoneWidth, height: phoneHeight)
                    .rotationEffect(.degrees(reduceMotion ? 0 : angle), anchor: .bottom)
                    .offset(x: reduceMotion ? 0 : translateX)
                    // Place the pivot (device bottom) at 84% down the square.
                    .position(x: side / 2, y: side * 0.84 - phoneHeight / 2)
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)                       // Decorative; the body Text carries the meaning.
        .task {
            guard !reduceMotion else { return }
            await runLoop()
        }
    }

    /// 2000ms loop: 4 swings (520ms) → rest (1480ms).
    @MainActor
    private func runLoop() async {
        while !Task.isCancelled {
            // rest → +12°/+9pt (fade the arcs in at the same time).
            apply(angle: 12, tx: 9, duration: 0.065, arcs: 0.85, arcsDuration: 0.08)
            if await sleep(0.065) { return }
            // -12°/-9pt (each swing ≈130ms).
            apply(angle: -12, tx: -9, duration: 0.130)
            if await sleep(0.130) { return }
            apply(angle: 12, tx: 9, duration: 0.130)
            if await sleep(0.130) { return }
            apply(angle: -12, tx: -9, duration: 0.130)
            if await sleep(0.130) { return }
            // Return to center (fade the arcs out).
            apply(angle: 0, tx: 0, duration: 0.065, arcs: 0, arcsDuration: 0.28)
            if await sleep(0.065) { return }
            // Rest (≈1480ms).
            if await sleep(1.480) { return }
        }
    }

    @MainActor
    private func apply(angle: Double, tx: CGFloat, duration: Double, arcs: Double? = nil, arcsDuration: Double = 0) {
        withAnimation(.easeInOut(duration: duration)) {
            self.angle = angle
            self.translateX = tx
        }
        if let arcs {
            withAnimation(.easeInOut(duration: arcsDuration)) { self.arcsOpacity = arcs }
        }
    }

    /// Returns `true` if cancelled (ends the loop).
    private func sleep(_ seconds: Double) async -> Bool {
        do { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
        catch { return true }
        return Task.isCancelled
    }
}

/// Device glyph (embeds a neutral Time Slice mark = ring + wedge). Drawn by uniformly scaling the
/// design coordinates 48×96 (real-device ratio 0.50) to the frame. All elements are Slate to honor
/// "unrelated to recording = no orange".
private struct PhoneGlyph: View {
    let slate: Color

    var body: some View {
        GeometryReader { geo in
            let k = geo.size.width / 48                  // Scale from the design viewBox width of 48
            ZStack(alignment: .topLeading) {
                // Body (filled with the card surface color, so only the outline shows).
                RoundedRectangle(cornerRadius: 11 * k, style: .continuous)
                    .fill(ShakeHintView.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 11 * k, style: .continuous)
                            .stroke(slate, lineWidth: 3.2 * k)
                    )
                    .frame(width: 44 * k, height: 92 * k)
                    .offset(x: 2 * k, y: 2 * k)

                // Screen.
                RoundedRectangle(cornerRadius: 5.5 * k, style: .continuous)
                    .fill(Self.screen)
                    .frame(width: 35 * k, height: 74 * k)
                    .offset(x: 6.5 * k, y: 9 * k)

                // Speaker.
                Capsule()
                    .fill(slate.opacity(0.5))
                    .frame(width: 12 * k, height: 2.2 * k)
                    .offset(x: 18 * k, y: 5.2 * k)

                // Neutral mini mark (all Slate, wedge @0.32). 32pt square at the design's translate(8,30) scale(0.50).
                TimeSliceMark(ringColor: slate, wedgeColor: slate.opacity(0.32), hubColor: slate)
                    .frame(width: 32 * k, height: 32 * k)
                    .offset(x: 8 * k, y: 30 * k)

                // Home line.
                Capsule()
                    .fill(slate.opacity(0.5))
                    .frame(width: 16 * k, height: 2.4 * k)
                    .offset(x: 16 * k, y: 88 * k)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    /// The glyph's screen surface (decorative). Light ≈ #F2F2F7 / dark ≈ #2C2C2E.
    static let screen = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0x2C / 255, green: 0x2C / 255, blue: 0x2E / 255, alpha: 1)
            : UIColor(red: 0xF2 / 255, green: 0xF2 / 255, blue: 0xF7 / 255, alpha: 1)
    })
}

/// Motion arcs (left/right) with small arrowheads at the tips. The design viewBox 150×150 is uniformly scaled to the frame.
private struct ShakeArcs: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 150       // Scale from the 150 coordinate space
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }

        var path = Path()

        // Left arc: design's M30 62 A24 24 …30 96 (bulges outward to the left), reproduced with a quad curve.
        path.move(to: p(30, 62))
        path.addQuadCurve(to: p(30, 96), control: p(16, 79))
        // Left arrowhead (top-left = points in the swing direction).
        path.move(to: p(28, 67)); path.addLine(to: p(22, 63))
        path.move(to: p(28, 67)); path.addLine(to: p(23, 73))

        // Right arc: M120 62 A24 24 …120 96 (bulges outward to the right).
        path.move(to: p(120, 62))
        path.addQuadCurve(to: p(120, 96), control: p(134, 79))
        // Right arrowhead.
        path.move(to: p(122, 67)); path.addLine(to: p(128, 63))
        path.move(to: p(122, 67)); path.addLine(to: p(127, 73))

        return path
    }
}

// MARK: - Presentation host (dimming scrim + centered card)

/// Presentation host that layers a dimming scrim and a centered card over the overlay window.
/// Presented with `.overFullScreen` + `.crossDissolve` (FlashbackPresenter); the card appears with a
/// spring effect, scaling up slightly (an "alert" feel, distinct from priming's slide-up).
struct ShakeHintHostView: View {
    let onDismiss: () -> Void
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.34)
                .ignoresSafeArea()
            ShakeHintView(onDismiss: onDismiss)
                .scaleEffect(appeared ? 1 : 0.92)
                .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { appeared = true }
        }
    }
}

#if DEBUG
#Preview("Shake Hint") {
    ZStack {
        Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
        ShakeHintHostView(onDismiss: {})
    }
}
#endif
#endif
