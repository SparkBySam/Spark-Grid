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
    let themeScheme = importThemeScheme(archiveData: archiveData)
    let themeStyleColors = importThemeStyleColors(archiveData: archiveData, scheme: themeScheme)
    let dxfs = importDifferentialFormats(archiveData: archiveData, themeScheme: themeScheme)
    let underlinedFonts = underlinedFontIndices(archiveData: archiveData)
    let textRotationsByStyleIndex = importTextRotationsByStyleIndex(archiveData: archiveData)
    let clipTextStyleIndexes = importClipTextStyleIndexes(archiveData: archiveData)
    var sheets: [Sheet] = []

    for wbk in try file.parseWorkbooks() {
      for (name, path) in try file.parseWorksheetPathsAndNames(workbook: wbk) {
        let worksheet = try file.parseWorksheet(at: path)
        var sheet = Sheet(name: name ?? "Sheet\(sheets.count + 1)")
        importCells(
          from: worksheet,
          into: &sheet,
          sharedStrings: sharedStrings,
          styles: styles,
          underlinedFontIds: underlinedFonts,
          themeStyleColors: themeStyleColors,
          textRotationsByStyleIndex: textRotationsByStyleIndex,
          clipTextStyleIndexes: clipTextStyleIndexes
        )
        expandSharedFormulas(into: &sheet, archiveData: archiveData, worksheetPath: path)
        importFormulaCachedValues(
          into: &sheet,
          archiveData: archiveData,
          worksheetPath: path,
          sharedStrings: sharedStrings
        )
        importColumnWidths(from: worksheet, into: &sheet)
        importRowHeights(from: worksheet, into: &sheet)
        importFreezePanes(from: worksheet, into: &sheet)
        importMergeCells(from: worksheet, into: &sheet)
        importAutoFilter(into: &sheet, archiveData: archiveData, worksheetPath: path)
        importConditionalFormatting(
          into: &sheet,
          archiveData: archiveData,
          worksheetPath: path,
          dxfs: dxfs,
          themeScheme: themeScheme
        )
        importSparkCharts(into: &sheet, archiveData: archiveData, sheetIndex: sheets.count)
        importSheetImages(
          into: &sheet,
          archiveData: archiveData,
          sheetIndex: sheets.count,
          worksheetPath: path
        )
        sheets.append(sheet)
      }
    }

    guard !sheets.isEmpty else { throw CodecError.emptyWorkbook }
    return Workbook(
      sheets: sheets,
      activeSheetIndex: 0,
      namedRanges: importDefinedNames(archiveData: archiveData, sheets: sheets),
      xlsxThemeData: zipEntryData(archiveData: archiveData, entryPath: "xl/theme/theme1.xml")
    )
  }

  /// CoreXLSX does not expose `definedNames`. Read them from workbook XML the same way shared formulas are read from sheet XML.
  private static func importDefinedNames(archiveData: Data, sheets: [Sheet]) -> [String: NamedRange] {
    guard let xml = zipEntryString(archiveData: archiveData, entryPath: "xl/workbook.xml"),
          let blockStart = xml.range(of: "<definedNames"),
          let blockEnd = xml.range(of: "</definedNames>", range: blockStart.upperBound..<xml.endIndex)
    else { return [:] }
    let section = String(xml[blockStart.lowerBound..<blockEnd.upperBound])
    guard let regex = try? NSRegularExpression(
      pattern: #"<(?:[\w]+:)?definedName\b([^>]*)>([\s\S]*?)</(?:[\w]+:)?definedName>"#
    ) else { return [:] }

    struct RawName {
      var name: String
      var formula: String
      var localSheet: String?
    }

    let nsSection = section as NSString
    var globals: [RawName] = []
    var locals: [RawName] = []
    for match in regex.matches(in: section, range: NSRange(location: 0, length: nsSection.length)) {
      guard match.numberOfRanges > 2 else { continue }
      let attrs = nsSection.substring(with: match.range(at: 1))
      let body = decodeXMLEntities(nsSection.substring(with: match.range(at: 2)))
      guard let rawName = xmlAttribute(attrs, named: "name")?.trimmingCharacters(in: .whitespacesAndNewlines),
            !rawName.isEmpty
      else { continue }
      let localSheet: String?
      if let local = xmlAttribute(attrs, named: "localSheetId"), let index = Int(local), sheets.indices.contains(index) {
        localSheet = sheets[index].name
      } else {
        localSheet = nil
      }
      let raw = RawName(name: rawName, formula: body, localSheet: localSheet)
      if localSheet == nil {
        globals.append(raw)
      } else {
        locals.append(raw)
      }
    }

    var named: [String: NamedRange] = [:]
    for raw in globals + locals {
      let key = raw.name.uppercased()
      if raw.localSheet != nil, named[key] != nil { continue }
      let formula = raw.formula.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !formula.isEmpty else { continue }
      named[key] = DefinedNameFormula.make(
        name: raw.name,
        formula: formula,
        sheets: sheets,
        localSheet: raw.localSheet
      )
    }
    return named
  }

  private static func xmlAttribute(_ attributes: String, named name: String) -> String? {
    let patterns = [
      #"\#(name)="([^"]*)""#,
      #"\#(name)='([^']*)'"#,
    ]
    for pattern in patterns {
      guard let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(
              in: attributes,
              range: NSRange(location: 0, length: (attributes as NSString).length)
            ),
            match.numberOfRanges > 1
      else { continue }
      return decodeXMLEntities((attributes as NSString).substring(with: match.range(at: 1)))
    }
    return nil
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

    forEachCellElement(in: xml) { attrs, body in
      guard let ref = xmlAttribute(attrs, named: "r")?.trimmingCharacters(in: .whitespacesAndNewlines),
            !ref.isEmpty,
            let address = address(fromA1: ref)
      else { return }

      guard let fTag = sharedFormulaTag(in: body) else { return }
      guard fTag.contains(#"t="shared""#) || fTag.contains("t='shared'") else { return }

      var si: Int?
      if let siMatch = fTag.range(of: #"si="\d+""#, options: .regularExpression) {
        si = Int(String(fTag[siMatch]).filter(\.isNumber))
      } else if let siMatch = fTag.range(of: #"si='\d+'"#, options: .regularExpression) {
        si = Int(String(fTag[siMatch]).filter(\.isNumber))
      }
      guard let sharedIndex = si else { return }

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
            return
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

  /// Linear scan for `<c …>` / `</c>` pairs. Regex over the whole worksheet XML backtracks catastrophically on large KPI sheets.
  private static func forEachCellElement(in xml: String, body: (String, String) -> Void) {
    var searchStart = xml.startIndex
    while searchStart < xml.endIndex {
      guard let open = xml.range(of: "<c", range: searchStart..<xml.endIndex) else { break }
      let afterTagName = open.upperBound
      guard afterTagName < xml.endIndex else { break }
      let boundary = xml[afterTagName]
      guard boundary == " " || boundary == ">" || boundary == "/" else {
        searchStart = open.upperBound
        continue
      }
      guard let openEnd = xml.range(of: ">", range: afterTagName..<xml.endIndex) else { break }
      let attrs = String(xml[open.upperBound..<openEnd.lowerBound])
      let openTag = String(xml[open.lowerBound..<openEnd.upperBound])
      if openTag.hasSuffix("/>") {
        body(attrs, "")
        searchStart = openEnd.upperBound
        continue
      }
      guard let close = xml.range(of: "</c>", range: openEnd.upperBound..<xml.endIndex) else { break }
      let cellBody = String(xml[openEnd.upperBound..<close.lowerBound])
      body(attrs, cellBody)
      searchStart = close.upperBound
    }
  }

  /// CoreXLSX often omits cached `<v>` on formula cells; read it from sheet XML (same scan as shared formulas).
  private static func importFormulaCachedValues(
    into sheet: inout Sheet,
    archiveData: Data,
    worksheetPath: String,
    sharedStrings: SharedStrings?
  ) {
    guard let xml = zipEntryString(archiveData: archiveData, entryPath: worksheetPath) else { return }
    forEachCellElement(in: xml) { attrs, body in
      guard body.contains("<f") else { return }
      guard let ref = xmlAttribute(attrs, named: "r")?.trimmingCharacters(in: .whitespacesAndNewlines),
            !ref.isEmpty,
            let address = address(fromA1: ref)
      else { return }
      guard let cached = formulaCachedValueFromCellXML(
        attrs: attrs,
        body: body,
        sharedStrings: sharedStrings
      ) else { return }
      var cell = sheet.cell(at: address)
      guard FormulaSyntax.isFormula(cell.raw) else { return }
      cell.importedFormulaResult = cached
      sheet.setCell(cell, at: address)
    }
  }

  private static func formulaCachedValueFromCellXML(
    attrs: String,
    body: String,
    sharedStrings: SharedStrings?
  ) -> String? {
    guard let vOpen = body.range(of: "<v>"),
          let vClose = body.range(of: "</v>", range: vOpen.upperBound..<body.endIndex)
    else { return nil }
    let raw = decodeXMLEntities(String(body[vOpen.upperBound..<vClose.lowerBound]))
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !raw.isEmpty else { return nil }
    let cellType = xmlAttribute(attrs, named: "t")?.trimmingCharacters(in: .whitespacesAndNewlines)
    if cellType == "s" || cellType == "sharedString" {
      if let index = Int(raw), let text = sharedString(at: index, in: sharedStrings) {
        return text
      }
    }
    return raw
  }

  private static func sharedString(at index: Int, in table: SharedStrings?) -> String? {
    guard let table, index >= 0, index < table.items.count else { return nil }
    return table.items[index].text
  }

  private static func sharedFormulaTag(in cellBody: String) -> String? {
    var search = cellBody.startIndex
    while search < cellBody.endIndex {
      guard let fStart = cellBody.range(of: "<f", range: search..<cellBody.endIndex) else { break }
      let tail = cellBody[fStart.lowerBound...]
      let head = String(tail.prefix(240))
      guard head.contains(#"t="shared""#) || head.contains("t='shared'") else {
        search = fStart.upperBound
        continue
      }
      if let selfClose = tail.range(of: "/>") {
        return String(tail[..<selfClose.upperBound])
      }
      if let close = tail.range(of: "</f>") {
        return String(tail[..<close.upperBound])
      }
      return nil
    }
    return nil
  }

  static func zipEntryString(archiveData: Data, entryPath: String) -> String? {
    guard let data = zipEntryData(archiveData: archiveData, entryPath: entryPath) else { return nil }
    return String(data: data, encoding: .utf8)
  }

  /// Swap stored parts, then rebuild with the same stored-zip writer import already reads.
  static func replacingZipEntries(_ archiveData: Data, entries: [String: Data]) -> Data? {
    guard let archive = try? Archive(data: archiveData, accessMode: .read, pathEncoding: nil) else { return nil }
    var files: [String: Data] = [:]
    for entry in archive {
      let path = entry.path
      if path.hasSuffix("/") { continue }
      var data = Data()
      do {
        _ = try archive.extract(entry) { data.append($0) }
      } catch {
        return nil
      }
      files[path] = data
    }
    for (path, data) in entries {
      files[path] = data
    }
    return MinimalZip.archive(files: files)
  }

  static func zipEntryData(archiveData: Data, entryPath: String) -> Data? {
    let normalized = entryPath.hasPrefix("/") ? String(entryPath.dropFirst()) : entryPath
    guard let archive = try? Archive(data: archiveData, accessMode: .read, pathEncoding: nil) else { return nil }
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
      guard !data.isEmpty else { continue }
      return data
    }
    return nil
  }

  static func decodeXMLEntities(_ string: String) -> String {
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
    styles: Styles?,
    underlinedFontIds: Set<Int>,
    themeStyleColors: ThemeResolvedStyleColors,
    textRotationsByStyleIndex: [Int: Int],
    clipTextStyleIndexes: Set<Int>
  ) {
    for row in worksheet.data?.rows ?? [] {
      for cell in row.cells {
        guard let address = address(from: cell.reference) else { continue }
        let raw = cellRawValue(cell, sharedStrings: sharedStrings)
        guard !raw.isEmpty || cell.styleIndex != nil else { continue }
        var model = Cell(raw: raw)
        if let cached = importedFormulaResult(from: cell, sharedStrings: sharedStrings) {
          model.importedFormulaResult = cached
        }
        if let styles, let format = cellFormat(
          from: cell,
          styles: styles,
          underlinedFontIds: underlinedFontIds,
          themeStyleColors: themeStyleColors,
          textRotationsByStyleIndex: textRotationsByStyleIndex,
          clipTextStyleIndexes: clipTextStyleIndexes
        ) {
          model.format = format
        }
        sheet.setCell(model, at: address)
      }
    }
  }

  /// CoreXLSX omits `textRotation` on alignment — parse it from styles.xml cellXfs.
  static func importTextRotationsByStyleIndex(archiveData: Data) -> [Int: Int] {
    guard let xml = zipEntryString(archiveData: archiveData, entryPath: "xl/styles.xml") else { return [:] }
    guard let start = xml.range(of: "<cellXfs"),
          let end = xml.range(of: "</cellXfs>", range: start.upperBound..<xml.endIndex)
    else { return [:] }

    let section = String(xml[start.lowerBound..<end.upperBound])
    guard let xfRegex = try? NSRegularExpression(
      pattern: #"<xf\b[^>]*>(.*?)</xf>|<xf\b[^>]*/>"#,
      options: [.dotMatchesLineSeparators]
    ),
      let rotationRegex = try? NSRegularExpression(pattern: #"textRotation="(-?\d+)""#)
    else { return [:] }

    let nsSection = section as NSString
    var rotations: [Int: Int] = [:]
    for (index, match) in xfRegex.matches(
      in: section,
      options: [],
      range: NSRange(location: 0, length: nsSection.length)
    ).enumerated() {
      let chunk = nsSection.substring(with: match.range)
      let nsChunk = chunk as NSString
      guard let rotMatch = rotationRegex.firstMatch(
        in: chunk,
        options: [],
        range: NSRange(location: 0, length: nsChunk.length)
      ), rotMatch.numberOfRanges > 1,
        let rotation = Int(nsChunk.substring(with: rotMatch.range(at: 1)))
      else { continue }
      rotations[index] = rotation
    }
    return rotations
  }

  /// Clip is not an OOXML alignment flag. Spark Grid stores it beside wrapText so a round trip keeps it.
  static func importClipTextStyleIndexes(archiveData: Data) -> Set<Int> {
    guard let xml = zipEntryString(archiveData: archiveData, entryPath: "xl/styles.xml") else { return [] }
    guard let start = xml.range(of: "<cellXfs"),
          let end = xml.range(of: "</cellXfs>", range: start.upperBound..<xml.endIndex)
    else { return [] }

    let section = String(xml[start.lowerBound..<end.upperBound])
    guard let xfRegex = try? NSRegularExpression(
      pattern: #"<xf\b[^>]*>(.*?)</xf>|<xf\b[^>]*/>"#,
      options: [.dotMatchesLineSeparators]
    ),
      let clipRegex = try? NSRegularExpression(pattern: #"sparkTextDisplay="clip""#)
    else { return [] }

    let nsSection = section as NSString
    var indexes = Set<Int>()
    for (index, match) in xfRegex.matches(
      in: section,
      options: [],
      range: NSRange(location: 0, length: nsSection.length)
    ).enumerated() {
      let chunk = nsSection.substring(with: match.range)
      let nsChunk = chunk as NSString
      if clipRegex.firstMatch(
        in: chunk,
        options: [],
        range: NSRange(location: 0, length: nsChunk.length)
      ) != nil {
        indexes.insert(index)
      }
    }
    return indexes
  }

  private static func importedFormulaResult(
    from cell: CoreXLSX.Cell,
    sharedStrings: SharedStrings?
  ) -> String? {
    guard let formula = cell.formula?.value, !formula.isEmpty else { return nil }
    if cell.type == .sharedString, let sharedStrings, let text = cell.stringValue(sharedStrings) {
      return text
    }
    if let inline = cell.inlineString?.text, !inline.isEmpty {
      return inline
    }
    if let value = cell.value, !value.isEmpty {
      return value
    }
    return nil
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

  private static func cellFormat(
    from cell: CoreXLSX.Cell,
    styles: Styles,
    underlinedFontIds: Set<Int>,
    themeStyleColors: ThemeResolvedStyleColors,
    textRotationsByStyleIndex: [Int: Int],
    clipTextStyleIndexes: Set<Int>
  ) -> CellFormat? {
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

    if let fontId = cell.format(in: styles)?.fontId {
      if underlinedFontIds.contains(fontId) {
        format.underline = true
        changed = true
      }
      if format.textColor == nil, let themed = themeStyleColors.fontColorsById[fontId] {
        format.textColor = themed
        changed = true
      }
    }

    if let fillId = cell.format(in: styles)?.fillId,
       let fills = styles.fills?.items,
       fillId >= 0,
       fillId < fills.count
    {
      let pattern = fills[fillId].patternFill
      if pattern.patternType != "none" {
        if let color = codableColor(from: pattern.foregroundColor ?? pattern.backgroundColor) {
          format.fillColor = color
          changed = true
        } else if let themed = themeStyleColors.fillColorsById[fillId] {
          format.fillColor = themed
          changed = true
        }
      }
    }

    if let xf = cell.format(in: styles) {
      if let mapped = importedNumberFormat(for: xf.numberFormatId, styles: styles) {
        // Prefer explicit number formats even when applyNumberFormat is omitted (common in Excel exports).
        format.numberFormat = mapped.kind
        format.formatCode = mapped.code
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

    if let styleIndex = cell.styleIndex {
      if format.textColor == nil, let themed = themeStyleColors.fontColorsByCellXfId[styleIndex] {
        format.textColor = themed
        changed = true
      }
      if format.fillColor == nil, let themed = themeStyleColors.fillColorsByCellXfId[styleIndex] {
        format.fillColor = themed
        changed = true
      }
      if let rotation = textRotationsByStyleIndex[styleIndex] {
        format.textRotation = rotation
        changed = true
      }
      if clipTextStyleIndexes.contains(styleIndex), !format.wrapText {
        format.textDisplay = .clip
        changed = true
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

  private struct ImportedNumberFormat {
    var kind: CellFormat.NumberFormat
    var code: String
  }

  /// Built-in ECMA-376 format ids. The code is what the cell actually displays.
  private static let builtinNumberFormatCodes: [Int: String] = [
    1: "0",
    2: "0.00",
    3: "#,##0",
    4: "#,##0.00",
    5: "$#,##0_);($#,##0)",
    6: "$#,##0_);[Red]($#,##0)",
    7: "$#,##0.00_);($#,##0.00)",
    8: "$#,##0.00_);[Red]($#,##0.00)",
    9: "0%",
    10: "0.00%",
    11: "0.00E+00",
    14: "m/d/yyyy",
    15: "d-mmm-yy",
    16: "d-mmm",
    17: "mmm-yy",
    18: "h:mm AM/PM",
    19: "h:mm:ss AM/PM",
    20: "h:mm",
    21: "h:mm:ss",
    22: "m/d/yyyy h:mm",
    37: "#,##0_);(#,##0)",
    38: "#,##0_);[Red](#,##0)",
    39: "#,##0.00_);(#,##0.00)",
    40: "#,##0.00_);[Red](#,##0.00)",
    45: "mm:ss",
    46: "[h]:mm:ss",
    48: "##0.0E+0",
    49: "@",
  ]

  private static func builtinNumberFormatID(matching code: String) -> Int? {
    let target = code.trimmingCharacters(in: .whitespacesAndNewlines)
    return builtinNumberFormatCodes.first { $0.value.caseInsensitiveCompare(target) == .orderedSame }?.key
  }

  private static func importedNumberFormat(for id: Int, styles: Styles) -> ImportedNumberFormat? {
    if let raw = styles.numberFormats?.items.first(where: { $0.id == id })?.formatCode {
      let code = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      if code.isEmpty || code.caseInsensitiveCompare("General") == .orderedSame { return nil }
      return ImportedNumberFormat(kind: classifyNumberFormat(code), code: code)
    }
    guard let code = builtinNumberFormatCodes[id] else { return nil }
    return ImportedNumberFormat(kind: classifyNumberFormat(code), code: code)
  }

  private static func classifyNumberFormat(_ code: String) -> CellFormat.NumberFormat {
    ExcelFormatCode.numberFormatKind(for: code)
  }

  private static func codableColor(from color: Color?) -> CodableColor? {
    if let rgb = color?.rgb, rgb.count >= 6 {
      let hex = rgb.count == 8 ? String(rgb.suffix(6)) : rgb
      guard let value = UInt32(hex, radix: 16) else { return nil }
      let r = Double((value >> 16) & 0xFF) / 255
      let g = Double((value >> 8) & 0xFF) / 255
      let b = Double(value & 0xFF) / 255
      return CodableColor(red: r, green: g, blue: b, alpha: 1)
    }
    if let indexed = color?.indexed, let rgb = indexedColorRGB(indexed) {
      return CodableColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
    }
    return nil
  }

  /// Standard ECMA-376 indexed color palette (subset; unknown indexes fall back to black/white).
  private static func indexedColorRGB(_ index: Int) -> (Double, Double, Double)? {
    let palette: [(Double, Double, Double)] = [
      (0, 0, 0), (1, 1, 1), (1, 0, 0), (0, 1, 0), (0, 0, 1), (1, 1, 0), (1, 0, 1), (0, 1, 1),
      (0, 0, 0), (1, 1, 1), (1, 0, 0), (0, 1, 0), (0, 0, 1), (1, 1, 0), (1, 0, 1), (0, 1, 1),
      (0.5, 0, 0), (0, 0.5, 0), (0, 0, 0.5), (0.5, 0.5, 0), (0.5, 0, 0.5), (0, 0.5, 0.5),
      (0.75, 0.75, 0.75), (0.5, 0.5, 0.5),
      (0.6, 0.8, 1), (0.6, 0.6, 1), (0.8, 0.6, 1), (1, 0.6, 1), (1, 0.6, 0.8), (1, 0.6, 0.6),
      (1, 0.8, 0.6), (1, 1, 0.6), (0.8, 1, 0.6), (0.6, 1, 0.6), (0.6, 1, 0.8), (0.6, 1, 1),
      (0, 0, 0.5), (0.4, 0, 0.6), (0.6, 0, 0.6), (0.6, 0, 0.4), (0.6, 0, 0), (0.6, 0.4, 0),
      (0.4, 0.6, 0), (0, 0.6, 0), (0, 0.6, 0.4), (0, 0.6, 0.6), (0, 0.4, 0.6), (0, 0, 0.6),
      (0.2, 0.2, 0.4), (0.4, 0.2, 0.6), (0.6, 0.2, 0.6), (0.6, 0.2, 0.4), (0.6, 0.2, 0.2),
      (0.6, 0.4, 0.2), (0.4, 0.6, 0.2), (0.2, 0.6, 0.2), (0.2, 0.6, 0.4), (0.2, 0.6, 0.6),
      (0.2, 0.4, 0.6), (0.2, 0.2, 0.6), (0.4, 0.4, 0.6), (0.6, 0.4, 0.6), (0.6, 0.4, 0.4),
    ]
    if index == 64 || index == 65 { return (0, 0, 0) }
    guard index >= 0, index < palette.count else { return nil }
    return palette[index]
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

    var dxfCatalog: [ConditionalFormatStyle: Int] = [:]
    var dxfList: [ConditionalFormatStyle] = []
    func dxfIndex(for style: ConditionalFormatStyle) -> Int {
      if let existing = dxfCatalog[style] { return existing }
      let index = dxfList.count
      dxfList.append(style)
      dxfCatalog[style] = index
      return index
    }

    var files: [String: Data] = [:]
    var sheetsWithDrawings = Set<Int>()
    var globalImageIndex = 0
    for (index, sheet) in workbook.sheets.enumerated() {
      if appendSheetDrawingParts(
        for: sheet,
        sheetIndex: index,
        globalImageIndex: &globalImageIndex,
        into: &files
      ) {
        sheetsWithDrawings.insert(index)
      }
    }
    files["[Content_Types].xml"] = contentTypesXML(
      sheetCount: workbook.sheets.count,
      drawingOverrides: drawingContentTypeOverrides(workbook: workbook),
      imageDefaults: imageContentTypeDefaults(workbook: workbook),
      includeTheme: workbook.xlsxThemeData != nil
    )
    files["_rels/.rels"] = rootRelsXML
    files["xl/workbook.xml"] = workbookXML(workbook)
    files["xl/_rels/workbook.xml.rels"] = workbookRelsXML(
      sheetCount: workbook.sheets.count,
      includeTheme: workbook.xlsxThemeData != nil
    )

    for (index, sheet) in workbook.sheets.enumerated() {
      let hasDrawing = sheetsWithDrawings.contains(index)
      let sheetXML = worksheetXML(
        sheet,
        intern: intern,
        styleIndex: styleIndex,
        dxfIndex: dxfIndex,
        includeDrawing: hasDrawing
      )
      files["xl/worksheets/sheet\(index + 1).xml"] = sheetXML
      if let rels = worksheetRelsXML(sheetIndex: index, hasDrawing: hasDrawing) {
        files["xl/worksheets/_rels/sheet\(index + 1).xml.rels"] = rels
      }
      if let chartsData = sparkChartsJSON(sheet.charts) {
        files["xl/sparkGrid/charts\(index + 1).json"] = chartsData
      }
    }

    files["xl/sharedStrings.xml"] = sharedStringsXML(sharedStrings)
    files["xl/styles.xml"] = stylesXML(styleList, dxfs: dxfList)
    if let themeData = workbook.xlsxThemeData {
      files["xl/theme/theme1.xml"] = themeData
    }

    guard let data = MinimalZip.archive(files: files) else {
      throw CodecError.writeFailed
    }
    return data
  }

  // MARK: - Export XML builders

  private static func contentTypesXML(
    sheetCount: Int,
    drawingOverrides: String = "",
    imageDefaults: String = "",
    includeTheme: Bool = false
  ) -> Data {
    var overrides = """
    <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
    <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
    <Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>
    """
    if includeTheme {
      overrides += """
      <Override PartName="/xl/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>
      """
    }
    for i in 1...sheetCount {
      overrides += """
      <Override PartName="/xl/worksheets/sheet\(i).xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
      """
    }
    overrides += drawingOverrides
    let xml = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
    \(imageDefaults)
    <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
    <Default Extension="xml" ContentType="application/xml"/>
    <Default Extension="json" ContentType="application/json"/>
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
        let formula = named.referenceText
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

  private static func workbookRelsXML(sheetCount: Int, includeTheme: Bool = false) -> Data {
    var rels = ""
    for i in 1...sheetCount {
      rels += """
      <Relationship Id="rId\(i)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet\(i).xml"/>
      """
    }
    let stylesId = sheetCount + 1
    let sharedId = sheetCount + 2
    let themeId = sheetCount + 3
    rels += """
    <Relationship Id="rId\(stylesId)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
    <Relationship Id="rId\(sharedId)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>
    """
    if includeTheme {
      rels += """
      <Relationship Id="rId\(themeId)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="theme/theme1.xml"/>
      """
    }
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
    styleIndex: (CellFormat?) -> Int,
    dxfIndex: (ConditionalFormatStyle) -> Int,
    includeDrawing: Bool = false
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

    let viewsXML = sheetViewsXML(frozenRows: sheet.frozenRows, frozenColumns: sheet.frozenColumns)
    // ECMA-376 order: sheetData → autoFilter → mergeCells → conditionalFormatting → drawing
    let filterXML = autoFilterXML(sheet.autoFilter)
    let mergeXML = mergeCellsXML(sheet.mergedRanges)
    let cfXML = conditionalFormattingXML(sheet.conditionalFormats, dxfIndex: dxfIndex)
    let x14cfXML = x14ConditionalFormattingXML(sheet.conditionalFormats)
    let drawingXML = includeDrawing ? sheetDrawingRelationshipXML(sheetIndex: 0) : ""

    let xml = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
    \(viewsXML)
    \(colsXML)
    <sheetData>\(sheetData)</sheetData>
    \(filterXML)
    \(mergeXML)
    \(cfXML)
    \(drawingXML)
    \(x14cfXML)
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

  private static func stylesXML(_ styles: [StyleKey], dxfs: [ConditionalFormatStyle] = []) -> Data {
    var customFormats: [String: Int] = [:]
    var nextCustomID = 164
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

      let numFmtId = numberFormatID(for: style, customFormats: &customFormats, nextCustomID: &nextCustomID)

      let alignmentXML = style.alignmentXML
      let applyBorder = borderId == 0 ? "0" : "1"
      let applyAlignment = alignmentXML.isEmpty ? "0" : "1"
      cellXfs += #"<xf numFmtId="\#(numFmtId)" fontId="\#(fontId)" fillId="\#(fillId)" borderId="\#(borderId)" xfId="0" applyFont="1" applyFill="1" applyBorder="\#(applyBorder)" applyAlignment="\#(applyAlignment)" applyNumberFormat="1">\#(alignmentXML)</xf>"#
    }

    let numFmts = customFormats
      .sorted { $0.value < $1.value }
      .map { #" <numFmt numFmtId="\#($0.value)" formatCode="\#(escapeXML($0.key))"/>"# }
      .joined()
    let xml = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
    <numFmts count="\(customFormats.count)">\(numFmts)</numFmts>
    <fonts count="\(styles.count)">\(fonts)</fonts>
    <fills count="\(fillCount)">\(fills)</fills>
    <borders count="\(borderCount)">\(bordersXML)</borders>
    <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
    <cellXfs count="\(styles.count)">\(cellXfs)</cellXfs>
    <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
    \(dxfsXML(dxfs))
    <tableStyles count="0" defaultTableStyle="TableStyleMedium9" defaultPivotStyle="PivotStyleLight16"/>
    </styleSheet>
    """
    return Data(xml.utf8)
  }

  private static func numberFormatID(
    for style: StyleKey,
    customFormats: inout [String: Int],
    nextCustomID: inout Int
  ) -> Int {
    if let code = style.formatCode?.trimmingCharacters(in: .whitespacesAndNewlines),
       !code.isEmpty,
       code.caseInsensitiveCompare("General") != .orderedSame
    {
      if let builtin = builtinNumberFormatID(matching: code) { return builtin }
      if let existing = customFormats[code] { return existing }
      let id = nextCustomID
      nextCustomID += 1
      customFormats[code] = id
      return id
    }
    switch style.numberFormat {
    case .general: return 0
    case .number: return 2
    case .currency:
      let code = "$#,##0.00"
      if let existing = customFormats[code] { return existing }
      let id = nextCustomID
      nextCustomID += 1
      customFormats[code] = id
      return id
    case .percent: return 10
    case .scientific: return 11
    case .date: return 14
    case .time: return 21
    }
  }

  static func escapeXML(_ string: String) -> String {
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
  var formatCode: String?
  var borders = StyleBorderKey.none
  var horizontalAlign: CellFormat.HorizontalAlign = .general
  var verticalAlign: CellFormat.VerticalAlign = .bottom
  var wrapText = false
  var clipText = false
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
    formatCode = format.formatCode
    borders = StyleBorderKey(format.borders)
    horizontalAlign = format.horizontalAlign
    verticalAlign = format.verticalAlign
    wrapText = format.wrapText
    clipText = format.textDisplay == .clip
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
    if clipText { attrs.append(#"sparkTextDisplay="clip""#) }
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
