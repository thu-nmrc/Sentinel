import AppKit
import ApplicationServices
import Carbon
import Combine
import Foundation
import GRDB
import os

struct BufferedKeystroke {
    let timestamp: Date
    let characters: String
    let keyCode: Int
    let modifiers: Int
}

final class InputCounters {
    let lock = NSLock()
    var keystrokes: Int = 0
    var mouseClicks: Int = 0
    var scrollEvents: Int = 0
    var mouseTravelDistance: Double = 0
    var lastMouseLocation: CGPoint?
    var eventTapMachPort: CFMachPort?
    var keystrokeBuffer: [BufferedKeystroke] = []
}

@MainActor
final class InputMonitorService: ObservableObject {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sentinel", category: "InputMonitor")

    @Published private(set) var currentMinuteKeystrokes: Int = 0
    @Published private(set) var currentMinuteClicks: Int = 0
    @Published private(set) var todayTotalKeystrokes: Int = 0
    @Published private(set) var todayTotalClicks: Int = 0

    nonisolated init() {}

    private let counters = InputCounters()
    private var countersUserInfo: UnsafeMutableRawPointer?
    private var eventTapPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var aggregationTimer: Timer?
    private var uiSyncTimer: Timer?
    private var keystrokeFlushTimer: Timer?
    private var imeTextCaptureTimer: Timer?

    private var currentMinuteStart: Date?
    private var lastCapturedText: String = ""
    private var lastCapturedAppPid: pid_t = 0

    func start() {
        stop()

        loadTodayTotalsFromDatabase()

        counters.eventTapMachPort = nil
        countersUserInfo = Unmanaged.passUnretained(counters).toOpaque()

        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << CGEventType.scrollWheel.rawValue)
            | (1 << CGEventType.mouseMoved.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: inputEventTapCallback,
            userInfo: countersUserInfo
        ) else {
            Self.log.error("CGEvent tapCreate failed (Input Monitoring permission may be denied)")
            countersUserInfo = nil
            return
        }

