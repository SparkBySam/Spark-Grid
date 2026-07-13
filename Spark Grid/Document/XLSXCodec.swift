import CoreGraphics
import CoreXLSX
import Foundation
import ZIPFoundation

enum XLSXCodec {
  enum CodecError: LocalizedError {
    case unreadable
    case emptyWorkbook
    case writeFailed

    var errorDescription: String? {
      switch self {
      case .unreadable: return "Couldn't read the Excel workbook."
      case .emptyWorkbook: return "The Excel workbook has no sheets."
      case .writeFailed: return "Couldn't write the Excel workbook."
      }
    }
  }

  // MARK: - Import

  static func importWorkbook(from data: Data) throws -> Workbook {
    let file = try XLSXFile(data: data)
    return try importWorkbook(from: file, archiveData: data)
  }

  static func importWorkbook(from url: URL) throws -> Workbook {
    let data = try Data(contentsOf: url)
    return try importWorkbook(from: data)
  }

  private static func importWorkbook(from file: XLSXFile, archiveData: Data) throws -> Workbook {
    let sharedStrings = try? file.parseSharedStrings()
    let styles = try? file.parseStyles()
    var sheets: [Sheet] = []

    for wbk in try file.parseWorkbooks() {
      for (name, path) in try file.parseWorksheetPathsAndNames(workbook: wbk) {
        let worksheet = try file.parseWorksheet(at: path)
        var sheet = Sheet(name: name ?? "Sheet\(sheets.count + 1)")
        importCells(
          from: worksheet,
          into: &sheet,
          sharedStrings: sharedStrings,
          styles: styles
        )
        expandSharedFormulas(into: &sheet, archiveData: archiveData, worksheetPath: path)
        importColumnWidths(from: worksheet, into: &sheet)
        importRowHeights(from: worksheet, into: &sheet)
        sheets.append(sheet)
      }
    }

    guard !sheets.isEmpty else { throw CodecError.emptyWorkbook }
    // Defined names are not exposed by CoreXLSX Workbook model — skip without failing.
    return Workbook(sheets: sheets, activeSheetIndex: 0)
  }

