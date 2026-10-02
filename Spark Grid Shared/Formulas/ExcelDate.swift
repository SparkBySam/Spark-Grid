import Foundation

/// Excel-compatible date serials (days since 1899-12-30), ignoring the 1900 leap-year bug.
enum ExcelDate {
  private static let epoch: Date = {
    var components = DateComponents()
    components.calendar = Calendar(identifier: .gregorian)
    components.timeZone = TimeZone(secondsFromGMT: 0)
    components.year = 1899
    components.month = 12
    components.day = 30
    return components.date ?? Date(timeIntervalSince1970: -2_209_161_600)
  }()

  static func serial(from date: Date) -> Double {
    let days = date.timeIntervalSince(epoch) / 86_400
    return days.rounded(.down)
  }

  static func date(from serial: Double) -> Date? {
    epoch.addingTimeInterval(serial * 86_400)
  }
}
