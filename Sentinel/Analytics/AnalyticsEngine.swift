import Foundation
import GRDB
import os

struct SearchResults {
    let appUsageResults: [AppUsageRecord]
    let clipboardResults: [ClipboardRecord]
    let fileEventResults: [FileEventRecord]
    let ocrResults: [ScreenshotRecord]
    let keystrokeResults: [KeystrokeRecord]
}

struct KeystrokeGroup: Identifiable {
    let id = UUID()
    let startTime: Date
    let endTime: Date
    let activeApp: String
    let windowTitle: String?
    let text: String
    let keystrokeCount: Int
}

@MainActor
final class AnalyticsEngine: ObservableObject {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sentinel", category: "Analytics")

    nonisolated init() {}

    private let calendar = Calendar.current

    private func dayBounds(for date: Date) -> (start: Date, end: Date) {
        let start = date.startOfDay
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return (start, end)
    }

    private func logReadError(_ method: String, _ error: Error) {
        Self.log.error("\(method, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }

    // MARK: - Existing Stats

    func totalRecordingTime(for date: Date) throws -> TimeInterval {
        let (dayStart, dayEnd) = dayBounds(for: date)
        do {
            return try DatabaseManager.shared.dbQueue.read { db in
                try Double.fetchOne(
                    db,
                    sql: """
                    SELECT IFNULL(SUM(duration), 0) FROM \(AppUsageRecord.databaseTableName)
                    WHERE startTime >= ? AND startTime < ?
                    """,
                    arguments: [dayStart, dayEnd]
                ) ?? 0
            }
        } catch {
            logReadError("totalRecordingTime", error)
            throw error
        }
    }

    func distinctAppsCount(for date: Date) throws -> Int {
        let (dayStart, dayEnd) = dayBounds(for: date)
        do {
            return try DatabaseManager.shared.dbQueue.read { db in
                try Int.fetchOne(
                    db,
                    sql: """
                    SELECT COUNT(DISTINCT bundleId) FROM \(AppUsageRecord.databaseTableName)
                    WHERE startTime >= ? AND startTime < ?
                    """,
                    arguments: [dayStart, dayEnd]
                ) ?? 0
            }
        } catch {
            logReadError("distinctAppsCount", error)
            throw error
        }
    }

    func totalKeystrokes(for date: Date) throws -> Int {
        let (dayStart, dayEnd) = dayBounds(for: date)
        do {
            return try DatabaseManager.shared.dbQueue.read { db in
                try Int.fetchOne(
                    db,
                    sql: """
                    SELECT IFNULL(SUM(keystrokeCount), 0) FROM \(InputActivityRecord.databaseTableName)
                    WHERE minuteTimestamp >= ? AND minuteTimestamp < ?
                    """,
                    arguments: [dayStart, dayEnd]
                ) ?? 0
            }
        } catch {
            logReadError("totalKeystrokes", error)
            throw error
        }
    }

    func totalMouseClicks(for date: Date) throws -> Int {
        let (dayStart, dayEnd) = dayBounds(for: date)
        do {
            return try DatabaseManager.shared.dbQueue.read { db in
                try Int.fetchOne(
                    db,
                    sql: """
                    SELECT IFNULL(SUM(mouseClickCount), 0) FROM \(InputActivityRecord.databaseTableName)
                    WHERE minuteTimestamp >= ? AND minuteTimestamp < ?
                    """,
                    arguments: [dayStart, dayEnd]
                ) ?? 0
            }
        } catch {
            logReadError("totalMouseClicks", error)
            throw error
        }
    }

    func screenshotCount(for date: Date) throws -> Int {
        let (dayStart, dayEnd) = dayBounds(for: date)
        do {
            return try DatabaseManager.shared.dbQueue.read { db in
                try ScreenshotRecord
                    .filter(ScreenshotRecord.Columns.timestamp >= dayStart && ScreenshotRecord.Columns.timestamp < dayEnd)
                    .fetchCount(db)
            }
        } catch {
            logReadError("screenshotCount", error)
            throw error
        }
    }

    func fileEventsCount(for date: Date) throws -> Int {
        let (dayStart, dayEnd) = dayBounds(for: date)
        do {
            return try DatabaseManager.shared.dbQueue.read { db in
                try FileEventRecord
                    .filter(FileEventRecord.Columns.timestamp >= dayStart && FileEventRecord.Columns.timestamp < dayEnd)
                    .fetchCount(db)
            }
        } catch {
            logReadError("fileEventsCount", error)
            throw error
        }
    }

    func ocrCount(for date: Date) throws -> Int {
        let (dayStart, dayEnd) = dayBounds(for: date)
        do {
            return try DatabaseManager.shared.dbQueue.read { db in
                try Int.fetchOne(
                    db,
                    sql: """
                    SELECT COUNT(*) FROM \(ScreenshotRecord.databaseTableName)
                    WHERE timestamp >= ? AND timestamp < ? AND ocrText IS NOT NULL AND ocrText != ''
                    """,
                    arguments: [dayStart, dayEnd]
                ) ?? 0
            }
        } catch {
            logReadError("ocrCount", error)
            throw error
        }
    }

    // MARK: - Record Queries

    func appUsageRecords(for date: Date) throws -> [AppUsageRecord] {
        let (dayStart, dayEnd) = dayBounds(for: date)
        do {
            return try DatabaseManager.shared.dbQueue.read { db in
                try AppUsageRecord
                    .filter(
                        AppUsageRecord.Columns.startTime >= dayStart
                            && AppUsageRecord.Columns.startTime < dayEnd
                    )
                    .order(AppUsageRecord.Columns.startTime.asc)
                    .fetchAll(db)
            }
        } catch {
            logReadError("appUsageRecords", error)
            throw error
        }
    }

    func appUsageBreakdown(for date: Date) throws -> [(bundleId: String, appName: String, totalDuration: TimeInterval)] {
        let (dayStart, dayEnd) = dayBounds(for: date)
        do {
            return try DatabaseManager.shared.dbQueue.read { db in
                let rows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT bundleId, MAX(appName) AS appName, SUM(duration) AS totalDuration
                    FROM \(AppUsageRecord.databaseTableName)
                    WHERE startTime >= ? AND startTime < ?
                    GROUP BY bundleId
                    ORDER BY totalDuration DESC
                    """,
                    arguments: [dayStart, dayEnd]
                )
                return rows.compactMap { row in
                    guard let bundleId = row["bundleId"] as? String,
                          let appName = row["appName"] as? String else { return nil }
                    let totalDuration: Double
                    if let d = row["totalDuration"] as? Double {
                        totalDuration = d
                    } else if let i = row["totalDuration"] as? Int64 {
                        totalDuration = Double(i)
                    } else {
                        return nil
                    }
                    return (bundleId: bundleId, appName: appName, totalDuration: totalDuration)
                }
            }
        } catch {
            logReadError("appUsageBreakdown", error)
            throw error
        }
    }

    func recentScreenshots(limit: Int, offset: Int) throws -> [ScreenshotRecord] {
        do {
            return try DatabaseManager.shared.dbQueue.read { db in
                try ScreenshotRecord
                    .order(ScreenshotRecord.Columns.timestamp.desc)
                    .limit(limit, offset: offset)
                    .fetchAll(db)
            }
        } catch {
            logReadError("recentScreenshots", error)
            throw error
        }
    }

    func screenshots(from startDate: Date, to endDate: Date) throws -> [ScreenshotRecord] {
        let rangeStart = startDate.startOfDay
        guard let rangeEnd = calendar.date(byAdding: .day, value: 1, to: endDate.startOfDay) else {
            return []
        }
        do {
            return try DatabaseManager.shared.dbQueue.read { db in
                try ScreenshotRecord
                    .filter(ScreenshotRecord.Columns.timestamp >= rangeStart && ScreenshotRecord.Columns.timestamp < rangeEnd)
                    .order(ScreenshotRecord.Columns.timestamp.asc)
                    .fetchAll(db)
            }
        } catch {
            logReadError("screenshots(from:to:)", error)
            throw error
        }
    }

    func inputActivity(for date: Date) throws -> [InputActivityRecord] {
        let (dayStart, dayEnd) = dayBounds(for: date)
        do {
            return try DatabaseManager.shared.dbQueue.read { db in
                try InputActivityRecord
                    .filter(
                        InputActivityRecord.Columns.minuteTimestamp >= dayStart
                            && InputActivityRecord.Columns.minuteTimestamp < dayEnd
                    )
                    .order(InputActivityRecord.Columns.minuteTimestamp.asc)
                    .fetchAll(db)
            }
        } catch {
            logReadError("inputActivity", error)
            throw error
        }
    }

    func clipboardRecords(for date: Date) throws -> [ClipboardRecord] {
        let (dayStart, dayEnd) = dayBounds(for: date)
        do {
            return try DatabaseManager.shared.dbQueue.read { db in
                try ClipboardRecord
                    .filter(ClipboardRecord.Columns.timestamp >= dayStart && ClipboardRecord.Columns.timestamp < dayEnd)
                    .order(ClipboardRecord.Columns.timestamp.desc)
                    .fetchAll(db)
            }
        } catch {
            logReadError("clipboardRecords", error)
            throw error
        }
    }

    func fileEvents(for date: Date) throws -> [FileEventRecord] {
        let (dayStart, dayEnd) = dayBounds(for: date)
        do {
            return try DatabaseManager.shared.dbQueue.read { db in
                try FileEventRecord
                    .filter(FileEventRecord.Columns.timestamp >= dayStart && FileEventRecord.Columns.timestamp < dayEnd)
                    .order(FileEventRecord.Columns.timestamp.desc)
                    .fetchAll(db)
            }
        } catch {
            logReadError("fileEvents", error)
            throw error
        }
    }

    // MARK: - Keystroke Queries

    func keystrokeRecords(for date: Date) throws -> [KeystrokeRecord] {
        let (dayStart, dayEnd) = dayBounds(for: date)
        do {
            return try DatabaseManager.shared.dbQueue.read { db in
                try KeystrokeRecord
                    .filter(KeystrokeRecord.Columns.timestamp >= dayStart && KeystrokeRecord.Columns.timestamp < dayEnd)
                    .order(KeystrokeRecord.Columns.timestamp.asc)
                    .fetchAll(db)
            }
        } catch {
            logReadError("keystrokeRecords", error)
            throw error
        }
    }

    func keystrokeGroups(for date: Date, windowSeconds: TimeInterval = 30) throws -> [KeystrokeGroup] {
        let records = try keystrokeRecords(for: date)
        guard !records.isEmpty else { return [] }

        var groups: [KeystrokeGroup] = []
        var currentChars: [String] = []
        var currentApp = records[0].activeApp
        var currentWindow = records[0].windowTitle
        var groupStart = records[0].timestamp
        var groupEnd = records[0].timestamp

        for record in records {
            let timeDiff = record.timestamp.timeIntervalSince(groupEnd)
            let appChanged = record.activeApp != currentApp

            if timeDiff > windowSeconds || appChanged {
                if !currentChars.isEmpty {
                    groups.append(KeystrokeGroup(
                        startTime: groupStart,
                        endTime: groupEnd,
                        activeApp: currentApp,
                        windowTitle: currentWindow,
                        text: currentChars.joined(),
                        keystrokeCount: currentChars.count
                    ))
                }
                currentChars = []
                currentApp = record.activeApp
                currentWindow = record.windowTitle
                groupStart = record.timestamp
            }

            if !record.characters.isEmpty {
                currentChars.append(record.characters)
            }
            groupEnd = record.timestamp
        }

        if !currentChars.isEmpty {
            groups.append(KeystrokeGroup(
                startTime: groupStart,
                endTime: groupEnd,
                activeApp: currentApp,
                windowTitle: currentWindow,
                text: currentChars.joined(),
                keystrokeCount: currentChars.count
            ))
        }

        return groups
    }

    // MARK: - Range Queries (for Insight Analysis)

    func appUsageBreakdown(from startDate: Date, to endDate: Date) throws -> [(bundleId: String, appName: String, totalDuration: TimeInterval)] {
        let rangeStart = startDate.startOfDay
        guard let rangeEnd = calendar.date(byAdding: .day, value: 1, to: endDate.startOfDay) else { return [] }
        do {
            return try DatabaseManager.shared.dbQueue.read { db in
                let rows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT bundleId, MAX(appName) AS appName, SUM(duration) AS totalDuration
                    FROM \(AppUsageRecord.databaseTableName)
                    WHERE startTime >= ? AND startTime < ?
                    GROUP BY bundleId
                    ORDER BY totalDuration DESC
                    """,
                    arguments: [rangeStart, rangeEnd]
                )
                return rows.compactMap { row in
                    guard let bundleId = row["bundleId"] as? String,
                          let appName = row["appName"] as? String else { return nil }
                    let totalDuration: Double
                    if let d = row["totalDuration"] as? Double {
                        totalDuration = d
                    } else if let i = row["totalDuration"] as? Int64 {
                        totalDuration = Double(i)
                    } else {
                        return nil
                    }
                    return (bundleId: bundleId, appName: appName, totalDuration: totalDuration)
                }
            }
        } catch {
            logReadError("appUsageBreakdown(range)", error)
            throw error
        }
    }

    func windowTitleSamples(from startDate: Date, to endDate: Date, limit: Int = 500) throws -> [(appName: String, windowTitle: String)] {
        let rangeStart = startDate.startOfDay
        guard let rangeEnd = calendar.date(byAdding: .day, value: 1, to: endDate.startOfDay) else { return [] }
        do {
            return try DatabaseManager.shared.dbQueue.read { db in
                let rows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT appName, windowTitle FROM \(AppUsageRecord.databaseTableName)
                    WHERE startTime >= ? AND startTime < ? AND windowTitle IS NOT NULL AND windowTitle != ''
                    ORDER BY duration DESC
                    LIMIT ?
                    """,
                    arguments: [rangeStart, rangeEnd, limit]
                )
                return rows.compactMap { row in
                    guard let appName = row["appName"] as? String,
                          let windowTitle = row["windowTitle"] as? String else { return nil }
                    return (appName: appName, windowTitle: windowTitle)
                }
            }
        } catch {
            logReadError("windowTitleSamples", error)
            throw error
        }
    }

    func fileEventPaths(from startDate: Date, to endDate: Date, limit: Int = 1000) throws -> [String] {
        let rangeStart = startDate.startOfDay
        guard let rangeEnd = calendar.date(byAdding: .day, value: 1, to: endDate.startOfDay) else { return [] }
        do {
            return try DatabaseManager.shared.dbQueue.read { db in
                try String.fetchAll(
                    db,
                    sql: """
                    SELECT DISTINCT path FROM \(FileEventRecord.databaseTableName)
                    WHERE timestamp >= ? AND timestamp < ?
                    ORDER BY timestamp DESC
                    LIMIT ?
                    """,
                    arguments: [rangeStart, rangeEnd, limit]
                )
            }
        } catch {
            logReadError("fileEventPaths", error)
            throw error
        }
    }

    func clipboardTexts(from startDate: Date, to endDate: Date, limit: Int = 200) throws -> [(sourceApp: String?, text: String)] {
        let rangeStart = startDate.startOfDay
        guard let rangeEnd = calendar.date(byAdding: .day, value: 1, to: endDate.startOfDay) else { return [] }
        do {
            return try DatabaseManager.shared.dbQueue.read { db in
                let rows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT sourceApp, textContent FROM \(ClipboardRecord.databaseTableName)
                    WHERE timestamp >= ? AND timestamp < ? AND textContent IS NOT NULL AND textContent != ''
                    ORDER BY timestamp DESC
                    LIMIT ?
                    """,
                    arguments: [rangeStart, rangeEnd, limit]
                )
                return rows.map { row in
                    (sourceApp: row["sourceApp"] as? String, text: (row["textContent"] as? String) ?? "")
                }
            }
        } catch {
            logReadError("clipboardTexts", error)
            throw error
        }
    }

