import CoreXLSX
import Foundation

extension XLSXCodec {
  // MARK: - Sheet extras (freeze, autofilter, CF, merges, theme) from / into worksheet XML

  static func importFreezePanes(from worksheet: Worksheet, into sheet: inout Sheet) {
    guard let pane = worksheet.sheetViews?.items.first?.pane else { return }
    let state = pane.state?.lowercased() ?? ""
    guard state == "frozen" || state == "frozensplit" else { return }
    if let y = pane.ySplit.flatMap(Double.init), y > 0 {
      sheet.frozenRows = Int(y.rounded(.down))
    }
    if let x = pane.xSplit.flatMap(Double.init), x > 0 {
      sheet.frozenColumns = Int(x.rounded(.down))
    }
  }

  static func importMergeCells(from worksheet: Worksheet, into sheet: inout Sheet) {
    for merge in worksheet.mergeCells?.items ?? [] {
      guard let range = parseCellRange(merge.reference) else { continue }
      sheet.mergedRanges.append(range)
    }
  }

  static func importThemeScheme(archiveData: Data) -> ThemeColorScheme {
    guard let xml = zipEntryString(archiveData: archiveData, entryPath: "xl/theme/theme1.xml")
    else { return ThemeColorScheme() }
    return ThemeColorScheme.parse(themeXML: xml)
  }

  static func importThemeStyleColors(
    archiveData: Data,
    scheme: ThemeColorScheme
  ) -> ThemeResolvedStyleColors {
    guard let xml = zipEntryString(archiveData: archiveData, entryPath: "xl/styles.xml")
    else { return ThemeResolvedStyleColors() }
    return ThemeColorLookup.parseStyleColors(stylesXML: xml, scheme: scheme)
  }

