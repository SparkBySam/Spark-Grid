import Foundation

extension XLSXCodec {
  /// Writes Excel-readable drawing parts for a sheet's charts and embedded images.
  /// Also keeps the Spark JSON sidecar for faithful round-trip of our chart model.
  static func appendSheetDrawingParts(
    for sheet: Sheet,
    sheetIndex: Int,
    globalImageIndex: inout Int,
    into files: inout [String: Data]
  ) -> Bool {
    let hasCharts = !sheet.charts.isEmpty
    let hasImages = !sheet.images.isEmpty
    guard hasCharts || hasImages else { return false }

    let sheetNum = sheetIndex + 1
    var drawingBody = ""
    var drawingRels = ""
    var relId = 1

    for (chartIndex, chart) in sheet.charts.enumerated() {
      let chartNum = sheetIndex * 100 + chartIndex + 1
      files["xl/charts/chart\(chartNum).xml"] = Data(excelChartXML(chart, sheetName: sheet.name).utf8)
      drawingBody += twoCellAnchorXML(chart: chart, chartRelId: "rId\(relId)")
      drawingRels += """
      <Relationship Id="rId\(relId)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart" Target="../charts/chart\(chartNum).xml"/>
      """
      relId += 1
    }

    for (imageIndex, image) in sheet.images.enumerated() {
      globalImageIndex += 1
      let mediaName = mediaFileName(for: image, index: globalImageIndex)
      files["xl/media/\(mediaName)"] = image.imageData
      drawingBody += oneCellAnchorImageXML(image: image, relId: "rId\(relId)", pictureId: imageIndex + 1)
      drawingRels += """
      <Relationship Id="rId\(relId)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/\(mediaName)"/>
      """
      relId += 1
    }

    files["xl/drawings/drawing\(sheetNum).xml"] = Data(drawingXML(body: drawingBody).utf8)
    files["xl/drawings/_rels/drawing\(sheetNum).xml.rels"] = Data("""
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    \(drawingRels)
    </Relationships>
    """.utf8)
    return true
  }

  static func sheetDrawingRelationshipXML(sheetIndex: Int) -> String {
    #"<drawing r:id="rId1"/>"#
  }

