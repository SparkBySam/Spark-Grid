import CoreGraphics
import Foundation

struct Workbook: Codable, Equatable, Sendable {
    static let defaultRowCount = 1_000
    static let defaultColumnCount = 26
    static let defaultColumnWidth: CGFloat = 80
    static let defaultRowHeight: CGFloat = 22

    var sheets: [Sheet]
    var activeSheetIndex: Int

    init(sheets: [Sheet] = [Sheet(name: "Sheet1")], activeSheetIndex: Int = 0) {
        self.sheets = sheets.isEmpty ? [Sheet(name: "Sheet1")] : sheets
        self.activeSheetIndex = min(max(0, activeSheetIndex), self.sheets.count - 1)
    }

    var activeSheet: Sheet {
        get { sheets[activeSheetIndex] }
        set { sheets[activeSheetIndex] = newValue }
    }

    var isEffectivelyEmpty: Bool {
        sheets.allSatisfy(\.cells.isEmpty)
    }

    static var empty: Workbook { Workbook() }
}