        counters.eventTapMachPort = tap
        eventTapPort = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)

        currentMinuteStart = Date()

        let agg = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.flushMinuteToDatabase(advanceMinuteStart: true)
            }
        }
        RunLoop.main.add(agg, forMode: .common)
        aggregationTimer = agg

        let ui = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncPublishedMinuteTotals()
            }
        }
        RunLoop.main.add(ui, forMode: .common)
        uiSyncTimer = ui

        let ksFlush = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.flushKeystrokeBuffer()
            }
        }
        RunLoop.main.add(ksFlush, forMode: .common)
        keystrokeFlushTimer = ksFlush

        let imeCap = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.captureIMECommittedText()
            }
        }
        RunLoop.main.add(imeCap, forMode: .common)
        imeTextCaptureTimer = imeCap

        syncPublishedMinuteTotals()
    }

    func stop() {
        aggregationTimer?.invalidate()
        aggregationTimer = nil
        uiSyncTimer?.invalidate()
        uiSyncTimer = nil
        keystrokeFlushTimer?.invalidate()
        keystrokeFlushTimer = nil
        imeTextCaptureTimer?.invalidate()
        imeTextCaptureTimer = nil

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil

        if let eventTapPort {
            CGEvent.tapEnable(tap: eventTapPort, enable: false)
            CFMachPortInvalidate(eventTapPort)
        }
        eventTapPort = nil
        counters.eventTapMachPort = nil

        countersUserInfo = nil

        flushMinuteToDatabase(advanceMinuteStart: false)
        flushKeystrokeBuffer()
        currentMinuteStart = nil

        currentMinuteKeystrokes = 0
        currentMinuteClicks = 0
    }

    // MARK: - IME Committed Text Capture

    static func isCurrentInputSourceCJK() -> Bool {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return false }
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return false }
        let sourceID = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
        let cjkKeywords = ["Chinese", "Pinyin", "Wubi", "Cangjie", "Japanese", "Korean",
                           "Shuangpin", "Handwriting", "SCIM", "RIME", "Sogou", "Baidu",
                           "QIM", "SquirrelInput", "fcitx", "ibus"]
        for kw in cjkKeywords where sourceID.localizedCaseInsensitiveContains(kw) {
            return true
        }
        return false
    }

    private func captureIMECommittedText() {
        guard Self.isCurrentInputSourceCJK() else {
            lastCapturedText = ""
            lastCapturedAppPid = 0
            return
        }

        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
        let pid = frontApp.processIdentifier

        if pid != lastCapturedAppPid {
            lastCapturedText = ""
            lastCapturedAppPid = pid
        }

        guard let newText = Self.readFocusedElementText(pid: pid) else { return }

        if !lastCapturedText.isEmpty && newText.count > lastCapturedText.count {
            let delta: String
            if newText.hasPrefix(lastCapturedText) {
                delta = String(newText.dropFirst(lastCapturedText.count))
            } else if newText.hasSuffix(lastCapturedText) {
                delta = String(newText.dropLast(lastCapturedText.count))
            } else {
                let commonPrefix = newText.commonPrefix(with: lastCapturedText)
                delta = String(newText.dropFirst(commonPrefix.count))
            }

            let cjkChars = delta.filter { $0.isCJK }
            if !cjkChars.isEmpty {
                saveIMEText(String(cjkChars), app: frontApp)
            }
        }

        lastCapturedText = newText
    }

    private static func readFocusedElementText(pid: pid_t) -> String? {
        let appElement = AXUIElementCreateApplication(pid)

        var focusedObject: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedObject) == .success,
              let focusedObject else { return nil }
        let focused = focusedObject as! AXUIElement

        var selectedObject: CFTypeRef?
        if AXUIElementCopyAttributeValue(focused, kAXSelectedTextAttribute as CFString, &selectedObject) == .success,
           let sel = selectedObject as? String, !sel.isEmpty {
            return nil
        }

        var valueObject: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused, kAXValueAttribute as CFString, &valueObject) == .success,
              let text = valueObject as? String else { return nil }

        let trimmed = text.suffix(500)
        return String(trimmed)
    }

    private func saveIMEText(_ text: String, app: NSRunningApplication) {
        let appName = app.localizedName ?? app.bundleIdentifier ?? "unknown"
        let windowTitle = WindowTrackingService.getFocusedWindowTitle()
        let now = Date()

        do {
            try DatabaseManager.shared.dbQueue.write { db in
                var record = KeystrokeRecord(
                    id: nil,
                    timestamp: now,
                    characters: text,
                    keyCode: 0,
                    modifiers: 0,
                    activeApp: appName,
                    windowTitle: windowTitle
                )
                try record.insert(db)
            }
        } catch {
            Self.log.error("Failed to save IME text: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Existing Logic

    private func loadTodayTotalsFromDatabase() {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        do {
            let sums = try DatabaseManager.shared.dbQueue.read { db -> (Int, Int) in
                let sql = """
                    SELECT IFNULL(SUM(keystrokeCount), 0) AS ks, IFNULL(SUM(mouseClickCount), 0) AS mc
                    FROM \(InputActivityRecord.databaseTableName)
                    WHERE minuteTimestamp >= ?
                    """
                let row = try Row.fetchOne(db, sql: sql, arguments: [startOfDay])
                let ks = row?["ks"] as? Int64 ?? 0
                let mc = row?["mc"] as? Int64 ?? 0
                return (Int(ks), Int(mc))
            }
            todayTotalKeystrokes = sums.0
            todayTotalClicks = sums.1
        } catch {
            Self.log.error("Failed to load today input totals: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func syncPublishedMinuteTotals() {
        counters.lock.lock()
        let ks = counters.keystrokes
        let cl = counters.mouseClicks
        counters.lock.unlock()
        currentMinuteKeystrokes = ks
        currentMinuteClicks = cl
    }

    private func flushMinuteToDatabase(advanceMinuteStart: Bool) {
        counters.lock.lock()
        let ks = counters.keystrokes
        let cl = counters.mouseClicks
        let sc = counters.scrollEvents
        let dist = counters.mouseTravelDistance
        counters.keystrokes = 0
        counters.mouseClicks = 0
        counters.scrollEvents = 0
        counters.mouseTravelDistance = 0
        counters.lastMouseLocation = nil
        counters.lock.unlock()

        currentMinuteKeystrokes = 0
        currentMinuteClicks = 0

        let minuteKey = currentMinuteStart ?? Calendar.current.startOfDay(for: Date())
        if advanceMinuteStart {
            currentMinuteStart = Date()
        }

        guard ks > 0 || cl > 0 || sc > 0 || dist > 0 else { return }

        var record = InputActivityRecord(
            id: nil,
            minuteTimestamp: minuteKey,
            keystrokeCount: ks,
            mouseClickCount: cl,
            mouseScrollCount: sc,
            mouseTravelDistance: dist
        )

        do {
            try DatabaseManager.shared.dbQueue.write { db in
                try record.insert(db)
            }
            todayTotalKeystrokes += ks
            todayTotalClicks += cl
        } catch {
            Self.log.error("Failed to save input activity: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func flushKeystrokeBuffer() {
        counters.lock.lock()
        let batch = counters.keystrokeBuffer
        counters.keystrokeBuffer.removeAll()
        counters.lock.unlock()

        guard !batch.isEmpty else { return }

        let isCJK = Self.isCurrentInputSourceCJK()
        let frontApp = NSWorkspace.shared.frontmostApplication
        let appName = frontApp?.localizedName ?? frontApp?.bundleIdentifier ?? "unknown"
        let windowTitle = WindowTrackingService.getFocusedWindowTitle()

        let filtered: [BufferedKeystroke]
        if isCJK {
            filtered = batch.filter { ks in
                ks.characters.contains(where: { $0.isCJK || $0.isPunctuation }) ||
                ks.modifiers != 0 ||
                ks.characters.isEmpty
            }
        } else {
            filtered = batch
        }

        guard !filtered.isEmpty else { return }

        do {
            try DatabaseManager.shared.dbQueue.write { db in
                for ks in filtered {
                    var record = KeystrokeRecord(
                        id: nil,
                        timestamp: ks.timestamp,
                        characters: ks.characters,
                        keyCode: ks.keyCode,
                        modifiers: ks.modifiers,
                        activeApp: appName,
                        windowTitle: windowTitle
                    )
                    try record.insert(db)
                }
            }
        } catch {
            Self.log.error("Failed to save keystrokes: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - CJK Character Detection

extension Character {
    var isCJK: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        let v = scalar.value
        return (0x4E00...0x9FFF).contains(v) ||    // CJK Unified
               (0x3400...0x4DBF).contains(v) ||    // CJK Extension A
               (0x20000...0x2A6DF).contains(v) ||  // CJK Extension B
               (0x2A700...0x2B73F).contains(v) ||  // CJK Extension C
               (0x2B740...0x2B81F).contains(v) ||  // CJK Extension D
               (0xF900...0xFAFF).contains(v) ||    // CJK Compatibility
               (0x2F800...0x2FA1F).contains(v) ||  // CJK Compatibility Supplement
               (0x3000...0x303F).contains(v) ||    // CJK Symbols & Punctuation
               (0x3040...0x309F).contains(v) ||    // Hiragana
               (0x30A0...0x30FF).contains(v) ||    // Katakana
               (0xAC00...0xD7AF).contains(v) ||    // Hangul
               (0xFF00...0xFFEF).contains(v)       // Fullwidth Forms
    }
}

// MARK: - CGEvent Tap Callback

private func inputEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    _ = proxy
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let counters = Unmanaged<InputCounters>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let port = counters.eventTapMachPort {
            CGEvent.tapEnable(tap: port, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }

    switch type {
    case .keyDown:
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        var modifiers: Int = 0
        if flags.contains(.maskShift) { modifiers |= 1 }
        if flags.contains(.maskControl) { modifiers |= 2 }
        if flags.contains(.maskAlternate) { modifiers |= 4 }
        if flags.contains(.maskCommand) { modifiers |= 8 }

        var unicodeLength: Int = 0
        var unicodeChars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(
            maxStringLength: 4,
            actualStringLength: &unicodeLength,
            unicodeString: &unicodeChars
        )
        let chars: String
        if unicodeLength > 0 {
            chars = String(utf16CodeUnits: Array(unicodeChars.prefix(unicodeLength)), count: unicodeLength)
        } else {
            chars = ""
        }

        let buffered = BufferedKeystroke(
            timestamp: Date(),
            characters: chars,
            keyCode: Int(keyCode),
            modifiers: modifiers
        )

        counters.lock.lock()
        counters.keystrokes += 1
        counters.keystrokeBuffer.append(buffered)
        counters.lock.unlock()

    case .leftMouseDown, .rightMouseDown:
        counters.lock.lock()
        counters.mouseClicks += 1
        counters.lock.unlock()

    case .scrollWheel:
        counters.lock.lock()
        counters.scrollEvents += 1
        counters.lock.unlock()

    case .mouseMoved:
        let dx = event.getDoubleValueField(.mouseEventDeltaX)
        let dy = event.getDoubleValueField(.mouseEventDeltaY)
        let segment = hypot(dx, dy)
        counters.lock.lock()
        counters.mouseTravelDistance += segment
        counters.lock.unlock()

    default:
        break
    }

    return Unmanaged.passUnretained(event)
}
