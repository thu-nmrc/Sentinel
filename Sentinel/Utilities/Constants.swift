import Foundation
import CoreGraphics

enum SentinelConstants {
    static let appName = "Sentinel"
    static let defaultScreenshotInterval: TimeInterval = 5.0
    static let defaultClipboardPollInterval: TimeInterval = 1.0
    static let inputAggregationInterval: TimeInterval = 60.0
    static let screenshotJPEGQuality: CGFloat = 0.5
    static let maxScreenshotRetentionDays = 90
    static let maxDatabaseRetentionDays = 365

    enum StoragePaths {
        static var appSupportDirectory: URL {
            let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Sentinel")
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        static var databasePath: URL {
            appSupportDirectory.appendingPathComponent("sentinel.sqlite")
        }

        static var screenshotsDirectory: URL {
            let url = appSupportDirectory.appendingPathComponent("Screenshots")
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
    }

    enum UserDefaultsKeys {
        static let isRecording = "isRecording"
        static let screenshotInterval = "screenshotInterval"
        static let monitoredDirectories = "monitoredDirectories"
        static let launchAtLogin = "launchAtLogin"
        static let screenshotRetentionDays = "screenshotRetentionDays"
        static let databaseRetentionDays = "databaseRetentionDays"
        static let screenshotQuality = "screenshotQuality"
        static let todayRecordingSeconds = "todayRecordingSeconds"
        static let todayRecordingDayKey = "todayRecordingDayKey"
        static let llmEnabled = "llmEnabled"
        static let llmModel = "llmModel"
    }

    enum LLMDefaults {
        static let defaultModel = "gpt-4o-mini"
        static let availableModels: [String] = [
            "gpt-4o-mini",
            "gpt-4o",
            "gpt-4.1-mini",
            "gpt-4.1",
            "o4-mini",
            "o3-mini"
        ]
    }
}
