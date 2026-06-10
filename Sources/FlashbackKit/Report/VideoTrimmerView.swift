#if canImport(SwiftUI) && canImport(AVFoundation) && canImport(UIKit)
import SwiftUI
import AVFoundation
import UIKit
import ImageIO
import UniformTypeIdentifiers

/// Preview + range-trimming UI for the recording clip.
///
/// Lays a thumbnail filmstrip under the preview (`AVPlayerLayer`); the two handles pick the
/// selection range. The range (in seconds) is two-way bound to `selection`.
/// Zero dependencies (AVFoundation / SwiftUI / UIKit only).
@MainActor
struct VideoTrimmerView: View {
    let url: URL
    /// Selection range (seconds). Passing an initial value with `lowerBound == upperBound` widens to the full range once the duration is known.
    @Binding var selection: ClosedRange<Double>
    /// Max height of the preview frame. Small in the half-modal, larger when expanded.
    var previewMaxHeight: CGFloat = 280
    /// Renders the frame at the playhead at full resolution and hands back a temp-file URL for sharing.
    /// When `nil`, the camera (still capture) button is hidden.
    var onCaptureStill: ((URL) -> Void)? = nil
    /// Returns the title at capture time (report input). Like clip sharing, it feeds the file name and the
    /// image metadata title. Taken as a closure so the latest in-progress value is read.
    var currentTitle: () -> String = { "" }
    /// Device info burned into the image metadata description (same string as the clip share's mp4 description).
    var deviceDescription: String = ""

    /// Minimum selection length (seconds); handles can't be squeezed past this.
    private let minimumDuration: Double = 1.0

