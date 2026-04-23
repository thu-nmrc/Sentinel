import Foundation
import GRDB

struct KeystrokeRecord: Codable, FetchableRecord, PersistableRecord, Identifiable {
    var id: Int64?
    var timestamp: Date
    var characters: String
    var keyCode: Int
    var modifiers: Int
    var activeApp: String
    var windowTitle: String?

    static let databaseTableName = "keystrokeRecords"

    enum CodingKeys: String, CodingKey, ColumnExpression {
        case id
        case timestamp
        case characters
        case keyCode
        case modifiers
        case activeApp
        case windowTitle
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let timestamp = Column(CodingKeys.timestamp)
        static let characters = Column(CodingKeys.characters)
        static let keyCode = Column(CodingKeys.keyCode)
        static let modifiers = Column(CodingKeys.modifiers)
        static let activeApp = Column(CodingKeys.activeApp)
        static let windowTitle = Column(CodingKeys.windowTitle)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
