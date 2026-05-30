import Foundation

/// Flashback から生成される構造化バグレポート。
public struct FlashbackReport: Sendable {
    public var title: String
    public var reproductionSteps: [String]
    public var actualResult: String
    public var suspectedCause: String?
    public var comment: String
    public var device: DeviceInfo
    public var clipURL: URL?
}
