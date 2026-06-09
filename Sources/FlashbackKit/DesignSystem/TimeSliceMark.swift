#if canImport(SwiftUI)
import SwiftUI

/// The wedge (pie slice) Shape of the Time Slice logo.
///
/// A pie slice opening **counterclockwise (upper-left)** from 12 o'clock, evoking
/// a clock that "cuts out the last N seconds." The wedge spans `cd ∈ [−66°, 0°]`,
/// i.e. 66° counterclockwise from straight up (toward 10 o'clock), representing the
/// rewind (going back in time) direction.
///
/// Angles are given in **clock coordinates** (0° = 12 o'clock, increasing clockwise).
/// SwiftUI's `addArc(clockwise:)` flips meaning under its y-down coordinate space, so
/// the arc is point-sampled instead to remove any directional ambiguity.
struct TimeSliceWedge: Shape {
    /// Start angle of the wedge (12 o'clock origin, clockwise). Default 0° (straight up).
    var start: Angle = .degrees(0)
    /// Sweep angle (opens counterclockwise from straight up). Default 66°.
    var sweep: Angle = .degrees(66)

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        path.move(to: center)

        let steps = 48
        for i in 0...steps {
            // Open counterclockwise from straight up (cd toward negative) -> upper-left wedge.
            let clock = start.radians - sweep.radians * Double(i) / Double(steps)
            // Clock coords -> screen coords: 0° is straight up (0, -r), increasing clockwise.
            let x = center.x + radius * sin(clock)
            let y = center.y - radius * cos(clock)
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.closeSubpath()
        return path
    }
}

/// The Time Slice mark (ring + wedge + hand + hub).
///
/// Each element takes its own color so that swapping colors and opacity alone covers the
/// FAB's four states (recording / held / edge-tucked / dormant) and the logo. Dimensions
/// are based on viewBox 64 and scaled uniformly into the given frame (ring radius 20,
/// stroke 3.2, hub radius 2.6, hand pointing to 12 o'clock at r=18). The hand (clock hand
/// pointing to 12) shares the ring/hub color.
///
/// Set the size at the call site with `.frame(width:height:)` (e.g. 36pt for the FAB mark).
struct TimeSliceMark: View {
    var ringColor: Color
    var wedgeColor: Color
    var hubColor: Color
    var wedgeStart: Angle = .degrees(0)
    var wedgeSweep: Angle = .degrees(66)

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let k = side / 64                     // scale from viewBox 64
            let ringDiameter = 40 * k             // radius 20
            let strokeWidth = 3.2 * k
            let hubDiameter = 5.2 * k             // radius 2.6
            let handLength = 18 * k               // center -> 12 o'clock hand (r=18, 2 short of ring inner edge)

            ZStack {
                // Wedge (backmost). Layering the ring on top makes the ring an outline around the whole wedge.
                TimeSliceWedge(start: wedgeStart, sweep: wedgeSweep)
                    .fill(wedgeColor)
                    .frame(width: ringDiameter, height: ringDiameter)

                // Ring (above the wedge). When colored differently from the wedge, it reads as a full outline.
                Circle()
                    .stroke(ringColor, lineWidth: strokeWidth)
                    .frame(width: ringDiameter, height: ringDiameter)

                // Hand (toward 12 o'clock). Same color as ring/hub, round cap, extending straight up from center.
                Capsule()
                    .fill(ringColor)
                    .frame(width: strokeWidth, height: handLength)
                    .offset(y: -handLength / 2)

                Circle()
                    .fill(hubColor)
                    .frame(width: hubDiameter, height: hubDiameter)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)               // Decorative; meaning is carried by the parent's accessibilityLabel.
    }
}

extension TimeSliceMark {
    /// For the brand logo (ring/hub = label, wedge = Action Orange).
    static func logo() -> TimeSliceMark {
        TimeSliceMark(ringColor: FlashbackColor.label,
                      wedgeColor: FlashbackColor.action,
                      hubColor: FlashbackColor.label)
    }

    /// Recording-OFF (dormant) mark: gray ring + hand + hub only.
    /// To match the FAB's OFF state (wedge collapsed and hidden), the wedge is not drawn
    /// (`wedgeSweep = 0` shows "not recording = no slice" in the form itself).
    static func dormantOnSurface() -> TimeSliceMark {
        TimeSliceMark(ringColor: FlashbackColor.slate,
                      wedgeColor: FlashbackColor.slate.opacity(0.55),
                      hubColor: FlashbackColor.slate,
                      wedgeSweep: .degrees(0))
    }

    /// Mark for just after recording turns on (recording): all orange on a light surface.
    /// Expresses the color rule "gray -> orange = recording" (ReportView's justEnabled state).
    static func recordingOnSurface() -> TimeSliceMark {
        TimeSliceMark(ringColor: FlashbackColor.action,
                      wedgeColor: FlashbackColor.action,
                      hubColor: FlashbackColor.action)
    }
}

/// FlashbackKit wordmark: "Flashback" (label) + "Kit" (orange), semibold, slight tracking.
struct FlashbackWordmark: View {
    var size: Font.TextStyle = .headline

    var body: some View {
        (Text("Flashback").foregroundColor(FlashbackColor.label)
         + Text("Kit").foregroundColor(FlashbackColor.action))
            .font(.system(size, design: .default).weight(.semibold))
            .tracking(-0.3)                       // ≈ -0.02em
            .accessibilityLabel("FlashbackKit")
    }
}

/// Logo lockup: mark + wordmark.
struct FlashbackLogo: View {
    var markSize: CGFloat = 22

    var body: some View {
        HStack(spacing: 6) {
            TimeSliceMark.logo()
                .frame(width: markSize, height: markSize)
            FlashbackWordmark()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("FlashbackKit")
    }
}

#if DEBUG
#Preview("Time Slice") {
    VStack(spacing: 28) {
        FlashbackLogo()
        HStack(spacing: 20) {
            // Recording (orange FAB: white ring, white@0.5 wedge)
            TimeSliceMark(ringColor: .white,
                          wedgeColor: .white.opacity(0.5),
                          hubColor: .white)
                .frame(width: 36, height: 36)
                .padding(10)
                .background(FlashbackColor.action, in: Circle())

            // Edge-tucked (gray FAB, orange@1.0 wedge)
            TimeSliceMark(ringColor: .white,
                          wedgeColor: FlashbackColor.action,
                          hubColor: .white)
                .frame(width: 36, height: 36)
                .padding(10)
                .background(FlashbackColor.slate.opacity(0.82), in: Circle())

            // Dormant (on a light surface)
            TimeSliceMark.dormantOnSurface()
                .frame(width: 36, height: 36)
        }
    }
    .padding(40)
}
#endif
#endif