  static func importAutoFilter(into sheet: inout Sheet, archiveData: Data, worksheetPath: String) {
    guard let xml = zipEntryString(archiveData: archiveData, entryPath: worksheetPath) else { return }
    guard let blockRange = xml.range(
      of: #"<autoFilter\b[^>]*(?:/>|>[\s\S]*?</autoFilter>)"#,
      options: .regularExpression
    ) else { return }
    let block = String(xml[blockRange])
    guard let refRange = block.range(of: #"ref="[^"]+""#, options: .regularExpression) else { return }
    let quoted = String(block[refRange])
    guard let q1 = quoted.firstIndex(of: "\""),
          let q2 = quoted.lastIndex(of: "\""),
          q1 < q2
    else { return }
    let ref = String(quoted[quoted.index(after: q1)..<q2])
    guard let range = parseCellRange(ref) else { return }

    var selected: [Int: Set<String>] = [:]
    let colPattern = #"<filterColumn\b([^>]*)>(.*?)</filterColumn>"#
    if let colRegex = try? NSRegularExpression(pattern: colPattern, options: [.dotMatchesLineSeparators]) {
      let ns = block as NSString
      for match in colRegex.matches(in: block, range: NSRange(location: 0, length: ns.length)) {
        let attrs = ns.substring(with: match.range(at: 1))
        let body = ns.substring(with: match.range(at: 2))
        guard let colId = attributeValue(attrs, name: "colId").flatMap(Int.init) else { continue }
        let absoluteCol = range.normalized.minCol + colId
        var values = Set<String>()
        let filterPattern = #"<filter\b([^>]*)/?\s*>"#
        if let filterRegex = try? NSRegularExpression(pattern: filterPattern) {
          let bodyNS = body as NSString
          for fMatch in filterRegex.matches(in: body, range: NSRange(location: 0, length: bodyNS.length)) {
            let fAttrs = bodyNS.substring(with: fMatch.range(at: 1))
            if let val = attributeValue(fAttrs, name: "val") {
              values.insert(decodeXMLEntities(val))
            }
          }
        }
        if !values.isEmpty {
          selected[absoluteCol] = values
        }
      }
    }
    sheet.autoFilter = SheetFilterState(range: range, selectedValuesByColumn: selected)
  }

  static func importConditionalFormatting(
    into sheet: inout Sheet,
    archiveData: Data,
    worksheetPath: String,
    dxfs: [ConditionalFormatStyle],
    themeScheme: ThemeColorScheme
  ) {
    guard let xml = zipEntryString(archiveData: archiveData, entryPath: worksheetPath) else { return }
    let blockPattern = #"<conditionalFormatting\b([^>]*)>(.*?)</conditionalFormatting>"#
    guard let blockRegex = try? NSRegularExpression(
      pattern: blockPattern,
      options: [.dotMatchesLineSeparators]
    ) else { return }
    let nsxml = xml as NSString
    let full = NSRange(location: 0, length: nsxml.length)

    for match in blockRegex.matches(in: xml, options: [], range: full) {
      let attrs = nsxml.substring(with: match.range(at: 1))
      let body = nsxml.substring(with: match.range(at: 2))
      guard let sqref = attributeValue(attrs, name: "sqref"),
            let range = parseCellRange(sqref.split(separator: " ").first.map(String.init) ?? sqref)
      else { continue }

      let rulePattern = #"<cfRule\b([^>]*)>(.*?)</cfRule>|<cfRule\b([^>]*)/>"#
      guard let ruleRegex = try? NSRegularExpression(
        pattern: rulePattern,
        options: [.dotMatchesLineSeparators]
      ) else { continue }
      let bodyNS = body as NSString
      let bodyFull = NSRange(location: 0, length: bodyNS.length)

      for ruleMatch in ruleRegex.matches(in: body, options: [], range: bodyFull) {
        let ruleAttrs: String
        let ruleBody: String
        if ruleMatch.range(at: 1).location != NSNotFound {
          ruleAttrs = bodyNS.substring(with: ruleMatch.range(at: 1))
          ruleBody = bodyNS.substring(with: ruleMatch.range(at: 2))
        } else {
          ruleAttrs = bodyNS.substring(with: ruleMatch.range(at: 3))
          ruleBody = ""
        }

        let type = attributeValue(ruleAttrs, name: "type") ?? ""
        let stop = attributeValue(ruleAttrs, name: "stopIfTrue") != "0"
        let dxfId = attributeValue(ruleAttrs, name: "dxfId").flatMap(Int.init) ?? 0
        let style = (dxfId >= 0 && dxfId < dxfs.count) ? dxfs[dxfId] : .redFill
        let formulas = formulaValues(in: ruleBody)

        let predicate: ConditionalFormatPredicate?
        switch type {
        case "expression":
          guard let formula = formulas.first, !formula.isEmpty else { continue }
          predicate = .formula(formula.hasPrefix("=") ? formula : "=\(formula)")
        case "cellIs":
          let op = attributeValue(ruleAttrs, name: "operator") ?? ""
          predicate = cellIsPredicate(operator: op, formulas: formulas)
        case "containsText":
          if let text = attributeValue(ruleAttrs, name: "text") ?? formulas.first {
            predicate = .textContains(text)
          } else {
            predicate = nil
          }
        case "containsBlanks":
          predicate = .blanks
        case "notContainsBlanks":
          predicate = .nonBlanks
        case "colorScale":
          predicate = colorScalePredicate(in: ruleBody, themeScheme: themeScheme)
        default:
          predicate = nil
        }

        guard let predicate else { continue }
        let ruleStyle: ConditionalFormatStyle
        if case .colorScale = predicate {
          ruleStyle = ConditionalFormatStyle()
        } else {
          ruleStyle = style
        }
        sheet.conditionalFormats.append(
          ConditionalFormatRule(range: range, stopIfTrue: stop, predicate: predicate, style: ruleStyle)
        )
      }
    }
  }

  static func importDifferentialFormats(
    archiveData: Data,
    themeScheme: ThemeColorScheme
  ) -> [ConditionalFormatStyle] {
    guard let xml = zipEntryString(archiveData: archiveData, entryPath: "xl/styles.xml") else {
      return []
    }
    guard let dxfsRange = xml.range(of: #"<dxfs\b[^>]*>[\s\S]*?</dxfs>"#, options: .regularExpression)
    else { return [] }
    let dxfsXML = String(xml[dxfsRange])
    let dxfPattern = #"<dxf>(.*?)</dxf>"#
    guard let regex = try? NSRegularExpression(
      pattern: dxfPattern,
      options: [.dotMatchesLineSeparators]
    ) else { return [] }
    let ns = dxfsXML as NSString
    var styles: [ConditionalFormatStyle] = []
    for match in regex.matches(in: dxfsXML, options: [], range: NSRange(location: 0, length: ns.length)) {
      let body = ns.substring(with: match.range(at: 1))
      var style = ConditionalFormatStyle()
      if body.contains("<b") || body.contains("<b/>") || body.contains("<b ") {
        style.bold = true
      }
      if let fill = firstColor(in: body, near: "fgColor", themeScheme: themeScheme)
        ?? firstColor(in: body, near: "patternFill", themeScheme: themeScheme)
      {
        style.fillColor = fill
      }
      if let fontBlock = body.range(of: #"<font>[\s\S]*?</font>"#, options: .regularExpression) {
        if let text = firstColor(in: String(body[fontBlock]), near: "color", themeScheme: themeScheme) {
          style.textColor = text
        }
      }
      styles.append(style)
    }
    return styles
  }

  static func underlinedFontIndices(archiveData: Data) -> Set<Int> {
    guard let xml = zipEntryString(archiveData: archiveData, entryPath: "xl/styles.xml") else {
      return []
    }
    guard let fontsRange = xml.range(of: #"<fonts\b[^>]*>[\s\S]*?</fonts>"#, options: .regularExpression)
    else { return [] }
    let fontsXML = String(xml[fontsRange])
    let fontPattern = #"<font>(.*?)</font>"#
    guard let regex = try? NSRegularExpression(
      pattern: fontPattern,
      options: [.dotMatchesLineSeparators]
    ) else { return [] }
    let ns = fontsXML as NSString
    var underlined = Set<Int>()
    for (index, match) in regex.matches(
      in: fontsXML,
      options: [],
      range: NSRange(location: 0, length: ns.length)
    ).enumerated() {
      let body = ns.substring(with: match.range(at: 1))
      if body.contains("<u") {
        underlined.insert(index)
      }
    }
    return underlined
  }

  static func importSparkCharts(into sheet: inout Sheet, archiveData: Data, sheetIndex: Int) {
    let path = "xl/sparkGrid/charts\(sheetIndex + 1).json"
    guard let xml = zipEntryString(archiveData: archiveData, entryPath: path),
          let data = xml.data(using: .utf8),
          let charts = try? JSONDecoder().decode([SheetChart].self, from: data)
    else { return }
    sheet.charts = charts
  }

  static func sheetViewsXML(frozenRows: Int, frozenColumns: Int) -> String {
    guard frozenRows > 0 || frozenColumns > 0 else { return "" }
    let topLeft = CellAddress(row: frozenRows, col: frozenColumns).a1
    return """
    <sheetViews><sheetView workbookViewId="0"><pane xSplit="\(frozenColumns)" ySplit="\(frozenRows)" topLeftCell="\(topLeft)" activePane="bottomRight" state="frozen"/></sheetView></sheetViews>
    """
  }

  static func mergeCellsXML(_ ranges: [CellRange]) -> String {
    guard !ranges.isEmpty else { return "" }
    let items = ranges.map { range -> String in
      let n = range.normalized
      let start = CellAddress(row: n.minRow, col: n.minCol).a1
      let end = CellAddress(row: n.maxRow, col: n.maxCol).a1
      let ref = start == end ? start : "\(start):\(end)"
      return #"<mergeCell ref="\#(ref)"/>"#
    }.joined()
    return #"<mergeCells count="\#(ranges.count)">\#(items)</mergeCells>"#
  }

  static func autoFilterXML(_ filter: SheetFilterState?) -> String {
    guard let filter else { return "" }
    let n = filter.range.normalized
    let start = CellAddress(row: n.minRow, col: n.minCol).a1
    let end = CellAddress(row: n.maxRow, col: n.maxCol).a1
    let ref = start == end ? start : "\(start):\(end)"
    if filter.selectedValuesByColumn.isEmpty {
      return #"<autoFilter ref="\#(ref)"/>"#
    }
    var columnsXML = ""
    for col in n.minCol...n.maxCol {
      guard let values = filter.selectedValuesByColumn[col], !values.isEmpty else { continue }
      let colId = col - n.minCol
      let filters = values.sorted().map { #"<filter val="\#(escapeXML($0))"/>"# }.joined()
      columnsXML += #"<filterColumn colId="\#(colId)"><filters>\#(filters)</filters></filterColumn>"#
    }
    if columnsXML.isEmpty {
      return #"<autoFilter ref="\#(ref)"/>"#
    }
    return #"<autoFilter ref="\#(ref)">\#(columnsXML)</autoFilter>"#
  }

  static func conditionalFormattingXML(
    _ rules: [ConditionalFormatRule],
    dxfIndex: (ConditionalFormatStyle) -> Int
  ) -> String {
    guard !rules.isEmpty else { return "" }
    var grouped: [String: [(ConditionalFormatRule, Int)]] = [:]
    for (priority, rule) in rules.enumerated() {
      let n = rule.range.normalized
      let start = CellAddress(row: n.minRow, col: n.minCol).a1
      let end = CellAddress(row: n.maxRow, col: n.maxCol).a1
      let sqref = start == end ? start : "\(start):\(end)"
      grouped[sqref, default: []].append((rule, priority + 1))
    }

    var xml = ""
    for (sqref, items) in grouped.sorted(by: { $0.key < $1.key }) {
      xml += #"<conditionalFormatting sqref="\#(sqref)">"#
      for (rule, priority) in items {
        let stop = rule.stopIfTrue ? "" : #" stopIfTrue="0""#
        switch rule.predicate {
        case .greaterThan(let v):
          let dxfId = dxfIndex(rule.style)
          xml += #"<cfRule type="cellIs" dxfId="\#(dxfId)" priority="\#(priority)"\#(stop) operator="greaterThan"><formula>\#(escapeXML(stringFromNumber(v)))</formula></cfRule>"#
        case .lessThan(let v):
          let dxfId = dxfIndex(rule.style)
          xml += #"<cfRule type="cellIs" dxfId="\#(dxfId)" priority="\#(priority)"\#(stop) operator="lessThan"><formula>\#(escapeXML(stringFromNumber(v)))</formula></cfRule>"#
        case .greaterOrEqual(let v):
          let dxfId = dxfIndex(rule.style)
          xml += #"<cfRule type="cellIs" dxfId="\#(dxfId)" priority="\#(priority)"\#(stop) operator="greaterThanOrEqual"><formula>\#(escapeXML(stringFromNumber(v)))</formula></cfRule>"#
        case .lessOrEqual(let v):
          let dxfId = dxfIndex(rule.style)
          xml += #"<cfRule type="cellIs" dxfId="\#(dxfId)" priority="\#(priority)"\#(stop) operator="lessThanOrEqual"><formula>\#(escapeXML(stringFromNumber(v)))</formula></cfRule>"#
        case .equal(let v):
          let dxfId = dxfIndex(rule.style)
          xml += #"<cfRule type="cellIs" dxfId="\#(dxfId)" priority="\#(priority)"\#(stop) operator="equal"><formula>\#(escapeXML(stringFromNumber(v)))</formula></cfRule>"#
        case .between(let a, let b):
          let dxfId = dxfIndex(rule.style)
          xml += #"<cfRule type="cellIs" dxfId="\#(dxfId)" priority="\#(priority)"\#(stop) operator="between"><formula>\#(escapeXML(stringFromNumber(a)))</formula><formula>\#(escapeXML(stringFromNumber(b)))</formula></cfRule>"#
        case .textContains(let text):
          let dxfId = dxfIndex(rule.style)
          xml += #"<cfRule type="containsText" dxfId="\#(dxfId)" priority="\#(priority)"\#(stop) operator="containsText" text="\#(escapeXML(text))"><formula>NOT(ISERROR(SEARCH("\#(escapeXML(text))",A1)))</formula></cfRule>"#
        case .blanks:
          let dxfId = dxfIndex(rule.style)
          xml += #"<cfRule type="containsBlanks" dxfId="\#(dxfId)" priority="\#(priority)"\#(stop)/>"#
        case .nonBlanks:
          let dxfId = dxfIndex(rule.style)
          xml += #"<cfRule type="notContainsBlanks" dxfId="\#(dxfId)" priority="\#(priority)"\#(stop)/>"#
        case .formula(let raw):
          let dxfId = dxfIndex(rule.style)
          let formula = raw.hasPrefix("=") ? String(raw.dropFirst()) : raw
          xml += #"<cfRule type="expression" dxfId="\#(dxfId)" priority="\#(priority)"\#(stop)><formula>\#(escapeXML(formula))</formula></cfRule>"#
        case .colorScale(let stops):
          xml += #"<cfRule type="colorScale" priority="\#(priority)"\#(stop)><colorScale>"#
          for stop in stops {
            switch stop.type {
            case .min:
              xml += #"<cfvo type="min"/>"#
            case .max:
              xml += #"<cfvo type="max"/>"#
            case .number:
              xml += #"<cfvo type="num" val="\#(escapeXML(stringFromNumber(stop.value ?? 0)))"/>"#
            case .percent:
              xml += #"<cfvo type="percent" val="\#(escapeXML(stringFromNumber(stop.value ?? 0)))"/>"#
            case .percentile:
              xml += #"<cfvo type="percentile" val="\#(escapeXML(stringFromNumber(stop.value ?? 50)))"/>"#
            }
          }
          for stop in stops {
            xml += #"<color rgb="FF\#(rgbHex(stop.color))"/>"#
          }
          xml += "</colorScale></cfRule>"
        }
      }
      xml += "</conditionalFormatting>"
    }
    return xml
  }

  static func dxfsXML(_ dxfs: [ConditionalFormatStyle]) -> String {
    guard !dxfs.isEmpty else { return #"<dxfs count="0"/>"# }
    var body = ""
    for style in dxfs {
      var font = ""
      if style.bold == true { font += "<b/>" }
      if let rgb = style.textColor.map(rgbHex) {
        font += #"<color rgb="FF\#(rgb)"/>"#
      }
      let fontXML = font.isEmpty ? "" : "<font>\(font)</font>"
      var fillXML = ""
      if let rgb = style.fillColor.map(rgbHex) {
        fillXML = #"<fill><patternFill patternType="solid"><fgColor rgb="FF\#(rgb)"/></patternFill></fill>"#
      }
      body += "<dxf>\(fontXML)\(fillXML)</dxf>"
    }
    return #"<dxfs count="\#(dxfs.count)">\#(body)</dxfs>"#
  }

  static func sparkChartsJSON(_ charts: [SheetChart]) -> Data? {
    guard !charts.isEmpty else { return nil }
    return try? JSONEncoder().encode(charts)
  }

  private static func rgbHex(_ color: CodableColor) -> String {
    let r = Int((color.red * 255).rounded())
    let g = Int((color.green * 255).rounded())
    let b = Int((color.blue * 255).rounded())
    return String(format: "%02X%02X%02X", r, g, b)
  }

  // MARK: - Private helpers

  private static func colorScalePredicate(
    in body: String,
    themeScheme: ThemeColorScheme
  ) -> ConditionalFormatPredicate? {
    guard let scaleRange = body.range(of: #"<colorScale>[\s\S]*?</colorScale>"#, options: .regularExpression)
    else { return nil }
    let scale = String(body[scaleRange])
    let cfvoPattern = #"<cfvo\b([^>]*)/?\s*>"#
    let colorPattern = #"<color\b([^>]*)/?\s*>"#
    guard let cfvoRegex = try? NSRegularExpression(pattern: cfvoPattern),
          let colorRegex = try? NSRegularExpression(pattern: colorPattern)
    else { return nil }
    let ns = scale as NSString
    let full = NSRange(location: 0, length: ns.length)
    let cfvos = cfvoRegex.matches(in: scale, range: full).map { ns.substring(with: $0.range(at: 1)) }
    let colors = colorRegex.matches(in: scale, range: full).map { ns.substring(with: $0.range(at: 1)) }
    guard cfvos.count >= 2, colors.count == cfvos.count else { return nil }

    var stops: [ColorScaleStop] = []
    for (index, attrs) in cfvos.enumerated() {
      let typeRaw = attributeValue(attrs, name: "type") ?? "min"
      let type: ColorScaleStop.StopType
      switch typeRaw {
      case "min": type = .min
      case "max": type = .max
      case "num", "number": type = .number
      case "percent": type = .percent
      case "percentile": type = .percentile
      default: type = .number
      }
      let value = attributeValue(attrs, name: "val").flatMap(Double.init)
      let colorAttrs = colors[index]
      let color = ThemeColorLookup.resolve(fromAttributes: colorAttrs, scheme: themeScheme)
        ?? colorFromRGBHex(attributeValue(colorAttrs, name: "rgb") ?? "")
        ?? CodableColor(red: 0.99, green: 0.8, blue: 0.8, alpha: 1)
      stops.append(ColorScaleStop(type: type, value: value, color: color))
    }
    return .colorScale(stops)
  }

  private static func cellIsPredicate(operator op: String, formulas: [String]) -> ConditionalFormatPredicate? {
    let values = formulas.compactMap { Double($0.replacingOccurrences(of: ",", with: "")) }
    switch op {
    case "greaterThan":
      guard let v = values.first else { return nil }
      return .greaterThan(v)
    case "lessThan":
      guard let v = values.first else { return nil }
      return .lessThan(v)
    case "greaterThanOrEqual":
      guard let v = values.first else { return nil }
      return .greaterOrEqual(v)
    case "lessThanOrEqual":
      guard let v = values.first else { return nil }
      return .lessOrEqual(v)
    case "equal":
      guard let v = values.first else { return nil }
      return .equal(v)
    case "between":
      guard values.count >= 2 else { return nil }
      return .between(values[0], values[1])
    default:
      return nil
    }
  }

  private static func formulaValues(in body: String) -> [String] {
    let pattern = #"<formula>([\s\S]*?)</formula>"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let ns = body as NSString
    return regex.matches(in: body, range: NSRange(location: 0, length: ns.length)).map { match in
      decodeXMLEntities(ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines))
    }
  }

  private static func attributeValue(_ attrs: String, name: String) -> String? {
    guard let range = attrs.range(of: #"\#(name)="[^"]*""#, options: .regularExpression) else {
      return nil
    }
    let token = String(attrs[range])
    guard let q1 = token.firstIndex(of: "\""),
          let q2 = token.lastIndex(of: "\""),
          q1 < q2
    else { return nil }
    return String(token[token.index(after: q1)..<q2])
  }

  static func parseCellRange(_ ref: String) -> CellRange? {
    let trimmed = ref.trimmingCharacters(in: .whitespacesAndNewlines)
    if let (start, end) = A1Reference.parseRange(trimmed) {
      return CellRange(start: start, end: end)
    }
    if let parsed = A1Reference.parseAddress(trimmed) {
      let address = CellAddress(row: parsed.row, col: parsed.col)
      return CellRange(start: address, end: address)
    }
    return nil
  }

  private static func firstColor(
    in xml: String,
    near marker: String,
    themeScheme: ThemeColorScheme
  ) -> CodableColor? {
    guard let markerRange = xml.range(of: marker) else { return nil }
    let window = String(xml[markerRange.lowerBound...])
    if let tagRange = window.range(of: #"<[^>]+>"#, options: .regularExpression) {
      let tag = String(window[tagRange])
      if let themed = ThemeColorLookup.resolve(fromAttributes: tag, scheme: themeScheme) {
        return themed
      }
    }
    guard let rgbRange = window.range(of: #"rgb="[A-Fa-f0-9]{6,8}""#, options: .regularExpression)
    else { return nil }
    let token = String(window[rgbRange])
    guard let q1 = token.firstIndex(of: "\""),
          let q2 = token.lastIndex(of: "\""),
          q1 < q2
    else { return nil }
    return colorFromRGBHex(String(token[token.index(after: q1)..<q2]))
  }

  private static func colorFromRGBHex(_ rgb: String) -> CodableColor? {
    guard !rgb.isEmpty else { return nil }
    let hex = rgb.count == 8 ? String(rgb.suffix(6)) : rgb
    guard let value = UInt32(hex, radix: 16) else { return nil }
    let r = Double((value >> 16) & 0xFF) / 255
    let g = Double((value >> 8) & 0xFF) / 255
    let b = Double(value & 0xFF) / 255
    return CodableColor(red: r, green: g, blue: b, alpha: 1)
  }

  private static func stringFromNumber(_ value: Double) -> String {
    if value.rounded() == value, abs(value) < 1e12 {
      return String(Int(value))
    }
    return String(value)
  }
}
