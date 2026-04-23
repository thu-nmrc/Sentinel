import AppKit
import CoreServices
import Foundation
import GRDB
import os

final class FileWatcherContext {
    let dbQueue: DatabaseQueue
    weak var service: FileWatcherService?

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }
}

private func isNoisePath(_ path: String) -> Bool {
    if path.contains(".DS_Store") { return true }
    if path.contains(".Trash") { return true }
    if path.contains("/.cache/") { return true }
    if path.contains("/node_modules/") { return true }
    if path.contains("/.git/") { return true }
    let lower = path.lowercased()
    if lower.hasSuffix(".tmp") || lower.contains("/.tmp") || lower.hasSuffix(".temp") { return true }
    if path.hasPrefix(NSTemporaryDirectory()) { return true }
    if lower.hasSuffix("~") || lower.contains("~$") { return true }
    return false
}

private func mapFSEventType(_ flags: FSEventStreamEventFlags) -> String? {
    if flags & UInt32(kFSEventStreamEventFlagHistoryDone) != 0 ||
       flags & UInt32(kFSEventStreamEventFlagRootChanged) != 0 { return nil }
    if flags & UInt32(kFSEventStreamEventFlagItemRemoved) != 0 { return "deleted" }
    if flags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0 { return "renamed" }
    if flags & UInt32(kFSEventStreamEventFlagItemCreated) != 0 { return "created" }
    if flags & UInt32(kFSEventStreamEventFlagItemModified) != 0 ||
       flags & UInt32(kFSEventStreamEventFlagItemInodeMetaMod) != 0 ||
       flags & UInt32(kFSEventStreamEventFlagItemXattrMod) != 0 {
        return "modified"
    }
    return nil
}

private let fileWatcherLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sentinel", category: "FileWatcher")

private let fileWatcherFSEventCallback: FSEventStreamCallback = { _, clientCallBackInfo, numEvents, eventPaths, eventFlags, _ in
    guard let clientCallBackInfo, numEvents > 0 else { return }
    let ctx = Unmanaged<FileWatcherContext>.fromOpaque(clientCallBackInfo).takeUnretainedValue()

    let cfArray = unsafeBitCast(eventPaths, to: CFArray.self)
    let count = CFArrayGetCount(cfArray)
    guard count == numEvents else { return }

    var records: [(path: String, eventType: String)] = []
    records.reserveCapacity(numEvents)

    for i in 0..<numEvents {
        let cfPtr = CFArrayGetValueAtIndex(cfArray, i)
        let path = unsafeBitCast(cfPtr, to: CFString.self) as String
        if isNoisePath(path) { continue }

        let rawFlags = eventFlags[i]
        guard let eventType = mapFSEventType(rawFlags) else { continue }
        records.append((path, eventType))
    }

    guard !records.isEmpty else { return }

    DispatchQueue.main.async {
        let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        var inserted = 0
        let now = Date()
        for item in records {
            var record = FileEventRecord(
                id: nil,
                timestamp: now,
                path: item.path,
                eventType: item.eventType,
                appBundleId: bundleId
            )
            do {
                try ctx.dbQueue.write { db in
                    try record.insert(db)
                }
                inserted += 1
            } catch {
                fileWatcherLog.error("Failed to insert file event: \(error.localizedDescription, privacy: .public)")
            }
        }
        guard inserted > 0, let service = ctx.service else { return }
        Task { @MainActor in
            service.applyInsertedFileEventsCount(inserted)
        }
    }
}

@MainActor
final class FileWatcherService: ObservableObject {
    fileprivate static let log = fileWatcherLog

    @Published private(set) var todayFileEvents: Int = 0

    nonisolated init() {}

    private var stream: FSEventStreamRef?
    private var contextObject: FileWatcherContext?
    private var retainedContext: UnsafeMutableRawPointer?

    private static func monitoredDirectoryURLs() -> [URL] {
        let key = SentinelConstants.UserDefaultsKeys.monitoredDirectories
        if let stored = UserDefaults.standard.stringArray(forKey: key), !stored.isEmpty {
            return stored.compactMap { expandedPath in
                let path = (expandedPath as NSString).expandingTildeInPath
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return nil }
                return URL(fileURLWithPath: path, isDirectory: true)
            }
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return ["Desktop", "Documents", "Downloads"].map { home.appendingPathComponent($0, isDirectory: true) }
    }

    func start() {
        stop()

        reloadTodayCountFromDatabase()

        let urls = Self.monitoredDirectoryURLs()
        guard !urls.isEmpty else {
            Self.log.error("No monitored directories configured")
            return
        }

        let pathStrings = urls.map(\.path) as [NSString]
        let pathsToWatch = pathStrings as CFArray

        let ctx = FileWatcherContext(dbQueue: DatabaseManager.shared.dbQueue)
        ctx.service = self
        contextObject = ctx

        let retained = Unmanaged.passRetained(ctx).toOpaque()
        retainedContext = retained

        var streamContext = FSEventStreamContext(
            version: 0,
            info: retained,
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let sinceWhen = FSEventStreamEventId(kFSEventStreamEventIdSinceNow)
        let latency: CFTimeInterval = 2.0
        let createFlags: FSEventStreamCreateFlags = UInt32(kFSEventStreamCreateFlagUseCFTypes)
            | UInt32(kFSEventStreamCreateFlagFileEvents)
            | UInt32(kFSEventStreamCreateFlagNoDefer)

        guard let newStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            fileWatcherFSEventCallback,
            &streamContext,
            pathsToWatch,
            sinceWhen,
            latency,
            createFlags
        ) else {
            Self.log.error("FSEventStreamCreate failed")
            releaseRetainedContext()
            contextObject = nil
            return
        }

        stream = newStream
        FSEventStreamSetDispatchQueue(newStream, DispatchQueue.main)
        if !FSEventStreamStart(newStream) {
            Self.log.error("FSEventStreamStart failed")
            FSEventStreamInvalidate(newStream)
            FSEventStreamRelease(newStream)
            stream = nil
            releaseRetainedContext()
            contextObject = nil
        }
    }

    func stop() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
        contextObject = nil
        releaseRetainedContext()
    }

    private func releaseRetainedContext() {
        if let retainedContext {
            Unmanaged<FileWatcherContext>.fromOpaque(retainedContext).release()
            self.retainedContext = nil
        }
    }

    fileprivate func applyInsertedFileEventsCount(_ count: Int) {
        todayFileEvents += count
    }

    private func reloadTodayCountFromDatabase() {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        do {
            let count = try DatabaseManager.shared.dbQueue.read { db -> Int in
                try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM \(FileEventRecord.databaseTableName) WHERE timestamp >= ?",
                    arguments: [startOfDay]
                ) ?? 0
            }
            todayFileEvents = count
        } catch {
            Self.log.error("Failed to load today file event count: \(error.localizedDescription, privacy: .public)")
        }
    }
}
