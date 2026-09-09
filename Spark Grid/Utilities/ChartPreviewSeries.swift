import Foundation

/// Infers label/value pairs for chart sidebar previews from an arbitrary selection shape.
enum ChartPreviewSeries {
  static let maxPreviewPoints = 24

  struct Point: Identifiable {
    let id: Int
    let label: String
    let value: Double
  }

  static func points(
    in range: CellRange,
    labelFor: (CellAddress) -> String,
    numberFor: (CellAddress) -> Double?
  ) -> [Point] {
    series(in: range, labelFor: labelFor, numberFor: numberFor).points
  }

  static func series(
    in range: CellRange,
    labelFor: (CellAddress) -> String,
    numberFor: (CellAddress) -> Double?
  ) -> (points: [Point], totalCount: Int) {
    let uncapped = uncappedPoints(in: range, labelFor: labelFor, numberFor: numberFor)
    return (capped(uncapped), uncapped.count)
  }

  private static func uncappedPoints(
    in range: CellRange,
    labelFor: (CellAddress) -> String,
    numberFor: (CellAddress) -> Double?
  ) -> [Point] {
    let n = range.normalized
    let rows = Array(n.minRow...n.maxRow)
    let cols = Array(n.minCol...n.maxCol)
    guard !rows.isEmpty, !cols.isEmpty else { return [] }

    if cols.count == 1 {
      return seriesFromSingleColumn(rows: rows, col: cols[0], labelFor: labelFor, numberFor: numberFor)
    }
    if rows.count == 1 {
      return seriesFromSingleRow(cols: cols, row: rows[0], labelFor: labelFor, numberFor: numberFor)
    }

    let valueCol = cols.max(by: { lhs, rhs in
      numericScore(col: lhs, rows: rows, numberFor: numberFor)
        < numericScore(col: rhs, rows: rows, numberFor: numberFor)
    }) ?? cols[0]
    let labelCol = preferredLabelColumn(
      cols: cols,
      rows: rows,
      valueCol: valueCol,
      labelFor: labelFor,
      numberFor: numberFor
    )
    var startRow = rows.first!
    if rows.count > 1, looksLikeHeaderRow(
      row: startRow,
      labelCol: labelCol,
      valueCol: valueCol,
      labelFor: labelFor,
      numberFor: numberFor
    ) {
      startRow += 1
    }

    var result: [Point] = []
    var index = 0
    for row in rows where row >= startRow {
      guard let value = numberFor(CellAddress(row: row, col: valueCol)) else { continue }
      let rawLabel = labelFor(CellAddress(row: row, col: labelCol))
      let label = rawLabel.isEmpty ? "\(index + 1)" : rawLabel
      result.append(Point(id: index, label: label, value: value))
      index += 1
    }
    return result
  }

  private static func capped(_ points: [Point]) -> [Point] {
    guard points.count > maxPreviewPoints else { return points }
    return Array(points.prefix(maxPreviewPoints))
  }

  private static func seriesFromSingleColumn(
    rows: [Int],
    col: Int,
    labelFor: (CellAddress) -> String,
    numberFor: (CellAddress) -> Double?
  ) -> [Point] {
    var result: [Point] = []
    var index = 0
    for row in rows {
      let address = CellAddress(row: row, col: col)
      guard let value = numberFor(address) else { continue }
      let text = labelFor(address)
      let label = text.isEmpty ? "\(index + 1)" : text
      result.append(Point(id: index, label: label, value: value))
      index += 1
    }
    return result
  }

  private static func seriesFromSingleRow(
    cols: [Int],
    row: Int,
    labelFor: (CellAddress) -> String,
    numberFor: (CellAddress) -> Double?
  ) -> [Point] {
    var result: [Point] = []
    var index = 0
    for col in cols {
      let address = CellAddress(row: row, col: col)
      guard let value = numberFor(address) else { continue }
      let text = labelFor(address)
      let label = text.isEmpty ? CellAddress(row: row, col: col).a1 : text
      result.append(Point(id: index, label: label, value: value))
      index += 1
    }
    return result
  }

  private static func numericScore(
    col: Int,
    rows: [Int],
    numberFor: (CellAddress) -> Double?
  ) -> Int {
    rows.reduce(0) { count, row in
      numberFor(CellAddress(row: row, col: col)) != nil ? count + 1 : count
    }
  }

  private static func preferredLabelColumn(
    cols: [Int],
    rows: [Int],
    valueCol: Int,
    labelFor: (CellAddress) -> String,
    numberFor: (CellAddress) -> Double?
  ) -> Int {
    var bestCol = cols.first { $0 != valueCol } ?? valueCol
    var bestScore = -1
    for col in cols where col != valueCol {
      let score = rows.reduce(0) { count, row in
        let address = CellAddress(row: row, col: col)
        let text = labelFor(address)
        guard !text.isEmpty, numberFor(address) == nil else { return count }
        return count + 1
      }
      if score > bestScore {
        bestScore = score
        bestCol = col
      }
    }
    return bestCol
  }

  private static func looksLikeHeaderRow(
    row: Int,
    labelCol: Int,
    valueCol: Int,
    labelFor: (CellAddress) -> String,
    numberFor: (CellAddress) -> Double?
  ) -> Bool {
    let labelText = labelFor(CellAddress(row: row, col: labelCol))
    guard !labelText.isEmpty else { return false }
    guard numberFor(CellAddress(row: row, col: valueCol)) != nil else { return false }
    return numberFor(CellAddress(row: row, col: labelCol)) == nil
  }
}
