import Foundation
import GRDB

struct ClipboardRecord: Codable, FetchableRecord, PersistableRecord, Identifiable {
    var id: Int64?
    var timestamp: Date
    var contentType: String
    var textContent: String?
    var sourceApp: String?

    static let databaseTableName = "clipboardRecords"

    enum CodingKeys: String, CodingKey, ColumnExpression {
        case id
        case timestamp
        case contentType
        case textContent
        case sourceApp
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let timestamp = Column(CodingKeys.timestamp)
        static let contentType = Column(CodingKeys.contentType)
        static let textContent = Column(CodingKeys.textContent)
        static let sourceApp = Column(CodingKeys.sourceApp)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