    @State private var player = AVPlayer()
    @State private var duration: Double = 0
    @State private var thumbnails: [UIImage] = []
    @State private var playhead: Double = 0
    @State private var isPlaying = false
    /// Whether the playhead is being dragged. Stops the periodic observer from overwriting the playhead so it follows the finger.
    @State private var isScrubbing = false
    /// Whether a still is being written out. Guards against a double-tap and shows the button as a spinner.
    @State private var isCapturingStill = false
    /// Opacity for the brief white "shutter" flash on capture (0 -> 0.85 -> 0).
    @State private var flashOpacity: Double = 0
    @State private var timeObserver: Any?
    /// Display aspect ratio (width/height). Derived from the real track once the duration is known; matching the
    /// preview frame to it avoids letterboxing. Provisional portrait value until then.
    @State private var videoAspect: CGFloat = 9.0 / 16.0

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Spacer(minLength: 0)
                PlayerLayerView(player: player)
                    .aspectRatio(videoAspect, contentMode: .fit)
                    .frame(maxHeight: previewMaxHeight)
                    .background(.black, in: RoundedRectangle(cornerRadius: 12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        if duration == 0 {
                            ProgressView().tint(.white)
                        } else if !isPlaying {
                            // Paused-state poster. The whole video area handles taps, so this is non-interactive.
                            Image(systemName: "play.fill")
                                .font(.title3)
                                .foregroundStyle(.white)
                                .padding(16)
                                .background(.black.opacity(0.35), in: Circle())
                                .allowsHitTesting(false)
                        }
                    }
                    // White shutter flash on capture. Clipped to the video shape, non-interactive.
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.white)
                            .opacity(flashOpacity)
                            .allowsHitTesting(false)
                    }
                    // Tap anywhere on the video area to toggle play/pause (a tap while playing stops it).
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                    .onTapGesture { if duration > 0 { togglePlay() } }
                    .accessibilityElement(children: .ignore)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("プレビュー")
                    .accessibilityValue(isPlaying ? "再生中" : "一時停止中")
                    .accessibilityHint("タップで再生 / 一時停止")
                    .accessibilityAction { if duration > 0 { togglePlay() } }
                Spacer(minLength: 0)
            }

            HStack(spacing: 12) {
                // Small round orange play button (30pt).
                Button(action: togglePlay) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(FlashbackColor.onAction)
                        .frame(width: 30, height: 30)
                        .background(FlashbackColor.action, in: Circle())
                }
                .disabled(duration == 0)
                .accessibilityLabel(isPlaying ? "一時停止" : "再生")

                Text(rangeLabel)
                    .font(FlashbackFont.timecode)
                    .foregroundStyle(FlashbackColor.secondaryLabel)
                Spacer()
            }

            FilmstripTrimmer(
                thumbnails: thumbnails,
                duration: duration,
                minimumDuration: minimumDuration,
                playhead: playhead,
                selection: $selection,
                onScrub: { seconds in seek(to: seconds) },
                onScrubBegan: { beginScrub() },
                onScrubEnded: { isScrubbing = false },
                // The camera button tracking just below the playhead triggers still capture.
                onCapture: onCaptureStill != nil ? { captureStill() } : nil,
                isCapturing: isCapturingStill
            )
        }
        .task(id: url) { await load() }
        .onDisappear { teardown() }
    }

    private var rangeLabel: String {
        guard duration > 0 else { return "—" }
        return "\(format(selection.lowerBound)) ~ \(format(selection.upperBound))  (\(format(selection.upperBound - selection.lowerBound)))"
    }

    private func format(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Loading

    private func load() async {
        let asset = AVURLAsset(url: url)
        guard let loaded = try? await asset.load(.duration) else { return }
        let seconds = CMTimeGetSeconds(loaded)
        guard seconds.isFinite, seconds > 0 else { return }

        player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
        duration = seconds
        if selection.lowerBound >= selection.upperBound {
            // First load (unset): select "midpoint...end" (keeping the minimum length).
            // Put the playhead / preview / camera button at the tail of the recording (the latest frame),
            // so "screenshot the current screen as-is" works immediately.
            let start = max(0, min(seconds / 2, seconds - minimumDuration))
            selection = start...seconds
            seek(to: seconds)
        } else {
            // Reload (e.g. .task re-runs after pushing to settings and back): keep the selection.
            // replaceCurrentItem reset the play position to 0; restore it to the last playhead (clamped into
            // the selection). Otherwise the periodic observer syncs the playhead to 0 and only the camera button
            // jumps to the left edge (the selection stays centered).
            seek(to: min(max(playhead, selection.lowerBound), selection.upperBound))
        }
        // Derive the display aspect ratio from the real track and match the preview frame (no letterboxing).
        if let track = try? await asset.loadTracks(withMediaType: .video).first,
           let natural = try? await track.load(.naturalSize),
           let transform = try? await track.load(.preferredTransform) {
            let displayed = natural.applying(transform)
            let w = abs(displayed.width), h = abs(displayed.height)
            if w > 0, h > 0 { videoAspect = w / h }
        }
        addObserver()
        await generateThumbnails(asset: asset, duration: seconds)
    }

    private func generateThumbnails(asset: AVURLAsset, duration: Double) async {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 160)
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity

        let count = 8
        var images: [UIImage] = []
        for i in 0..<count {
            let t = duration * Double(i) / Double(count - 1)
            let time = CMTime(seconds: t, preferredTimescale: 600)
            if let cg = try? await generator.image(at: time).image {
                images.append(UIImage(cgImage: cg))
            }
        }
        thumbnails = images
    }

    // MARK: - Playback

    private func togglePlay() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            // If the playhead is outside the selection, start from the beginning of it.
            if playhead < selection.lowerBound || playhead >= selection.upperBound {
                seek(to: selection.lowerBound)
            }
            player.play()
            isPlaying = true
        }
    }

    private func seek(to seconds: Double) {
        let clamped = min(max(seconds, 0), duration)
        playhead = clamped
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
    }

    // MARK: - Still capture

    /// Extracts the frame at the playhead at full resolution, writes it as a PNG temp file, and hands it to sharing.
    ///
    /// Sets `AVAssetImageGenerator`'s tolerance to 0 to grab the exact frame the playhead is on (unlike thumbnail
    /// generation, which uses infinite tolerance for speed). `appliesPreferredTrackTransform` corrects rotation.
    /// The source is an already-compressed video frame, so write PNG to avoid re-JPEG smearing on text.
    private func captureStill() {
        guard duration > 0, !isCapturingStill else { return }
        // If playing, pause so the visible frame matches the one written out.
        if isPlaying {
            player.pause()
            isPlaying = false
        }
        playCaptureFeedback()   // haptic + white preview flash (immediate "shutter" feedback)
        isCapturingStill = true
        // Exactly at the tail (duration) the zero-tolerance generator misses the frame (there's no frame at
        // duration), so nudge slightly inward. Ensures the latest frame is captured even at the default tail.
        let seconds = min(max(playhead, 0), max(duration - 0.05, 0))
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        let sourceURL = url
        let title = currentTitle()
        let description = deviceDescription
        // VideoTrimmerView is @MainActor, so this Task inherits MainActor isolation
        // (keeps UIImage/CGImage from crossing isolation, i.e. avoids the known Sendable pitfall).
        Task {
            defer { isCapturingStill = false }
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: sourceURL))
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            guard let cg = try? await generator.image(at: time).image else { return }
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(stillFileName(at: seconds, title: title))
            try? FileManager.default.removeItem(at: fileURL)   // avoid same-name collision
            guard writeTitledPNG(cg, title: title, description: description, to: fileURL) else { return }
            onCaptureStill?(fileURL)
        }
    }

    /// Capture feedback: haptic (light impact) + white preview flash.
    /// Commit the lit state first, then decay on the next frame: writing 0.85 -> 0 in one loop never renders
    /// the intermediate 0.85 (so no flash), so the decay is deferred asynchronously.
    private func playCaptureFeedback() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        flashOpacity = 0.85
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.35)) { flashOpacity = 0 }
        }
    }

    /// Share file name, kept consistent with the clip share's title convention:
    /// - With title: `<sanitized title>-<timecode>.png` (a still is one moment, so the time tells which frame).
    /// - Empty title: `flashback-screenshot-<timestamp>.png` (only the kind differs from the clip's `flashback-video-...`).
    private func stillFileName(at seconds: Double, title: String) -> String {
        guard !title.isEmpty else { return "\(ClipTrimmer.fallbackName(kind: "screenshot")).png" }
        let total = Int(seconds.rounded())
        let stamp = String(format: "%dm%02ds", total / 60, total % 60)
        return "\(ClipTrimmer.sanitizedFileName(title))-\(stamp).png"
    }

    /// Writes a PNG with title / description, mirroring the clip's mp4 metadata roles:
    /// title = title (only when present), description = device info (always). Embedded into PNG tEXt (iTXt/XMP).
    private func writeTitledPNG(_ cgImage: CGImage, title: String, description: String, to url: URL) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { return false }
        var png: [CFString: Any] = [:]
        if !title.isEmpty { png[kCGImagePropertyPNGTitle] = title }
        if !description.isEmpty { png[kCGImagePropertyPNGDescription] = description }
        let properties: [CFString: Any] = png.isEmpty ? [:] : [kCGImagePropertyPNGDictionary: png]
        CGImageDestinationAddImage(dest, cgImage, properties as CFDictionary)
        return CGImageDestinationFinalize(dest)
    }

    /// Begin a playhead drag (idempotent). Pauses if playing and stops the observer from overwriting the playhead.
    private func beginScrub() {
        guard !isScrubbing else { return }
        isScrubbing = true
        if isPlaying {
            player.pause()
            isPlaying = false
        }
    }

    private func addObserver() {
        guard timeObserver == nil else { return }
        let interval = CMTime(seconds: 0.03, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            // The periodic observer is a @Sendable handler; hop back to MainActor-isolated state via Task.
            let seconds = CMTimeGetSeconds(time)
            Task { @MainActor in
                // While scrubbing, finger-follow wins (the observer doesn't overwrite the playhead).
                guard !isScrubbing else { return }
                playhead = seconds
                // At the selection's end, rewind to its start and pause (shows play, one tap replays).
                // When upperBound == duration, AVPlayer auto-pauses at the real end, so set pause()/isPlaying explicitly too.
                if isPlaying, seconds >= selection.upperBound {
                    seek(to: selection.lowerBound)
                    player.pause()
                    isPlaying = false
                }
            }
        }
    }

    private func teardown() {
        player.pause()
        isPlaying = false
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }
}

