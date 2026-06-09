import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Device and app snapshot attached to a report.
public struct DeviceInfo: Sendable {
    /// Generic model name (`UIDevice.model`; e.g. "iPhone" / "iPad").
    public let model: String
    /// Hardware model identifier (e.g. `iPhone16,1`), uniquely identifying the model.
    /// On Simulator, returns `SIMULATOR_MODEL_IDENTIFIER` (the emulated device).
    public let modelIdentifier: String
    /// Marketing name (e.g. "iPhone 15 Pro"). Equals the identifier for unknown models.
    public let modelName: String
    public let systemName: String
    public let systemVersion: String
    public let appVersion: String
    public let buildNumber: String
    public let locale: String

    /// Model string for report display, e.g. `iPhone 15 Pro (iPhone16,1)`.
    /// For unknown models (name == identifier), the identifier alone (e.g. `iPhone18,1`).
    public var displayModel: String {
        modelName == modelIdentifier ? modelIdentifier : "\(modelName) (\(modelIdentifier))"
    }

    /// Collects current device and app info. `@MainActor` because it reads `UIDevice.current`.
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

    /// Reads the model identifier from `uname(2)`'s `machine`.
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