  static func worksheetRelsXML(sheetIndex: Int, hasDrawing: Bool) -> Data? {
    guard hasDrawing else { return nil }
    let sheetNum = sheetIndex + 1
    let xml = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing" Target="../drawings/drawing\(sheetNum).xml"/>
    </Relationships>
    """
    return Data(xml.utf8)
  }

  static func drawingContentTypeOverrides(workbook: Workbook) -> String {
    var overrides = ""
    for (sheetIndex, sheet) in workbook.sheets.enumerated() {
      guard !sheet.charts.isEmpty || !sheet.images.isEmpty else { continue }
      let sheetNum = sheetIndex + 1
      overrides += """
      <Override PartName="/xl/drawings/drawing\(sheetNum).xml" ContentType="application/vnd.openxmlformats-officedocument.drawing+xml"/>
      """
      for (chartIndex, _) in sheet.charts.enumerated() {
        let chartNum = sheetIndex * 100 + chartIndex + 1
        overrides += """
        <Override PartName="/xl/charts/chart\(chartNum).xml" ContentType="application/vnd.openxmlformats-officedocument.drawingml.chart+xml"/>
        """
      }
    }
    return overrides
  }

  // MARK: - Chart XML builders

  private static func drawingXML(body: String) -> String {
    """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
    \(body)
    </xdr:wsDr>
    """
  }

  private static func twoCellAnchorXML(chart: SheetChart, chartRelId: String) -> String {
    let endRow = chart.anchorRow + chart.rowSpan
    let endCol = chart.anchorCol + chart.colSpan
    return """
    <xdr:twoCellAnchor>
      <xdr:from><xdr:col>\(chart.anchorCol)</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>\(chart.anchorRow)</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:from>
      <xdr:to><xdr:col>\(endCol)</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>\(endRow)</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:to>
      <xdr:graphicFrame macro="">
        <xdr:nvGraphicFramePr>
          <xdr:cNvPr id="2" name="\(escapeXML(chart.title))"/>
          <xdr:cNvGraphicFramePr><a:graphicFrameLocks noGrp="1"/></xdr:cNvGraphicFramePr>
        </xdr:nvGraphicFramePr>
        <xdr:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/></a:xfrm>
        <a:graphic>
          <a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/chart">
            <c:chart xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" r:id="\(chartRelId)"/>
          </a:graphicData>
        </a:graphic>
      </xdr:graphicFrame>
      <xdr:clientData/>
    </xdr:twoCellAnchor>
    """
  }

  private static func excelChartXML(_ chart: SheetChart, sheetName: String) -> String {
    let n = chart.dataRange.normalized
    let safeSheet = sheetName.replacingOccurrences(of: "'", with: "''")
    let hasHeader = chart.hasHeaderRow && n.maxRow > n.minRow
    let dataStartRow = hasHeader ? n.minRow + 1 : n.minRow
    let catCol = chart.categoryColumn ?? n.minCol
    let valCol = chart.valueColumn ?? min(n.maxCol, n.minCol + (n.minCol == n.maxCol ? 0 : 1))
    let catStart = CellAddress(row: dataStartRow, col: catCol).a1
    let catEnd = CellAddress(row: n.maxRow, col: catCol).a1
    let valStart = CellAddress(row: dataStartRow, col: valCol).a1
    let valEnd = CellAddress(row: n.maxRow, col: valCol).a1
    let catRef = "'\(safeSheet)'!\(catStart):\(catEnd)"
    let valRef = "'\(safeSheet)'!\(valStart):\(valEnd)"

    // Count mode is Spark-native; Excel export still points at the category column
    // as both cats and a placeholder val ref so the part remains valid.
    let exportValRef = chart.valueMode == .count ? catRef : valRef

    let seriesInner: String
    switch chart.kind {
    case .bar:
      seriesInner = """
      <c:barChart>
        <c:barDir val="col"/>
        <c:grouping val="clustered"/>
        <c:ser>
          <c:idx val="0"/><c:order val="0"/>
          <c:tx><c:v>\(escapeXML(chart.title))</c:v></c:tx>
          <c:cat><c:strRef><c:f>\(escapeXML(catRef))</c:f></c:strRef></c:cat>
          <c:val><c:numRef><c:f>\(escapeXML(exportValRef))</c:f></c:numRef></c:val>
        </c:ser>
        <c:axId val="1"/><c:axId val="2"/>
      </c:barChart>
      """
    case .line:
      seriesInner = """
      <c:lineChart>
        <c:grouping val="standard"/>
        <c:ser>
          <c:idx val="0"/><c:order val="0"/>
          <c:tx><c:v>\(escapeXML(chart.title))</c:v></c:tx>
          <c:cat><c:strRef><c:f>\(escapeXML(catRef))</c:f></c:strRef></c:cat>
          <c:val><c:numRef><c:f>\(escapeXML(exportValRef))</c:f></c:numRef></c:val>
        </c:ser>
        <c:axId val="1"/><c:axId val="2"/>
      </c:lineChart>
      """
    case .area:
      seriesInner = """
      <c:areaChart>
        <c:grouping val="standard"/>
        <c:ser>
          <c:idx val="0"/><c:order val="0"/>
          <c:tx><c:v>\(escapeXML(chart.title))</c:v></c:tx>
          <c:cat><c:strRef><c:f>\(escapeXML(catRef))</c:f></c:strRef></c:cat>
          <c:val><c:numRef><c:f>\(escapeXML(exportValRef))</c:f></c:numRef></c:val>
        </c:ser>
        <c:axId val="1"/><c:axId val="2"/>
      </c:areaChart>
      """
    }

    return """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <c:chartSpace xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
      <c:chart>
        <c:title>
          <c:tx><c:rich><a:bodyPr/><a:lstStyle/><a:p><a:pPr><a:defRPr/></a:pPr><a:r><a:t>\(escapeXML(chart.title))</a:t></a:r></a:p></c:rich></c:tx>
          <c:overlay val="0"/>
        </c:title>
        <c:plotArea>
          <c:layout/>
          \(seriesInner)
          <c:catAx>
            <c:axId val="1"/><c:scaling><c:orientation val="minMax"/></c:scaling>
            <c:axPos val="b"/><c:crossAx val="2"/>
          </c:catAx>
          <c:valAx>
            <c:axId val="2"/><c:scaling><c:orientation val="minMax"/></c:scaling>
            <c:axPos val="l"/><c:crossAx val="1"/>
          </c:valAx>
        </c:plotArea>
        <c:legend><c:legendPos val="r"/><c:overlay val="0"/></c:legend>
      </c:chart>
    </c:chartSpace>
    """
  }
}
