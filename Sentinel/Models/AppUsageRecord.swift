import Foundation
import GRDB

struct AppUsageRecord: Codable, FetchableRecord, PersistableRecord, Identifiable {
    var id: Int64?
    var bundleId: String
    var appName: String
    var windowTitle: String?
    var startTime: Date
    var endTime: Date?
    var duration: TimeInterval

    static let databaseTableName = "appUsageRecords"

    enum CodingKeys: String, CodingKey, ColumnExpression {
        case id
        case bundleId
        case appName
        case windowTitle
        case startTime
        case endTime
        case duration
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let bundleId = Column(CodingKeys.bundleId)
        static let appName = Column(CodingKeys.appName)
        static let windowTitle = Column(CodingKeys.windowTitle)
        static let startTime = Column(CodingKeys.startTime)
        static let endTime = Column(CodingKeys.endTime)
        static let duration = Column(CodingKeys.duration)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
