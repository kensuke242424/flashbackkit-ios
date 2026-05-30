import Foundation

/// 生のコンテキスト（コメント / 端末 / クリップ）を構造化レポートに変換する。
public protocol ReportGenerating: Sendable {
    func generate(
        comment: String,
        device: DeviceInfo,
        clipURL: URL?
    ) async throws -> FlashbackReport
}

/// 仮実装。Claude / OpenAI / Gemini ベースの実装に差し替える。
/// 注意: Claude / OpenAI は入力がテキスト+画像のみ。動画解析は
/// キーフレーム抽出 or 動画ネイティブモデル（Gemini 等）が必要。
public struct StubReportGenerator: ReportGenerating {
    public init() {}

    public func generate(
        comment: String,
        device: DeviceInfo,
        clipURL: URL?
    ) async throws -> FlashbackReport {
        FlashbackReport(
            title: comment.isEmpty ? "Untitled" : comment,
            reproductionSteps: [],
            actualResult: comment,
            suspectedCause: nil,
            comment: comment,
            device: device,
            clipURL: clipURL
        )
    }
}
