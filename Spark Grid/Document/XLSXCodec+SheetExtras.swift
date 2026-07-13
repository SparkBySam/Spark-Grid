import CoreXLSX
import Foundation

extension XLSXCodec {
  // MARK: - Sheet extras (freeze, autofilter, CF) from / into worksheet XML

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

  static func importAutoFilter(into sheet: inout Sheet, archiveData: Data, worksheetPath: String) {
    guard let xml = zipEntryString(archiveData: archiveData, entryPath: worksheetPath) else { return }
    guard let refRange = xml.range(of: #"<autoFilter\b[^>]*ref="[^"]+""#, options: .regularExpression)
    else { return }
    let tag = String(xml[refRange])
    guard let quoteRange = tag.range(of: #"ref="[^"]+""#, options: .regularExpression) else { return }
    let quoted = String(tag[quoteRange])
    guard let q1 = quoted.firstIndex(of: "\""),
          let q2 = quoted.lastIndex(of: "\""),
          q1 < q2
    else { return }
    let ref = String(quoted[quoted.index(after: q1)..<q2])
    guard let range = parseCellRange(ref) else { return }
    sheet.autoFilter = SheetFilterState(range: range, selectedValuesByColumn: [:])
  }

  static func importConditionalFormatting(
    into sheet: inout Sheet,
    archiveData: Data,
    worksheetPath: String,
    dxfs: [ConditionalFormatStyle]
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
        default:
          predicate = nil
        }

        guard let predicate else { continue }
        sheet.conditionalFormats.append(
          ConditionalFormatRule(range: range, stopIfTrue: stop, predicate: predicate, style: style)
        )
      }
    }
  }

  static func importDifferentialFormats(archiveData: Data) -> [ConditionalFormatStyle] {
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
      if let fillHex = firstRGB(in: body, near: "fgColor") ?? firstRGB(in: body, near: "patternFill") {
        style.fillColor = colorFromRGBHex(fillHex)
      }
      if let fontBlock = body.range(of: #"<font>[\s\S]*?</font>"#, options: .regularExpression) {
        if let textHex = firstRGB(in: String(body[fontBlock]), near: "color") {
          style.textColor = colorFromRGBHex(textHex)
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

  static func sheetViewsXML(frozenRows: Int, frozenColumns: Int) -> String {
    guard frozenRows > 0 || frozenColumns > 0 else { return "" }
    let topLeft = CellAddress(row: frozenRows, col: frozenColumns).a1
    return """
    <sheetViews><sheetView workbookViewId="0"><pane xSplit="\(frozenColumns)" ySplit="\(frozenRows)" topLeftCell="\(topLeft)" activePane="bottomRight" state="frozen"/></sheetView></sheetViews>
    """
  }

  static func autoFilterXML(_ filter: SheetFilterState?) -> String {
    guard let filter else { return "" }
    let n = filter.range.normalized
    let start = CellAddress(row: n.minRow, col: n.minCol).a1
    let end = CellAddress(row: n.maxRow, col: n.maxCol).a1
    let ref = start == end ? start : "\(start):\(end)"
    return #"<autoFilter ref="\#(ref)"/>"#
  }

  static func conditionalFormattingXML(
    _ rules: [ConditionalFormatRule],
    dxfIndex: (ConditionalFormatStyle) -> Int
  ) -> String {
    guard !rules.isEmpty else { return "" }
    // Group by sqref for slightly cleaner XML.
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
        let dxfId = dxfIndex(rule.style)
        let stop = rule.stopIfTrue ? "" : #" stopIfTrue="0""#
        switch rule.predicate {
        case .greaterThan(let v):
          xml += #"<cfRule type="cellIs" dxfId="\#(dxfId)" priority="\#(priority)"\#(stop) operator="greaterThan"><formula>\#(escapeXML(stringFromNumber(v)))</formula></cfRule>"#
        case .lessThan(let v):
          xml += #"<cfRule type="cellIs" dxfId="\#(dxfId)" priority="\#(priority)"\#(stop) operator="lessThan"><formula>\#(escapeXML(stringFromNumber(v)))</formula></cfRule>"#
        case .greaterOrEqual(let v):
          xml += #"<cfRule type="cellIs" dxfId="\#(dxfId)" priority="\#(priority)"\#(stop) operator="greaterThanOrEqual"><formula>\#(escapeXML(stringFromNumber(v)))</formula></cfRule>"#
        case .lessOrEqual(let v):
          xml += #"<cfRule type="cellIs" dxfId="\#(dxfId)" priority="\#(priority)"\#(stop) operator="lessThanOrEqual"><formula>\#(escapeXML(stringFromNumber(v)))</formula></cfRule>"#
        case .equal(let v):
          xml += #"<cfRule type="cellIs" dxfId="\#(dxfId)" priority="\#(priority)"\#(stop) operator="equal"><formula>\#(escapeXML(stringFromNumber(v)))</formula></cfRule>"#
        case .between(let a, let b):
          xml += #"<cfRule type="cellIs" dxfId="\#(dxfId)" priority="\#(priority)"\#(stop) operator="between"><formula>\#(escapeXML(stringFromNumber(a)))</formula><formula>\#(escapeXML(stringFromNumber(b)))</formula></cfRule>"#
        case .textContains(let text):
          xml += #"<cfRule type="containsText" dxfId="\#(dxfId)" priority="\#(priority)"\#(stop) operator="containsText" text="\#(escapeXML(text))"><formula>NOT(ISERROR(SEARCH("\#(escapeXML(text))",A1)))</formula></cfRule>"#
        case .blanks:
          xml += #"<cfRule type="containsBlanks" dxfId="\#(dxfId)" priority="\#(priority)"\#(stop)/>"#
        case .nonBlanks:
          xml += #"<cfRule type="notContainsBlanks" dxfId="\#(dxfId)" priority="\#(priority)"\#(stop)/>"#
        case .formula(let raw):
          let formula = raw.hasPrefix("=") ? String(raw.dropFirst()) : raw
          xml += #"<cfRule type="expression" dxfId="\#(dxfId)" priority="\#(priority)"\#(stop)><formula>\#(escapeXML(formula))</formula></cfRule>"#
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

  private static func rgbHex(_ color: CodableColor) -> String {
    let r = Int((color.red * 255).rounded())
    let g = Int((color.green * 255).rounded())
    let b = Int((color.blue * 255).rounded())
    return String(format: "%02X%02X%02X", r, g, b)
  }

  // MARK: - Private helpers

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

  private static func parseCellRange(_ ref: String) -> CellRange? {
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

  private static func firstRGB(in xml: String, near marker: String) -> String? {
    guard let markerRange = xml.range(of: marker) else { return nil }
    let window = xml[markerRange.lowerBound...]
    guard let rgbRange = window.range(of: #"rgb="[A-Fa-f0-9]{6,8}""#, options: .regularExpression)
    else { return nil }
    let token = String(window[rgbRange])
    guard let q1 = token.firstIndex(of: "\""),
          let q2 = token.lastIndex(of: "\""),
          q1 < q2
    else { return nil }
    return String(token[token.index(after: q1)..<q2])
  }

  private static func colorFromRGBHex(_ rgb: String) -> CodableColor? {
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

// MARK: - Private helpers used by sheet extras (continued in extension file as needed)
