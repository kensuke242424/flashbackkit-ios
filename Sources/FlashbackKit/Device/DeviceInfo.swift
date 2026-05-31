import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// レポートに添える端末・アプリのスナップショット。
public struct DeviceInfo: Sendable {
    /// 汎用機種名（`UIDevice.model`。"iPhone" / "iPad" など）。
    public let model: String
    /// ハードウェア識別子（`iPhone16,1` など）。機種を一意に表す。
    /// Simulator では `SIMULATOR_MODEL_IDENTIFIER`（実機相当）を返す。
    public let modelIdentifier: String
    /// マーケティング名（"iPhone 15 Pro" など）。未登録機種では識別子と同値。
    public let modelName: String
    public let systemName: String
    public let systemVersion: String
    public let appVersion: String
    public let buildNumber: String
    public let locale: String

    /// レポート表示用の機種文字列。`iPhone 15 Pro (iPhone16,1)`。
    /// 未登録機種（名前＝識別子）は識別子のみ（`iPhone18,1`）。
    public var displayModel: String {
        modelName == modelIdentifier ? modelIdentifier : "\(modelName) (\(modelIdentifier))"
    }

    /// 現在の端末・アプリ情報を採取する。`UIDevice.current` 参照のため `@MainActor`。
    @MainActor
    public static func current() -> DeviceInfo {
        let bundle = Bundle.main
        #if canImport(UIKit)
        let device = UIDevice.current
        let model = device.model
        let systemName = device.systemName
        let systemVersion = device.systemVersion
        #else
        let model = "unknown"
        let systemName = "unknown"
        let systemVersion = "unknown"
        #endif
        let identifier = machineIdentifier()
        return DeviceInfo(
            model: model,
            modelIdentifier: identifier,
            modelName: DeviceModelNames.name(for: identifier),
            systemName: systemName,
            systemVersion: systemVersion,
            appVersion: bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—",
            buildNumber: bundle.infoDictionary?["CFBundleVersion"] as? String ?? "—",
            locale: Locale.current.identifier
        )
    }

    /// `uname(2)` の `machine` から機種識別子を読む。マーケティング名への変換表は
    /// 新機種で陳腐化するメンテ負債になるため持たず、一意な生の識別子をそのまま使う。
    private static func machineIdentifier() -> String {
        #if targetEnvironment(simulator)
        if let identifier = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"],
           !identifier.isEmpty {
            return identifier
        }
        #endif
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafeBytes(of: &systemInfo.machine) { raw -> String in
            let buffer = raw.bindMemory(to: CChar.self)
            return String(cString: buffer.baseAddress!)
        }
        return machine.isEmpty ? "unknown" : machine
    }
}
