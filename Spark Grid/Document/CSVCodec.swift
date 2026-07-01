import Foundation

enum CSVCodec {
  /// Parse CSV/TSV text into a sparse sheet cell map.
  static func importCSV(_ text: String) -> [CellAddress: Cell] {
    let normalized = normalizeLineEndings(stripBOM(text))
    let delimiter = detectDelimiter(in: normalized)
    var cells: [CellAddress: Cell] = [:]
    let rows = parseRows(from: normalized, delimiter: delimiter)
    for (rowIndex, fields) in rows.enumerated() {
      for (colIndex, field) in fields.enumerated() {
        let value = field.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { continue }
        cells[CellAddress(row: rowIndex, col: colIndex)] = Cell(raw: value)
      }
    }
    return cells
  }

  /// Export the active sheet to CSV text.
  static func exportCSV(from sheet: Sheet) -> String {
    let maxRow = sheet.maxPopulatedRow
    let maxCol = sheet.maxPopulatedColumn
    guard maxRow >= 0, maxCol >= 0 else { return "" }

    var lines: [String] = []
    lines.reserveCapacity(maxRow + 1)
    for row in 0...maxRow {
      var fields: [String] = []
      fields.reserveCapacity(maxCol + 1)
      for col in 0...maxCol {
        let value = sheet.cell(at: CellAddress(row: row, col: col)).raw
        fields.append(escapeField(value))
      }
      lines.append(fields.joined(separator: ","))
    }
    return lines.joined(separator: "\n")
  }

  // MARK: - Parsing

  private static func stripBOM(_ text: String) -> String {
    guard text.first == "\u{FEFF}" else { return text }
    return String(text.dropFirst())
  }

  /// Excel and many exports use CRLF; Swift can treat `\r\n` as one Character that is not `==` to `\r` or `\n`.
  private static func normalizeLineEndings(_ text: String) -> String {
    text
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
  }

  private static func detectDelimiter(in text: String) -> Character {
    let sample = text.prefix(8_192)
    let firstLine = sample.split(whereSeparator: \.isNewline).first.map(String.init) ?? String(sample)
    let commaCount = firstLine.filter { $0 == "," }.count
    let tabCount = firstLine.filter { $0 == "\t" }.count
    let semicolonCount = firstLine.filter { $0 == ";" }.count
    if tabCount > commaCount && tabCount > semicolonCount { return "\t" }
    if semicolonCount > commaCount { return ";" }
    return ","
  }

  private static func parseRows(from text: String, delimiter: Character) -> [[String]] {
    var rows: [[String]] = []
    var currentRow: [String] = []
    var currentField = ""
    var inQuotes = false
    var index = text.startIndex

    func finishField() {
      currentRow.append(currentField)
      currentField = ""
    }

    func finishRow() {
      finishField()
      if !currentRow.isEmpty {
        rows.append(currentRow)
      }
      currentRow = []
    }

    while index < text.endIndex {
      let char = text[index]

      if inQuotes {
        if char == "\"" {
          let next = text.index(after: index)
          if next < text.endIndex, text[next] == "\"" {
            currentField.append("\"")
            index = next
          } else {
            inQuotes = false
          }
        } else {
          currentField.append(char)
        }
      } else if char == "\"" {
        inQuotes = true
      } else if char == delimiter {
        finishField()
      } else if char == "\n" {
        finishRow()
      } else {
        currentField.append(char)
      }

      index = text.index(after: index)
    }

    if inQuotes {
      finishField()
    }
    if !currentField.isEmpty || !currentRow.isEmpty {
      finishField()
      if !currentRow.isEmpty {
        rows.append(currentRow)
      }
    }

    return rows
  }

  private static func escapeField(_ value: String) -> String {
    let needsQuotes = value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r")
    guard needsQuotes else { return value }
    return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
  }
}
