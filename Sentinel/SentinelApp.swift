import AppKit
import SwiftUI

enum SentinelWindowID: String {
    case dashboard
    case settings
}

@main
struct SentinelApp: App {
    @StateObject private var windowTracking: WindowTrackingService
    @StateObject private var appTracking: AppTrackingService
    @StateObject private var permissionManager = PermissionManager()
    @StateObject private var screenCapture: ScreenCaptureService
    @StateObject private var inputMonitor: InputMonitorService
    @StateObject private var fileWatcher: FileWatcherService
    @StateObject private var clipboard: ClipboardService
    @StateObject private var analytics = AnalyticsEngine()
    @StateObject private var ocrService: OCRService

    init() {
        let wt = WindowTrackingService()
        let at = AppTrackingService(windowTracking: wt)
        let sc = ScreenCaptureService()
        let im = InputMonitorService()
        let fw = FileWatcherService()
        let cb = ClipboardService()
        let ocr = OCRService()

        _windowTracking = StateObject(wrappedValue: wt)
        _appTracking = StateObject(wrappedValue: at)
        _screenCapture = StateObject(wrappedValue: sc)
        _inputMonitor = StateObject(wrappedValue: im)
        _fileWatcher = StateObject(wrappedValue: fw)
        _clipboard = StateObject(wrappedValue: cb)
        _ocrService = StateObject(wrappedValue: ocr)

        _ = DatabaseManager.shared

        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "sentinel.hasLaunchedBefore") {
            defaults.set(true, forKey: SentinelConstants.UserDefaultsKeys.isRecording)
            defaults.set(true, forKey: "sentinel.hasLaunchedBefore")
        }

        if defaults.bool(forKey: SentinelConstants.UserDefaultsKeys.isRecording) {
            DispatchQueue.main.async {
                Task { @MainActor in
                    at.ocrService = ocr
                    at.start()
                    sc.start()
                    im.start()
                    fw.start()
                    cb.start()
                }
            }
        }
    }

    var body: some Scene {
        MenuBarExtra("Sentinel", systemImage: "eye.fill") {
            MenuBarView()
                .environmentObject(appTracking)
                .environmentObject(permissionManager)
                .environmentObject(screenCapture)
                .environmentObject(inputMonitor)
                .environmentObject(fileWatcher)
                .environmentObject(clipboard)
                .frame(minWidth: 280)
        }
        .menuBarExtraStyle(.window)

        WindowGroup(id: SentinelWindowID.dashboard.rawValue) {
            MainWindow()
                .environmentObject(appTracking)
                .environmentObject(analytics)
                .environmentObject(screenCapture)
                .environmentObject(inputMonitor)
                .environmentObject(fileWatcher)
                .environmentObject(clipboard)
        }
        .defaultSize(width: 1100, height: 720)
        .handlesExternalEvents(matching: [SentinelWindowID.dashboard.rawValue])

        WindowGroup(id: SentinelWindowID.settings.rawValue) {
            SettingsView()
                .environmentObject(permissionManager)
        }
        .defaultSize(width: 640, height: 520)
        .handlesExternalEvents(matching: [SentinelWindowID.settings.rawValue])
    }
}
