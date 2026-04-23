import Foundation
import GRDB

struct ScreenshotRecord: Codable, FetchableRecord, PersistableRecord, Identifiable {
    var id: Int64?
    var timestamp: Date
    var filePath: String
    var activeApp: String
    var windowTitle: String?
    var displayId: Int
    var ocrText: String?

    static let databaseTableName = "screenshotRecords"

    enum CodingKeys: String, CodingKey, ColumnExpression {
        case id
        case timestamp
        case filePath
        case activeApp
        case windowTitle
        case displayId
        case ocrText
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let timestamp = Column(CodingKeys.timestamp)
        static let filePath = Column(CodingKeys.filePath)
        static let activeApp = Column(CodingKeys.activeApp)
        static let windowTitle = Column(CodingKeys.windowTitle)
        static let displayId = Column(CodingKeys.displayId)
        static let ocrText = Column(CodingKeys.ocrText)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
