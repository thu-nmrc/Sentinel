import Foundation
import GRDB

final class DatabaseManager {
    static let shared = DatabaseManager()

    let dbQueue: DatabaseQueue

    private init() {
        let path = SentinelConstants.StoragePaths.databasePath.path
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        dbQueue = try! DatabaseQueue(path: path, configuration: config)
        do {
            try Self.migrate(dbQueue)
        } catch {
            fatalError("Database migration failed: \(error)")
        }
    }

    private static func migrate(_ dbQueue: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: AppUsageRecord.databaseTableName) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("bundleId", .text).notNull()
                t.column("appName", .text).notNull()
                t.column("windowTitle", .text)
                t.column("startTime", .datetime).notNull()
                t.column("endTime", .datetime)
                t.column("duration", .double).notNull().defaults(to: 0)
            }

            try db.create(table: ScreenshotRecord.databaseTableName) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("timestamp", .datetime).notNull()
                t.column("filePath", .text).notNull()
                t.column("activeApp", .text).notNull()
                t.column("windowTitle", .text)
                t.column("displayId", .integer).notNull()
            }

            try db.create(table: InputActivityRecord.databaseTableName) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("minuteTimestamp", .datetime).notNull()
                t.column("keystrokeCount", .integer).notNull().defaults(to: 0)
                t.column("mouseClickCount", .integer).notNull().defaults(to: 0)
                t.column("mouseScrollCount", .integer).notNull().defaults(to: 0)
                t.column("mouseTravelDistance", .double).notNull().defaults(to: 0)
            }

            try db.create(table: FileEventRecord.databaseTableName) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("timestamp", .datetime).notNull()
                t.column("path", .text).notNull()
                t.column("eventType", .text).notNull()
                t.column("appBundleId", .text)
            }

            try db.create(table: ClipboardRecord.databaseTableName) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("timestamp", .datetime).notNull()
                t.column("contentType", .text).notNull()
                t.column("textContent", .text)
                t.column("sourceApp", .text)
            }

            try db.create(index: "idx_appUsageRecords_bundleId", on: AppUsageRecord.databaseTableName, columns: ["bundleId"])
            try db.create(index: "idx_appUsageRecords_startTime", on: AppUsageRecord.databaseTableName, columns: ["startTime"])
            try db.create(index: "idx_screenshotRecords_timestamp", on: ScreenshotRecord.databaseTableName, columns: ["timestamp"])
            try db.create(
                index: "idx_inputActivityRecords_minuteTimestamp",
                on: InputActivityRecord.databaseTableName,
                columns: ["minuteTimestamp"]
            )
            try db.create(index: "idx_fileEventRecords_timestamp", on: FileEventRecord.databaseTableName, columns: ["timestamp"])
            try db.create(index: "idx_clipboardRecords_timestamp", on: ClipboardRecord.databaseTableName, columns: ["timestamp"])
        }

        migrator.registerMigration("v2") { db in
            try db.create(table: KeystrokeRecord.databaseTableName) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("timestamp", .datetime).notNull()
                t.column("characters", .text).notNull()
                t.column("keyCode", .integer).notNull()
                t.column("modifiers", .integer).notNull().defaults(to: 0)
                t.column("activeApp", .text).notNull()
                t.column("windowTitle", .text)
            }
            try db.create(index: "idx_keystrokeRecords_timestamp", on: KeystrokeRecord.databaseTableName, columns: ["timestamp"])
            try db.create(index: "idx_keystrokeRecords_activeApp", on: KeystrokeRecord.databaseTableName, columns: ["activeApp"])

            try db.alter(table: ScreenshotRecord.databaseTableName) { t in
                t.add(column: "ocrText", .text)
            }
        }

        try migrator.migrate(dbQueue)
    }
}
