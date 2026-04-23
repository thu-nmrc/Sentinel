import ApplicationServices
import AppKit
import Combine
import Foundation

@MainActor
final class WindowTrackingService: ObservableObject {
    @Published private(set) var currentWindowTitle: String = ""

    weak var appTrackingService: AppTrackingService?

    private var pollTimer: Timer?
    private var lastPolledTitle: String?

    nonisolated init() {}

    func start() {
        stop()
        lastPolledTitle = nil
        tick()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        lastPolledTitle = nil
    }

    private func tick() {
        let title = Self.getFocusedWindowTitle() ?? ""
        if title != lastPolledTitle {
            lastPolledTitle = title
            currentWindowTitle = title
            appTrackingService?.updateWindowTitleFromTracker(title)
        }
    }

    static func getFocusedWindowTitle() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedAppObject: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                systemWide,
                kAXFocusedApplicationAttribute as CFString,
                &focusedAppObject
            ) == .success,
            let focusedAppObject,
            CFGetTypeID(focusedAppObject) == AXUIElementGetTypeID()
        else {
            return nil
        }
        let appElement = focusedAppObject as! AXUIElement

        var focusedWindowObject: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                appElement,
                kAXFocusedWindowAttribute as CFString,
                &focusedWindowObject
            ) == .success,
            let focusedWindowObject,
            CFGetTypeID(focusedWindowObject) == AXUIElementGetTypeID()
        else {
            return nil
        }
        let windowElement = focusedWindowObject as! AXUIElement

        var titleObject: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &titleObject) == .success,
            let titleObject,
            CFGetTypeID(titleObject) == CFStringGetTypeID()
        else {
            return nil
        }
        return titleObject as? String
    }
}
