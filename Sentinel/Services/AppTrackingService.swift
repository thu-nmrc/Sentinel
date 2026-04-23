import AppKit
import Combine
import Foundation
import GRDB
import os

@MainActor
final class AppTrackingService: ObservableObject {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sentinel", category: "AppTracking")
    @Published private(set) var currentApp: String = ""
    @Published private(set) var currentBundleId: String = ""
    @Published private(set) var currentWindowTitle: String = ""

    let windowTracking: WindowTrackingService
    var ocrService: OCRService?

    nonisolated init(windowTracking: WindowTrackingService = WindowTrackingService()) {
        self.windowTracking = windowTracking
    }

    private var currentUsageRecord: AppUsageRecord?
    private var activationObserver: NSObjectProtocol?
    private var deactivationObserver: NSObjectProtocol?

    func start() {
        stop()
        windowTracking.appTrackingService = self
        windowTracking.start()

        let center = NSWorkspace.shared.notificationCenter
        activationObserver = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleApplicationActivated(notification)
            }
        }
        deactivationObserver = center.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleApplicationDeactivated()
            }
        }

        if let app = NSWorkspace.shared.frontmostApplication {
            switchToApplication(app)
        }
    }

    func stop() {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        if let deactivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(deactivationObserver)
        }
        activationObserver = nil
        deactivationObserver = nil

        windowTracking.stop()
        windowTracking.appTrackingService = nil

        persistCurrentSession()
        currentUsageRecord = nil
    }

    func updateWindowTitleFromTracker(_ title: String) {
        let normalized = title
        if normalized != currentWindowTitle {
            currentWindowTitle = normalized
            currentUsageRecord?.windowTitle = normalized.isEmpty ? nil : normalized
        }
    }

    private func handleApplicationActivated(_ notification: Notification) {
        guard
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        else {
            return
        }
        switchToApplication(app)
    }

    private func handleApplicationDeactivated() {}

    private func switchToApplication(_ app: NSRunningApplication) {
        let bundleId = app.bundleIdentifier ?? ""
        let name = app.localizedName ?? bundleId

        if bundleId == currentBundleId, !bundleId.isEmpty {
            return
        }

        let previousApp = currentApp
        let previousWindowTitle = currentWindowTitle

        if !previousApp.isEmpty {
            Task { @MainActor [ocrService] in
                await ocrService?.captureAndRecognize(
                    activeApp: previousApp,
                    windowTitle: previousWindowTitle.isEmpty ? nil : previousWindowTitle
                )
            }
        }

        persistCurrentSession()

        currentBundleId = bundleId
        currentApp = name
        let initialTitle = WindowTrackingService.getFocusedWindowTitle() ?? windowTracking.currentWindowTitle
        currentWindowTitle = initialTitle

        currentUsageRecord = AppUsageRecord(
            id: nil,
            bundleId: bundleId,
            appName: name,
            windowTitle: initialTitle.isEmpty ? nil : initialTitle,
            startTime: Date(),
            endTime: nil,
            duration: 0
        )
    }

    private func persistCurrentSession() {
        guard var record = currentUsageRecord else { return }
        let end = Date()
        record.endTime = end
        record.duration = end.timeIntervalSince(record.startTime)
        do {
            try DatabaseManager.shared.dbQueue.write { db in
                try record.insert(db)
            }
        } catch {
            Self.log.error("Failed to persist app usage: \(String(describing: error))")
        }
    }
}
