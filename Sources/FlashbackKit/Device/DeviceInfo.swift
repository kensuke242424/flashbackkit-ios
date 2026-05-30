import Foundation
#if canImport(UIKit)
import UIKit
#endif

public struct DeviceInfo: Sendable {
    public let model: String
    public let systemName: String
    public let systemVersion: String
    public let appVersion: String
    public let buildNumber: String
    public let locale: String

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
        return DeviceInfo(
            model: model,
            systemName: systemName,
            systemVersion: systemVersion,
            appVersion: bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—",
            buildNumber: bundle.infoDictionary?["CFBundleVersion"] as? String ?? "—",
            locale: Locale.current.identifier
        )
    }
}
