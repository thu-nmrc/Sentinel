import AppKit
import Combine
import Foundation
import GRDB
import os
import ScreenCaptureKit

@MainActor
final class ScreenCaptureService: ObservableObject {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sentinel", category: "ScreenCapture")

    @Published private(set) var screenshotCount: Int = 0

    private var timer: Timer?
    private var isCapturing = false

    nonisolated init() {}

    func start() {
        stop()
        refreshTodayCount()
        let interval = Self.intervalFromUserDefaults()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.performCapture()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func captureNow() {
        Task {
            await performCapture()
        }
    }

    private static func intervalFromUserDefaults() -> TimeInterval {
        let v = UserDefaults.standard.double(forKey: SentinelConstants.UserDefaultsKeys.screenshotInterval)
        return v > 0 ? v : SentinelConstants.defaultScreenshotInterval
    }

    private static func jpegQualityFromUserDefaults() -> CGFloat {
        let key = SentinelConstants.UserDefaultsKeys.screenshotQuality
        if UserDefaults.standard.object(forKey: key) != nil {
            return CGFloat(UserDefaults.standard.double(forKey: key))
        }
        return 0.5
    }

    private func refreshTodayCount() {
        let start = Calendar.current.startOfDay(for: Date())
        do {
            let count = try DatabaseManager.shared.dbQueue.read { db in
                try ScreenshotRecord.filter(ScreenshotRecord.Columns.timestamp >= start).fetchCount(db)
            }
            screenshotCount = count
        } catch {
            Self.log.error("Failed to load today's screenshot count: \(String(describing: error), privacy: .public)")
        }
    }

    private func performCapture() async {
        guard !isCapturing else { return }
        guard CGPreflightScreenCaptureAccess() else {
            Self.log.info("Screen recording permission not granted, skipping capture")
            return
        }
        isCapturing = true
        defer { isCapturing = false }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else {
                Self.log.error("No shareable displays available")
                return
            }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = display.width
            config.height = display.height
            config.captureResolution = .nominal
            let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            let quality = Self.jpegQualityFromUserDefaults()
            guard let jpegData = nsImage.jpegData(quality: quality) else {
                Self.log.error("JPEG encoding failed")
                return
            }

            let timestamp = Date()
            let nameFormatter = DateFormatter()
            nameFormatter.locale = Locale(identifier: "en_US_POSIX")
            nameFormatter.timeZone = TimeZone.current
            nameFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let filename = nameFormatter.string(from: timestamp) + ".jpg"
            let dir = SentinelConstants.StoragePaths.screenshotsDirectory
            let fileURL = dir.appendingPathComponent(filename)

            try jpegData.write(to: fileURL, options: .atomic)

            let front = NSWorkspace.shared.frontmostApplication
            let appLabel = front?.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let bundleFallback = front?.bundleIdentifier ?? ""
            let activeApp = appLabel.isEmpty ? (bundleFallback.isEmpty ? "unknown" : bundleFallback) : appLabel
            let windowTitle = WindowTrackingService.getFocusedWindowTitle()
            let displayId = Int(display.displayID)

            var record = ScreenshotRecord(
                id: nil,
                timestamp: timestamp,
                filePath: fileURL.path,
                activeApp: activeApp,
                windowTitle: windowTitle,
                displayId: displayId,
                ocrText: nil
            )

            try await DatabaseManager.shared.dbQueue.write { db in
                try record.insert(db)
            }

            refreshTodayCount()
        } catch {
            Self.log.error("Capture failed: \(String(describing: error), privacy: .public)")
        }
    }
}
