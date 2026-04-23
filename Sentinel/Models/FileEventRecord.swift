import Foundation
import GRDB

struct FileEventRecord: Codable, FetchableRecord, PersistableRecord, Identifiable {
    var id: Int64?
    var timestamp: Date
    var path: String
    var eventType: String
    var appBundleId: String?

    static let databaseTableName = "fileEventRecords"

    enum CodingKeys: String, CodingKey, ColumnExpression {
        case id
        case timestamp
        case path
        case eventType
        case appBundleId
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let timestamp = Column(CodingKeys.timestamp)
        static let path = Column(CodingKeys.path)
        static let eventType = Column(CodingKeys.eventType)
        static let appBundleId = Column(CodingKeys.appBundleId)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
