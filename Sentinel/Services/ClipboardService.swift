import AppKit
import Foundation
import GRDB
import os

@MainActor
final class ClipboardService: ObservableObject {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sentinel", category: "Clipboard")

    @Published private(set) var todayClipboardCount: Int = 0
    @Published private(set) var lastClipboardText: String?

    nonisolated init() {}

    private var pollTimer: Timer?
    private var lastChangeCount: Int = -1

    func start() {
        stop()

        reloadTodayCountFromDatabase()

        let pasteboard = NSPasteboard.general
        lastChangeCount = pasteboard.changeCount

        let interval = SentinelConstants.defaultClipboardPollInterval
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollPasteboard()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        lastChangeCount = -1
    }

    private func pollPasteboard() {
        let pasteboard = NSPasteboard.general
        let current = pasteboard.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current

        let sourceApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            let preview = text.count > 200 ? String(text.prefix(200)) : text
            lastClipboardText = preview
            persistRecord(
                contentType: "text",
                textContent: text,
                sourceApp: sourceApp
            )
            return
        }

        if pasteboard.data(forType: .tiff) != nil || pasteboard.data(forType: .png) != nil {
            lastClipboardText = nil
            persistRecord(contentType: "image", textContent: nil, sourceApp: sourceApp)
            return
        }

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            lastClipboardText = nil
            persistRecord(contentType: "file", textContent: nil, sourceApp: sourceApp)
            return
        }
    }

    private func persistRecord(contentType: String, textContent: String?, sourceApp: String?) {
        var record = ClipboardRecord( // var: insert(db) is mutating
            id: nil,
            timestamp: Date(),
            contentType: contentType,
            textContent: textContent,
            sourceApp: sourceApp
        )
        do {
            try DatabaseManager.shared.dbQueue.write { db in
                try record.insert(db)
            }
            todayClipboardCount += 1
        } catch {
            Self.log.error("Failed to insert clipboard record: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func reloadTodayCountFromDatabase() {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        do {
            let count = try DatabaseManager.shared.dbQueue.read { db -> Int in
                try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM \(ClipboardRecord.databaseTableName) WHERE timestamp >= ?",
                    arguments: [startOfDay]
                ) ?? 0
            }
            todayClipboardCount = count
        } catch {
            Self.log.error("Failed to load today clipboard count: \(error.localizedDescription, privacy: .public)")
        }
    }
}
