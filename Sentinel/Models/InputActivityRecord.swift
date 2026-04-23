import Foundation
import GRDB

struct InputActivityRecord: Codable, FetchableRecord, PersistableRecord, Identifiable {
    var id: Int64?
    var minuteTimestamp: Date
    var keystrokeCount: Int
    var mouseClickCount: Int
    var mouseScrollCount: Int
    var mouseTravelDistance: Double

    static let databaseTableName = "inputActivityRecords"

    enum CodingKeys: String, CodingKey, ColumnExpression {
        case id
        case minuteTimestamp
        case keystrokeCount
        case mouseClickCount
        case mouseScrollCount
        case mouseTravelDistance
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let minuteTimestamp = Column(CodingKeys.minuteTimestamp)
        static let keystrokeCount = Column(CodingKeys.keystrokeCount)
        static let mouseClickCount = Column(CodingKeys.mouseClickCount)
        static let mouseScrollCount = Column(CodingKeys.mouseScrollCount)
        static let mouseTravelDistance = Column(CodingKeys.mouseTravelDistance)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