/// Minimal view bridging `AVPlayerLayer` into SwiftUI (no default controls).
private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        uiView.playerLayer.player = player
    }

    final class PlayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

/// Thumbnail filmstrip + the two handles + the playhead.
private struct FilmstripTrimmer: View {
    let thumbnails: [UIImage]
    let duration: Double
    let minimumDuration: Double
    let playhead: Double
    @Binding var selection: ClosedRange<Double>
    let onScrub: (Double) -> Void
    /// Playhead drag begin (idempotent) / end. Tells the parent to pause and suppress the observer while scrubbing.
    var onScrubBegan: () -> Void = {}
    var onScrubEnded: () -> Void = {}
    /// Tap on the camera button below the playhead triggers still capture. When `nil`, the tracking track is hidden.
    var onCapture: (() -> Void)? = nil
    /// Still is being written out. Shows the button as a spinner and blocks a double-tap.
    var isCapturing: Bool = false

    /// True while a finger is on the camera button. Swells it slightly while pressed for feedback
    /// (releasing ends the gesture, which resets this to false and springs it back).
    @GestureState private var isPressingCapture = false

    private let handleWidth: CGFloat = 14
    /// Transparent hit area for the handle (wider than its look so it grabs more reliably than the scrub surface).
    private let handleHitWidth: CGFloat = 34
    private let stripHeight: CGFloat = 56
    /// Height fitting the capture button exactly (caret 6 + circle 34 = 40). Keeps the bottom padding tight.
    private let captureTrackHeight: CGFloat = 40