    func ocrTexts(from startDate: Date, to endDate: Date, limit: Int = 200) throws -> [(activeApp: String, ocrText: String)] {
        let rangeStart = startDate.startOfDay
        guard let rangeEnd = calendar.date(byAdding: .day, value: 1, to: endDate.startOfDay) else { return [] }
        do {
            return try DatabaseManager.shared.dbQueue.read { db in
                let rows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT activeApp, ocrText FROM \(ScreenshotRecord.databaseTableName)
                    WHERE timestamp >= ? AND timestamp < ? AND ocrText IS NOT NULL AND ocrText != ''
                    ORDER BY timestamp DESC
                    LIMIT ?
                    """,
                    arguments: [rangeStart, rangeEnd, limit]
                )
                return rows.compactMap { row in
                    guard let app = row["activeApp"] as? String,
                          let text = row["ocrText"] as? String else { return nil }
                    return (activeApp: app, ocrText: text)
                }
            }
        } catch {
            logReadError("ocrTexts", error)
            throw error
        }
    }

    func appSwitchSequences(from startDate: Date, to endDate: Date, limit: Int = 500) throws -> [(from: String, to: String, count: Int)] {
        let rangeStart = startDate.startOfDay
        guard let rangeEnd = calendar.date(byAdding: .day, value: 1, to: endDate.startOfDay) else { return [] }
        do {
            return try DatabaseManager.shared.dbQueue.read { db in
                let records = try AppUsageRecord
                    .filter(AppUsageRecord.Columns.startTime >= rangeStart && AppUsageRecord.Columns.startTime < rangeEnd)
                    .order(AppUsageRecord.Columns.startTime.asc)
                    .fetchAll(db)

                var transitions: [String: Int] = [:]
                for i in 1..<records.count {
                    let prev = records[i - 1].appName
                    let curr = records[i].appName
                    if prev != curr {
                        let key = "\(prev)||\(curr)"
                        transitions[key, default: 0] += 1
                    }
                }

                return transitions
                    .map { pair -> (from: String, to: String, count: Int) in
                        let parts = pair.key.components(separatedBy: "||")
                        return (from: parts[0], to: parts.count > 1 ? parts[1] : "", count: pair.value)
                    }
                    .sorted { $0.count > $1.count }
                    .prefix(limit)
                    .map { $0 }
            }
        } catch {
            logReadError("appSwitchSequences", error)
            throw error
        }
    }

    // MARK: - Search

    func search(query: String, limit: Int) throws -> SearchResults {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return SearchResults(appUsageResults: [], clipboardResults: [], fileEventResults: [], ocrResults: [], keystrokeResults: [])
        }
        let pattern = Self.sqlLikePattern(trimmed)
        let lim = max(0, limit)
        do {
            return try DatabaseManager.shared.dbQueue.read { db in
                let appUsage = try AppUsageRecord.fetchAll(
                    db,
                    sql: """
                    SELECT * FROM \(AppUsageRecord.databaseTableName)
                    WHERE (windowTitle LIKE ? ESCAPE '\\' OR appName LIKE ? ESCAPE '\\')
                    ORDER BY startTime DESC
                    LIMIT ?
                    """,
                    arguments: [pattern, pattern, lim]
                )
                let clipboard = try ClipboardRecord.fetchAll(
                    db,
                    sql: """
                    SELECT * FROM \(ClipboardRecord.databaseTableName)
                    WHERE textContent LIKE ? ESCAPE '\\'
                    ORDER BY timestamp DESC
                    LIMIT ?
                    """,
                    arguments: [pattern, lim]
                )
                let fileEvents = try FileEventRecord.fetchAll(
                    db,
                    sql: """
                    SELECT * FROM \(FileEventRecord.databaseTableName)
                    WHERE path LIKE ? ESCAPE '\\'
                    ORDER BY timestamp DESC
                    LIMIT ?
                    """,
                    arguments: [pattern, lim]
                )
                let ocrScreenshots = try ScreenshotRecord.fetchAll(
                    db,
                    sql: """
                    SELECT * FROM \(ScreenshotRecord.databaseTableName)
                    WHERE ocrText LIKE ? ESCAPE '\\'
                    ORDER BY timestamp DESC
                    LIMIT ?
                    """,
                    arguments: [pattern, lim]
                )
                let keystrokes = try KeystrokeRecord.fetchAll(
                    db,
                    sql: """
                    SELECT * FROM \(KeystrokeRecord.databaseTableName)
                    WHERE characters LIKE ? ESCAPE '\\'
                    ORDER BY timestamp DESC
                    LIMIT ?
                    """,
                    arguments: [pattern, lim]
                )
                return SearchResults(
                    appUsageResults: appUsage,
                    clipboardResults: clipboard,
                    fileEventResults: fileEvents,
                    ocrResults: ocrScreenshots,
                    keystrokeResults: keystrokes
                )
            }
        } catch {
            logReadError("search", error)
            throw error
        }
    }

    private static func sqlLikePattern(_ raw: String) -> String {
        let escaped = raw
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        return "%\(escaped)%"
    }
}