  /// CoreXLSX drops shared-formula followers (`<f t="shared" si="…"/>`). Expand them from sheet XML.
  private static func expandSharedFormulas(
    into sheet: inout Sheet,
    archiveData: Data,
    worksheetPath: String
  ) {
    guard let xml = zipEntryString(archiveData: archiveData, entryPath: worksheetPath) else { return }

    struct SharedMaster {
      var address: CellAddress
      var formula: String
    }

    var masters: [Int: SharedMaster] = [:]
    var followers: [(CellAddress, Int)] = []

    // Match <c r="E2"…>…<f t="shared" …>…</f> or self-closing <f …/>
    let cellPattern = #"<c\b([^>]*)>(.*?)</c>"#
    let cellRegex = try? NSRegularExpression(pattern: cellPattern, options: [.dotMatchesLineSeparators])
    let nsxml = xml as NSString
    let full = NSRange(location: 0, length: nsxml.length)
    guard let cellRegex else { return }

    for match in cellRegex.matches(in: xml, options: [], range: full) {
      let attrs = nsxml.substring(with: match.range(at: 1))
      let body = nsxml.substring(with: match.range(at: 2))
      guard let rAttrRange = attrs.range(of: #"r="[^"]+""#, options: .regularExpression) else { continue }
      let rAttr = String(attrs[rAttrRange])
      guard let q1 = rAttr.firstIndex(of: "\""),
            let q2 = rAttr.lastIndex(of: "\""),
            q1 < q2
      else { continue }
      let ref = String(rAttr[rAttr.index(after: q1)..<q2])
      guard let address = address(fromA1: ref) else { continue }

      guard let fRange = body.range(
        of: #"<f\b[^>]*(?:/>|>[\s\S]*?</f>)"#,
        options: .regularExpression
      ) else { continue }
      let fTag = String(body[fRange])
      guard fTag.contains(#"t="shared""#) || fTag.contains("t='shared'") else { continue }

      var si: Int?
      if let siMatch = fTag.range(of: #"si="\d+""#, options: .regularExpression) {
        si = Int(String(fTag[siMatch]).filter(\.isNumber))
      }
      guard let sharedIndex = si else { continue }

      if let open = fTag.range(of: ">"), fTag.contains("</f>") {
        let after = fTag[open.upperBound...]
        if let close = after.range(of: "</f>") {
          let formula = decodeXMLEntities(
            String(after[..<close.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
          )
          if !formula.isEmpty {
            masters[sharedIndex] = SharedMaster(address: address, formula: formula)
            let raw = formula.hasPrefix("=") ? formula : "=\(formula)"
            var cell = sheet.cell(at: address)
            cell.raw = raw
            sheet.setCell(cell, at: address)
            continue
          }
        }
      }
      followers.append((address, sharedIndex))
    }

    for (address, sharedIndex) in followers {
      guard let master = masters[sharedIndex] else { continue }
      let rowDelta = address.row - master.address.row
      let colDelta = address.col - master.address.col
      let base = master.formula.hasPrefix("=") ? master.formula : "=\(master.formula)"
      let adjusted = FormulaRewriter.adjust(base, rowDelta: rowDelta, colDelta: colDelta)
      var cell = sheet.cell(at: address)
      cell.raw = adjusted
      sheet.setCell(cell, at: address)
    }
  }

  private static func zipEntryString(archiveData: Data, entryPath: String) -> String? {
    let normalized = entryPath.hasPrefix("/") ? String(entryPath.dropFirst()) : entryPath
    guard let archive = try? Archive(data: archiveData, accessMode: .read) else { return nil }
    let candidates = [normalized, normalized.hasPrefix("xl/") ? normalized : "xl/\(normalized)"]
    for path in candidates {
      guard let entry = archive[path] else { continue }
      var data = Data()
      do {
        _ = try archive.extract(entry) { chunk in
          data.append(chunk)
        }
      } catch {
        continue
      }
      if let text = String(data: data, encoding: .utf8) {
        return text
      }
    }
    return nil
  }

  private static func decodeXMLEntities(_ string: String) -> String {
    string
      .replacingOccurrences(of: "&amp;", with: "&")
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "&apos;", with: "'")
  }

  private static func address(fromA1 ref: String) -> CellAddress? {
    guard let parsed = A1Reference.parseAddress(ref) else { return nil }
    return CellAddress(row: parsed.row, col: parsed.col)
  }

  private static func importCells(
    from worksheet: Worksheet,
    into sheet: inout Sheet,
    sharedStrings: SharedStrings?,
    styles: Styles?
  ) {
    for row in worksheet.data?.rows ?? [] {
      for cell in row.cells {
        guard let address = address(from: cell.reference) else { continue }
        let raw = cellRawValue(cell, sharedStrings: sharedStrings)
        guard !raw.isEmpty || cell.styleIndex != nil else { continue }
        var model = Cell(raw: raw)
        if let styles, let format = cellFormat(from: cell, styles: styles) {
          model.format = format
        }
        sheet.setCell(model, at: address)
      }
    }
  }

  private static func cellRawValue(_ cell: CoreXLSX.Cell, sharedStrings: SharedStrings?) -> String {
    if let formula = cell.formula?.value, !formula.isEmpty {
      return formula.hasPrefix("=") ? formula : "=\(formula)"
    }
    if let sharedStrings, let text = cell.stringValue(sharedStrings) {
      return text
    }
    if let inline = cell.inlineString?.text, !inline.isEmpty {
      return inline
    }
    return cell.value ?? ""
  }

  private static func cellFormat(from cell: CoreXLSX.Cell, styles: Styles) -> CellFormat? {
    var format = CellFormat()
    var changed = false

    if let font = cell.font(in: styles) {
      if font.bold != nil {
        format.bold = true
        changed = true
      }
      if font.italic != nil {
        format.italic = true
        changed = true
      }
      if font.strike != nil {
        format.strikethrough = true
        changed = true
      }
      if let size = font.size?.value {
        format.fontSize = CGFloat(size)
        changed = true
      }
      if let name = font.name?.value, !name.isEmpty {
        format.fontFamily = name
        changed = true
      }
      if let color = codableColor(from: font.color) {
        format.textColor = color
        changed = true
      }
    }

    if let fillId = cell.format(in: styles)?.fillId,
       let fills = styles.fills?.items,
       fillId >= 0,
       fillId < fills.count
    {
      let pattern = fills[fillId].patternFill
      if pattern.patternType != "none",
         let color = codableColor(from: pattern.foregroundColor ?? pattern.backgroundColor)
      {
        format.fillColor = color
        changed = true
      }
    }

    if let xf = cell.format(in: styles) {
      if let mapped = numberFormat(for: xf.numberFormatId, styles: styles) {
        // Prefer explicit number formats even when applyNumberFormat is omitted (common in Excel exports).
        format.numberFormat = mapped
        changed = true
      }

      if let borderId = xf.borderId,
         let borders = styles.borders?.items,
         borderId >= 0,
         borderId < borders.count
      {
        let imported = cellBorders(from: borders[borderId])
        if imported.hasAny {
          format.borders = imported
          changed = true
        }
      }

      if let alignment = xf.alignment {
        if let horizontal = horizontalAlign(from: alignment.horizontal) {
          format.horizontalAlign = horizontal
          changed = true
        }
        if let vertical = verticalAlign(from: alignment.vertical) {
          format.verticalAlign = vertical
          changed = true
        }
        if alignment.wrapText == true {
          format.wrapText = true
          changed = true
        }
      }
    }

    return changed ? format : nil
  }

  private static func cellBorders(from border: Border) -> CellBorders {
    CellBorders(
      top: borderEdge(from: border.top),
      bottom: borderEdge(from: border.bottom),
      left: borderEdge(from: border.left),
      right: borderEdge(from: border.right)
    )
  }

  private static func borderEdge(from value: Border.Value?) -> BorderEdge? {
    guard let value, let style = borderStyle(from: value.style) else { return nil }
    return BorderEdge(style: style, color: codableColor(from: value.color))
  }

  private static func borderStyle(from raw: String?) -> BorderStyle? {
    guard let raw, !raw.isEmpty else { return nil }
    switch raw {
    case "thin": return .thin
    case "medium": return .medium
    case "thick": return .thick
    case "dashed", "mediumDashed", "dashDot", "mediumDashDot",
         "dashDotDot", "mediumDashDotDot", "slantDashDot":
      return .dashed
    case "dotted", "hair": return .dotted
    case "double": return .double
    default: return .thin
    }
  }

  private static func horizontalAlign(from raw: String?) -> CellFormat.HorizontalAlign? {
    switch raw {
    case "left": return .left
    case "center", "centerContinuous": return .center
    case "right": return .right
    case "general": return .general
    default: return nil
    }
  }

  private static func verticalAlign(from raw: String?) -> CellFormat.VerticalAlign? {
    switch raw {
    case "top": return .top
    case "center": return .middle
    case "bottom": return .bottom
    default: return nil
    }
  }

  private static func numberFormat(for id: Int, styles: Styles) -> CellFormat.NumberFormat? {
    if let custom = styles.numberFormats?.items.first(where: { $0.id == id })?.formatCode.lowercased() {
      if custom.contains("%") { return .percent }
      if custom.contains("$") || custom.contains("¥") || custom.contains("€") { return .currency }
      if custom.contains("e+") || custom.contains("e-") { return .scientific }
      // Avoid treating patterns like `#0` as dates just because of incidental letters.
      let looksLikeDate = (custom.contains("y") || custom.contains("d"))
        && (custom.contains("m") || custom.contains("yy") || custom.contains("dd"))
      if looksLikeDate {
        if custom.contains("h") || custom.contains("s") { return .time }
        return .date
      }
      if custom.contains("h") && custom.contains(":") { return .time }
      if custom.contains("0") || custom.contains("#") { return .number }
    }
    switch id {
    case 1, 2, 3, 4: return .number
    case 5, 6, 7, 8: return .currency
    case 9, 10: return .percent
    case 11: return .scientific
    case 14, 15, 16, 17: return .date
    case 18, 19, 20, 21: return .time
    case 22: return .date // m/d/yy h:mm
    default: return nil
    }
  }

  private static func codableColor(from color: Color?) -> CodableColor? {
    guard let rgb = color?.rgb, rgb.count >= 6 else { return nil }
    let hex = rgb.count == 8 ? String(rgb.suffix(6)) : rgb
    guard let value = UInt32(hex, radix: 16) else { return nil }
    let r = Double((value >> 16) & 0xFF) / 255
    let g = Double((value >> 8) & 0xFF) / 255
    let b = Double(value & 0xFF) / 255
    return CodableColor(red: r, green: g, blue: b, alpha: 1)
  }

  private static func importColumnWidths(from worksheet: Worksheet, into sheet: inout Sheet) {
    for column in worksheet.columns?.items ?? [] {
      // Excel character widths ≈ pixels / 7 for default fonts.
      let width = CGFloat(column.width) * 7
      guard width > 0 else { continue }
      for col in column.min...column.max {
        sheet.columnWidths[col - 1] = width
      }
    }
  }

  private static func importRowHeights(from worksheet: Worksheet, into sheet: inout Sheet) {
    for row in worksheet.data?.rows ?? [] {
      guard let height = row.height, height > 0 else { continue }
      sheet.rowHeights[Int(row.reference) - 1] = CGFloat(height)
    }
  }

  private static func address(from reference: CellReference) -> CellAddress? {
    guard let col = A1Notation.columnIndex(from: reference.column.value) else { return nil }
    let row = Int(reference.row) - 1
    guard row >= 0, col >= 0 else { return nil }
    return CellAddress(row: row, col: col)
  }

  // MARK: - Export

  static func exportWorkbook(_ workbook: Workbook) throws -> Data {
    var sharedStrings: [String] = []
    var sharedIndex: [String: Int] = [:]

    func intern(_ text: String) -> Int {
      if let existing = sharedIndex[text] { return existing }
      let index = sharedStrings.count
      sharedStrings.append(text)
      sharedIndex[text] = index
      return index
    }

    var styleCatalog: [StyleKey: Int] = [:]
    var styleList: [StyleKey] = [.default]
    styleCatalog[.default] = 0

    func styleIndex(for format: CellFormat?) -> Int {
      let key = StyleKey(format: format)
      if let existing = styleCatalog[key] { return existing }
      let index = styleList.count
      styleList.append(key)
      styleCatalog[key] = index
      return index
    }

    var files: [String: Data] = [:]
    files["[Content_Types].xml"] = contentTypesXML(sheetCount: workbook.sheets.count)
    files["_rels/.rels"] = rootRelsXML
    files["xl/workbook.xml"] = workbookXML(workbook)
    files["xl/_rels/workbook.xml.rels"] = workbookRelsXML(sheetCount: workbook.sheets.count)

    for (index, sheet) in workbook.sheets.enumerated() {
      let sheetXML = worksheetXML(
        sheet,
        intern: intern,
        styleIndex: styleIndex
      )
      files["xl/worksheets/sheet\(index + 1).xml"] = sheetXML
    }

    files["xl/sharedStrings.xml"] = sharedStringsXML(sharedStrings)
    files["xl/styles.xml"] = stylesXML(styleList)

    guard let data = MinimalZip.archive(files: files) else {
      throw CodecError.writeFailed
    }
    return data
  }

  // MARK: - Export XML builders

  private static func contentTypesXML(sheetCount: Int) -> Data {
    var overrides = """
    <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
    <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
    <Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>
    """
    for i in 1...sheetCount {
      overrides += """
      <Override PartName="/xl/worksheets/sheet\(i).xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
      """
    }
    let xml = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
    <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
    <Default Extension="xml" ContentType="application/xml"/>
    \(overrides)
    </Types>
    """
    return Data(xml.utf8)
  }

  private static let rootRelsXML = Data("""
  <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
  </Relationships>
  """.utf8)

  private static func workbookXML(_ workbook: Workbook) -> Data {
    var sheetsXML = ""
    for (index, sheet) in workbook.sheets.enumerated() {
      let name = escapeXML(sheet.name)
      sheetsXML += #"<sheet name="\#(name)" sheetId="\#(index + 1)" r:id="rId\#(index + 1)"/>"#
    }
    var definedNames = ""
    if !workbook.namedRanges.isEmpty {
      let items = workbook.namedRanges.values.sorted { $0.name.uppercased() < $1.name.uppercased() }
      let body = items.map { named -> String in
        let sheetRef = escapeXML(named.sheetName.replacingOccurrences(of: "'", with: "''"))
        let start = CellAddress(row: named.startRow, col: named.startCol).a1
        let end = CellAddress(row: named.endRow, col: named.endCol).a1
        let formula = "'\(sheetRef)'!\(start):\(end)"
        return #"<definedName name="\#(escapeXML(named.name))">\#(escapeXML(formula))</definedName>"#
      }.joined()
      definedNames = "<definedNames>\(body)</definedNames>"
    }
    let xml = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
    <sheets>\(sheetsXML)</sheets>
    \(definedNames)
    </workbook>
    """
    return Data(xml.utf8)
  }

  private static func workbookRelsXML(sheetCount: Int) -> Data {
    var rels = ""
    for i in 1...sheetCount {
      rels += """
      <Relationship Id="rId\(i)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet\(i).xml"/>
      """
    }
    let stylesId = sheetCount + 1
    let sharedId = sheetCount + 2
    rels += """
    <Relationship Id="rId\(stylesId)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
    <Relationship Id="rId\(sharedId)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>
    """
    let xml = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    \(rels)
    </Relationships>
    """
    return Data(xml.utf8)
  }

  private static func worksheetXML(
    _ sheet: Sheet,
    intern: (String) -> Int,
    styleIndex: (CellFormat?) -> Int
  ) -> Data {
    var colsXML = ""
    if !sheet.columnWidths.isEmpty {
      let items = sheet.columnWidths.keys.sorted().map { col -> String in
        let width = (sheet.columnWidths[col] ?? Workbook.defaultColumnWidth) / 7
        return #"<col min="\#(col + 1)" max="\#(col + 1)" width="\#(width)" customWidth="1"/>"#
      }.joined()
      colsXML = "<cols>\(items)</cols>"
    }

    let grouped = Dictionary(grouping: sheet.cells.keys, by: \.row)
    let rowNumbers = grouped.keys.sorted()
    var sheetData = ""
    for row in rowNumbers {
      let heightAttr: String
      if let height = sheet.rowHeights[row] {
        heightAttr = #" ht="\#(height)" customHeight="1""#
      } else {
        heightAttr = ""
      }
      let addresses = (grouped[row] ?? []).sorted()
      var cellsXML = ""
      for address in addresses {
        let cell = sheet.cell(at: address)
        let sIndex = styleIndex(cell.format)
        let styleAttr = sIndex > 0 ? #" s="\#(sIndex)""# : ""
        if FormulaSyntax.isFormula(cell.raw) {
          let formula = String(cell.raw.drop(while: { $0 == "=" || $0.isWhitespace }))
          cellsXML += #"<c r="\#(address.a1)"\#(styleAttr)><f>\#(escapeXML(formula))</f></c>"#
        } else if Double(cell.raw) != nil, !cell.raw.contains(where: { $0.isLetter }) {
          cellsXML += #"<c r="\#(address.a1)"\#(styleAttr)><v>\#(escapeXML(cell.raw))</v></c>"#
        } else if !cell.raw.isEmpty {
          let idx = intern(cell.raw)
          cellsXML += #"<c r="\#(address.a1)"\#(styleAttr) t="s"><v>\#(idx)</v></c>"#
        } else if cell.format != nil {
          cellsXML += #"<c r="\#(address.a1)"\#(styleAttr)/>"#
        }
      }
      sheetData += #"<row r="\#(row + 1)"\#(heightAttr)>\#(cellsXML)</row>"#
    }

    let xml = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
    \(colsXML)
    <sheetData>\(sheetData)</sheetData>
    </worksheet>
    """
    return Data(xml.utf8)
  }

  private static func sharedStringsXML(_ strings: [String]) -> Data {
    let items = strings.map { #"<si><t>\#(escapeXML($0))</t></si>"# }.joined()
    let xml = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="\(strings.count)" uniqueCount="\(strings.count)">
    \(items)
    </sst>
    """
    return Data(xml.utf8)
  }

  private static func stylesXML(_ styles: [StyleKey]) -> Data {
    var fonts = ""
    var fills = #"<fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>"#
    var bordersXML = #"<border><left/><right/><top/><bottom/><diagonal/></border>"#
    var cellXfs = ""
    var fillCount = 2
    var borderCount = 1
    var borderIndexByKey: [StyleBorderKey: Int] = [.none: 0]

    for (fontId, style) in styles.enumerated() {
      let bold = style.bold ? "<b/>" : ""
      let italic = style.italic ? "<i/>" : ""
      let underline = style.underline ? #"<u val="single"/>"# : ""
      let strike = style.strikethrough ? "<strike/>" : ""
      let size = style.fontSize.map { #"<sz val="\#($0)"/>"# } ?? #"<sz val="12"/>"#
      let name = #"<name val="\#(escapeXML(style.fontFamily ?? "Helvetica Neue"))"/>"#
      let color = style.textRGB.map { #"<color rgb="FF\#($0)"/>"# } ?? ""
      fonts += "<font>\(bold)\(italic)\(underline)\(strike)\(size)\(color)\(name)</font>"

      var fillId = 0
      if let fillRGB = style.fillRGB {
        fills += #"<fill><patternFill patternType="solid"><fgColor rgb="FF\#(fillRGB)"/><bgColor indexed="64"/></patternFill></fill>"#
        fillId = fillCount
        fillCount += 1
      }

      let borderId: Int
      if let existing = borderIndexByKey[style.borders] {
        borderId = existing
      } else {
        bordersXML += style.borders.xml
        borderId = borderCount
        borderIndexByKey[style.borders] = borderId
        borderCount += 1
      }

      let numFmtId: Int
      switch style.numberFormat {
      case .general: numFmtId = 0
      case .number: numFmtId = 2
      case .currency: numFmtId = 164
      case .percent: numFmtId = 10
      case .scientific: numFmtId = 11
      case .date: numFmtId = 14
      case .time: numFmtId = 21
      }

      let alignmentXML = style.alignmentXML
      let applyBorder = borderId == 0 ? "0" : "1"
      let applyAlignment = alignmentXML.isEmpty ? "0" : "1"
      cellXfs += #"<xf numFmtId="\#(numFmtId)" fontId="\#(fontId)" fillId="\#(fillId)" borderId="\#(borderId)" xfId="0" applyFont="1" applyFill="1" applyBorder="\#(applyBorder)" applyAlignment="\#(applyAlignment)" applyNumberFormat="1">\#(alignmentXML)</xf>"#
    }

    let xml = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
    <numFmts count="1"><numFmt numFmtId="164" formatCode="$#,##0.00"/></numFmts>
    <fonts count="\(styles.count)">\(fonts)</fonts>
    <fills count="\(fillCount)">\(fills)</fills>
    <borders count="\(borderCount)">\(bordersXML)</borders>
    <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
    <cellXfs count="\(styles.count)">\(cellXfs)</cellXfs>
    </styleSheet>
    """
    return Data(xml.utf8)
  }

  private static func escapeXML(_ string: String) -> String {
    string
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "'", with: "&apos;")
  }
}

// MARK: - Style key

private struct StyleBorderEdgeKey: Hashable {
  var style: String
  var rgb: String?

  init?(_ edge: BorderEdge?) {
    guard let edge else { return nil }
    style = edge.style.rawValue
    rgb = edge.color.map(StyleKey.rgbHex)
  }
}

private struct StyleBorderKey: Hashable {
  var top: StyleBorderEdgeKey?
  var bottom: StyleBorderEdgeKey?
  var left: StyleBorderEdgeKey?
  var right: StyleBorderEdgeKey?

  static let none = StyleBorderKey()

  init(_ borders: CellBorders = .none) {
    top = StyleBorderEdgeKey(borders.top)
    bottom = StyleBorderEdgeKey(borders.bottom)
    left = StyleBorderEdgeKey(borders.left)
    right = StyleBorderEdgeKey(borders.right)
  }

  var xml: String {
    func side(_ name: String, _ edge: StyleBorderEdgeKey?) -> String {
      guard let edge else { return "<\(name)/>" }
      if let rgb = edge.rgb {
        return #"<\#(name) style="\#(edge.style)"><color rgb="FF\#(rgb)"/></\#(name)>"#
      }
      return #"<\#(name) style="\#(edge.style)"/>"#
    }
    return "<border>\(side("left", left))\(side("right", right))\(side("top", top))\(side("bottom", bottom))<diagonal/></border>"
  }
}

private struct StyleKey: Hashable {
  var bold = false
  var italic = false
  var underline = false
  var strikethrough = false
  var fontFamily: String?
  var fontSize: Double?
  var textRGB: String?
  var fillRGB: String?
  var numberFormat: CellFormat.NumberFormat = .general
  var borders = StyleBorderKey.none
  var horizontalAlign: CellFormat.HorizontalAlign = .general
  var verticalAlign: CellFormat.VerticalAlign = .bottom
  var wrapText = false
  var textRotation = 0

  static let `default` = StyleKey()

  init(format: CellFormat? = nil) {
    guard let format else { return }
    bold = format.bold
    italic = format.italic
    underline = format.underline
    strikethrough = format.strikethrough
    fontFamily = format.fontFamily
    fontSize = format.fontSize.map(Double.init)
    textRGB = format.textColor.map(Self.rgbHex)
    fillRGB = format.fillColor.map(Self.rgbHex)
    numberFormat = format.numberFormat
    borders = StyleBorderKey(format.borders)
    horizontalAlign = format.horizontalAlign
    verticalAlign = format.verticalAlign
    wrapText = format.wrapText
    textRotation = format.textRotation
  }

  var alignmentXML: String {
    var attrs: [String] = []
    switch horizontalAlign {
    case .general: break
    case .left: attrs.append(#"horizontal="left""#)
    case .center: attrs.append(#"horizontal="center""#)
    case .right: attrs.append(#"horizontal="right""#)
    }
    switch verticalAlign {
    case .bottom: break
    case .top: attrs.append(#"vertical="top""#)
    case .middle: attrs.append(#"vertical="center""#)
    }
    if wrapText { attrs.append(#"wrapText="1""#) }
    if textRotation != 0 { attrs.append(#"textRotation="\#(textRotation)""#) }
    guard !attrs.isEmpty else { return "" }
    return "<alignment \(attrs.joined(separator: " "))/>"
  }

  static func rgbHex(_ color: CodableColor) -> String {
    let r = Int((color.red * 255).rounded())
    let g = Int((color.green * 255).rounded())
    let b = Int((color.blue * 255).rounded())
    return String(format: "%02X%02X%02X", r, g, b)
  }
}

// MARK: - Minimal stored ZIP (Excel accepts method 0)

private enum MinimalZip {
  static func archive(files: [String: Data]) -> Data? {
    var central = Data()
    var local = Data()
    var offset: UInt32 = 0

    for path in files.keys.sorted() {
      guard let payload = files[path] else { continue }
      let nameData = Data(path.utf8)
      let crc = crc32(payload)
      let size = UInt32(payload.count)

      var localHeader = Data()
      localHeader.appendUInt32(0x0403_4b50)
      localHeader.appendUInt16(20)
      localHeader.appendUInt16(0)
      localHeader.appendUInt16(0) // stored
      localHeader.appendUInt16(0)
      localHeader.appendUInt16(0)
      localHeader.appendUInt32(crc)
      localHeader.appendUInt32(size)
      localHeader.appendUInt32(size)
      localHeader.appendUInt16(UInt16(nameData.count))
      localHeader.appendUInt16(0)
      localHeader.append(nameData)
      localHeader.append(payload)

      var centralHeader = Data()
      centralHeader.appendUInt32(0x0201_4b50)
      centralHeader.appendUInt16(20)
      centralHeader.appendUInt16(20)
      centralHeader.appendUInt16(0)
      centralHeader.appendUInt16(0)
      centralHeader.appendUInt16(0)
      centralHeader.appendUInt16(0)
      centralHeader.appendUInt32(crc)
      centralHeader.appendUInt32(size)
      centralHeader.appendUInt32(size)
      centralHeader.appendUInt16(UInt16(nameData.count))
      centralHeader.appendUInt16(0)
      centralHeader.appendUInt16(0)
      centralHeader.appendUInt16(0)
      centralHeader.appendUInt16(0)
      centralHeader.appendUInt32(0)
      centralHeader.appendUInt32(offset)
      centralHeader.append(nameData)

      local.append(localHeader)
      central.append(centralHeader)
      offset += UInt32(localHeader.count)
    }

    var end = Data()
    end.appendUInt32(0x0605_4b50)
    end.appendUInt16(0)
    end.appendUInt16(0)
    end.appendUInt16(UInt16(files.count))
    end.appendUInt16(UInt16(files.count))
    end.appendUInt32(UInt32(central.count))
    end.appendUInt32(UInt32(local.count))
    end.appendUInt16(0)

    return local + central + end
  }

  private static func crc32(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0xFFFF_FFFF
    for byte in data {
      let index = Int((crc ^ UInt32(byte)) & 0xFF)
      crc = (crc >> 8) ^ crcTable[index]
    }
    return crc ^ 0xFFFF_FFFF
  }

  private static let crcTable: [UInt32] = {
    (0..<256).map { i -> UInt32 in
      var c = UInt32(i)
      for _ in 0..<8 {
        c = (c & 1) != 0 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1)
      }
      return c
    }
  }()
}

private extension Data {
  mutating func appendUInt16(_ value: UInt16) {
    var le = value.littleEndian
    Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
  }

  mutating func appendUInt32(_ value: UInt32) {
    var le = value.littleEndian
    Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
  }
}
