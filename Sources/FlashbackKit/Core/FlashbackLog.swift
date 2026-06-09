import Foundation
import os

/// Shared logger for FlashbackKit.
///
/// Based on `os.Logger`. Filter by `subsystem:FlashbackKit` in Console.app. In Release
/// builds, `.debug` / `.info` levels are suppressed by default. Per the dependency-free
/// policy, nothing beyond the standard `os` is used.
enum FlashbackLog {
    /// Report generation and delivery.
    static let report = Logger(subsystem: "FlashbackKit", category: "report")

    /// Lifecycle (start / stop / triggers).
    static let lifecycle = Logger(subsystem: "FlashbackKit", category: "lifecycle")
}
