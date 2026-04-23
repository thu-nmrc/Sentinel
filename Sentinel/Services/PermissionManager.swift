import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import Foundation
import IOKit.hid

final class PermissionManager: ObservableObject {
    @Published private(set) var hasScreenRecording = false
    @Published private(set) var hasAccessibility = false
    @Published private(set) var hasFullDiskAccess = false
    @Published private(set) var hasInputMonitoring = false

    private var recheckTimer: Timer?

    init() {}

    func checkAllPermissions() {
        hasScreenRecording = checkScreenRecordingPermission()
        hasAccessibility = AXIsProcessTrusted()
        hasFullDiskAccess = checkFullDiskAccessPermission()
        hasInputMonitoring = checkInputMonitoringPermission()
    }

    func startPeriodicRecheck(interval: TimeInterval = 5) {
        stopPeriodicRecheck()
        checkAllPermissions()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.checkAllPermissions()
        }
        RunLoop.main.add(timer, forMode: .common)
        recheckTimer = timer
    }

    func stopPeriodicRecheck() {
        recheckTimer?.invalidate()
        recheckTimer = nil
    }

    @discardableResult
    func requestScreenRecording() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    func requestAccessibility() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func openFullDiskAccessSettings() {
        openSystemPreferences(identifier: "Privacy_AllFiles")
    }

    func openInputMonitoringSettings() {
        openSystemPreferences(identifier: "Privacy_ListenEvent")
    }

    func openScreenRecordingSettings() {
        openSystemPreferences(identifier: "Privacy_ScreenCapture")
    }

    func openAccessibilitySettings() {
        openSystemPreferences(identifier: "Privacy_Accessibility")
    }

    func openSystemPreferences(identifier: String) {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?\(identifier)"
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    private func checkScreenRecordingPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    private func checkFullDiskAccessPermission() -> Bool {
        let mailPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mail")
            .path
        guard FileManager.default.fileExists(atPath: mailPath) else {
            return false
        }
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: mailPath)
            return true
        } catch {
            return false
        }
    }

    private func checkInputMonitoringPermission() -> Bool {
        if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted {
            return true
        }
        return canCreatePassiveEventTap()
    }

    private func canCreatePassiveEventTap() -> Bool {
        let callback: CGEventTapCallBack = { _, _, event, _ in
            Unmanaged.passUnretained(event)
        }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: nil
        ) else {
            return false
        }
        CFMachPortInvalidate(tap)
        return true
    }
}