    var body: some View {
        VStack(spacing: 4) {
            filmstripBar
                .frame(height: stripHeight)
            if onCapture != nil {
                captureTrack
            }
        }
    }

    /// The main bar: thumbnails + the two handles + the playhead (fixed height).
    private var filmstripBar: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let usable = max(width - handleWidth * 2, 1)
            let startX = handleWidth + xOffset(for: selection.lowerBound, usable: usable)
            let endX = handleWidth + xOffset(for: selection.upperBound, usable: usable)

            ZStack(alignment: .leading) {
                filmstrip(width: width, height: height)

                // Dim outside the selection.
                dim(width: startX, height: height)
                dim(width: width - endX, height: height).offset(x: endX)

                // Playhead visual (behind the orange clip bar, non-interactive: thin vertical bar).
                if duration > 0 {
                    playheadVisual(at: handleWidth + xOffset(for: playhead, usable: usable), height: height)
                }

                // Selection frame: background-color outer ring (2pt) + action-color border (2.5pt).
                RoundedRectangle(cornerRadius: 6)
                    .stroke(FlashbackColor.background, lineWidth: 6)
                    .frame(width: max(endX - startX, 0), height: height)
                    .offset(x: startX)
                RoundedRectangle(cornerRadius: 6)
                    .stroke(FlashbackColor.action, lineWidth: 2.5)
                    .frame(width: max(endX - startX, 0), height: height)
                    .offset(x: startX)

                // Playhead grab (a small area over the head). Placed behind the handles (lower z order) so the
                // clip bar (trim) stays primary; the playhead is grabbable as a fallback where it doesn't overlap a handle.
                if duration > 0 {
                    playheadGrab(at: handleWidth + xOffset(for: playhead, usable: usable),
                                 height: height, usable: usable)
                }

                handle(at: startX, height: height, usable: usable, isStart: true)
                handle(at: endX, height: height, usable: usable, isStart: false)
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .coordinateSpace(name: "strip")
        }
    }

    /// Camera button tracking just below the playhead (an up caret signals "capture this position").
    /// Uses the same x mapping as the strip (full width, same `handleWidth`), so it lines up under the head.
    /// Clamps the button center by its radius so it isn't clipped at the edges.
    private var captureTrack: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let usable = max(width - handleWidth * 2, 1)
            let headX = handleWidth + xOffset(for: playhead, usable: usable)
            let radius: CGFloat = 17
            let cx = min(max(headX, radius), width - radius)
            CaptureHeadButton(isCapturing: isCapturing)
                .scaleEffect(isPressingCapture ? 1.14 : 1.0)   // swell slightly while pressed (feedback)
                .animation(.spring(response: 0.26, dampingFraction: 0.55), value: isPressingCapture)
                .padding(.horizontal, 8)             // widen the horizontal hit area for easier dragging
                .contentShape(Rectangle())
                .position(x: cx, y: 20)
                .gesture(captureGesture(usable: usable))
                .accessibilityElement()
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("この瞬間を画像で保存")
                .accessibilityHint("再生ヘッドの位置の画面を画像として共有します。左右ドラッグで位置調整。")
                .accessibilityAction { onCapture?() }
        }
        .frame(height: captureTrackHeight)
        .coordinateSpace(name: "captureTrack")
        .disabled(duration == 0)
    }

    /// Camera button gesture. Horizontal drag = scrub the play position; release with almost no movement = tap = capture.
    /// Uses the same seconds conversion as the playhead grab (`playheadGrab`) and clamps into the selection.
    private func captureGesture(usable: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("captureTrack"))
            .updating($isPressingCapture) { _, pressing, _ in pressing = true }
            .onChanged { value in
                // Keep tiny jitter as a tap; start scrubbing only after some movement.
                guard abs(value.translation.width) > 3 else { return }
                onScrubBegan()
                let seconds = secondsForX(value.location.x - handleWidth, usable: usable)
                onScrub(clampToSelection(seconds))
            }
            .onEnded { value in
                let isTap = abs(value.translation.width) <= 3 && abs(value.translation.height) <= 3
                onScrubEnded()
                if isTap { onCapture?() }
            }
    }

    /// Pin the height to prevent overflow (without it, .fill spills vertically and covers the UI below).
    ///
    /// `.clipped()` only clips the *drawing*: `scaledToFill` still lays each thumbnail's backing view out at
    /// its un-clipped size, so on wide cells (iPad) the image view overflows the strip height upward and ends up
    /// hit-testing on top of the play button just above it (it has no gesture, so the tap is silently swallowed —
    /// the button looks dead). The strip is display-only (scrub / handles live in their own overlay layers), so
    /// drop its hit testing entirely to keep those overflowing image views from stealing neighboring taps.
    private func filmstrip(width: CGFloat, height: CGFloat) -> some View {
        let count = max(thumbnails.count, 1)
        let cellWidth = width / CGFloat(count)
        return HStack(spacing: 0) {
            if thumbnails.isEmpty {
                Rectangle().fill(.gray.opacity(0.3))
            } else {
                ForEach(Array(thumbnails.enumerated()), id: \.offset) { _, image in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: cellWidth, height: height)
                        .clipped()
                }
            }
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
    }

    private func dim(width: CGFloat, height: CGFloat) -> some View {
        Rectangle()
            .fill(.black.opacity(0.5))
            .frame(width: max(width, 0), height: height)
            .allowsHitTesting(false)
    }

    /// Handle that follows the finger's absolute position ("strip" coords), avoiding accumulated-translation drift.
    /// Looks `handleWidth` wide but has a wider hit area (`handleHitWidth`) so it grabs more reliably than the scrub surface.
    private func handle(at x: CGFloat, height: CGFloat, usable: CGFloat, isStart: Bool) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(FlashbackColor.action)
            .frame(width: handleWidth, height: height)
            .overlay(
                Capsule().fill(FlashbackColor.onAction).frame(width: 3, height: 18)
            )
            .frame(width: handleHitWidth, height: height)   // wide transparent hit area (visual is the centered handleWidth)
            .contentShape(Rectangle())
            .offset(x: x - handleHitWidth / 2)
            .accessibilityLabel(isStart ? "開始位置" : "終了位置")
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("strip"))
                    .onChanged { value in
                        let seconds = secondsForX(value.location.x - handleWidth, usable: usable)
                        if isStart {
                            let upper = selection.upperBound
                            let newLower = min(max(seconds, 0), upper - minimumDuration)
                            selection = newLower...upper
                            onScrub(newLower)
                        } else {
                            let lower = selection.lowerBound
                            let newUpper = max(min(seconds, duration), lower + minimumDuration)
                            selection = lower...newUpper
                            onScrub(newUpper)
                        }
                    }
            )
    }

    /// Playhead visual (thin vertical bar only). Non-interactive (the grab is a separate layer).
    private func playheadVisual(at x: CGFloat, height: CGFloat) -> some View {
        Rectangle()
            .fill(FlashbackColor.label)
            .frame(width: 2, height: height)
            .offset(x: x)
            .allowsHitTesting(false)
    }

    /// Playhead grab (a small area over the head). Clamps the position into the selection and seeks.
    /// Where it overlaps a handle (wide hit area, higher z order), trim wins so the clip bar stays primary.
    /// The grab is narrower than the handle's hit area so the handle reliably wins on overlap.
    private func playheadGrab(at x: CGFloat, height: CGFloat, usable: CGFloat) -> some View {
        let grabWidth: CGFloat = 26
        return Color.clear
            .frame(width: grabWidth, height: height)
            .contentShape(Rectangle())
            .offset(x: x - grabWidth / 2 + 1)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("strip"))
                    .onChanged { value in
                        onScrubBegan()
                        let seconds = secondsForX(value.location.x - handleWidth, usable: usable)
                        onScrub(clampToSelection(seconds))
                    }
                    .onEnded { _ in onScrubEnded() }
            )
            .accessibilityLabel("再生位置")
            .accessibilityValue(timeLabel(playhead))
            .accessibilityAdjustableAction { direction in
                let target = direction == .increment ? playhead + 1 : playhead - 1
                onScrubBegan()
                onScrub(clampToSelection(target))
                onScrubEnded()
            }
    }

    /// Clamp into the selection range (never outside the trim).
    private func clampToSelection(_ seconds: Double) -> Double {
        min(max(seconds, selection.lowerBound), selection.upperBound)
    }

    private func timeLabel(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func xOffset(for seconds: Double, usable: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        return usable * CGFloat(seconds / duration)
    }

    private func secondsForX(_ x: CGFloat, usable: CGFloat) -> Double {
        guard usable > 0 else { return 0 }
        return Double(x / usable) * duration
    }
}

/// Visual of the capture button sitting under the playhead (up caret + round camera button).
/// Outlined (background-color fill + action-color border) to distinguish it from the filled play button.
/// Interaction (tap = capture / horizontal drag = scrub) is handled together by the parent `captureTrack`.
private struct CaptureHeadButton: View {
    let isCapturing: Bool

    var body: some View {
        VStack(spacing: 0) {
            CaretUp()
                .fill(FlashbackColor.action)
                .frame(width: 12, height: 6)
            ZStack {
                Circle()
                    .fill(FlashbackColor.background)
                    .overlay(Circle().stroke(FlashbackColor.action, lineWidth: 1.5))
                if isCapturing {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(FlashbackColor.action)
                } else {
                    Image(systemName: "camera")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(FlashbackColor.action)
                }
            }
            .frame(width: 34, height: 34)
        }
    }
}

/// Up-pointing triangle (caret) marking the playhead direction.
private struct CaretUp: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
#endif
