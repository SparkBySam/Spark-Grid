import CoreGraphics
import Foundation

/// Embedded picture anchored on a sheet (Excel drawing / oneCellAnchor).
struct SheetImage: Identifiable, Codable, Equatable, Sendable {
  var id: UUID
  /// Top-left anchor cell (0-based row/column).
  var anchorRow: Int
  var anchorCol: Int
  /// Offset from anchor cell top-left, in EMU (English Metric Units).
  var rowOffsetEMU: Int
  var colOffsetEMU: Int
  var widthEMU: Int
  var heightEMU: Int
  var imageData: Data
  /// MIME type for export (`image/png`, `image/jpeg`).
  var contentType: String

  init(
    id: UUID = UUID(),
    anchorRow: Int,
    anchorCol: Int,
    rowOffsetEMU: Int = 0,
    colOffsetEMU: Int = 0,
    widthEMU: Int,
    heightEMU: Int,
    imageData: Data,
    contentType: String = "image/png"
  ) {
    self.id = id
    self.anchorRow = anchorRow
    self.anchorCol = anchorCol
    self.rowOffsetEMU = rowOffsetEMU
    self.colOffsetEMU = colOffsetEMU
    self.widthEMU = widthEMU
    self.heightEMU = heightEMU
    self.imageData = imageData
    self.contentType = contentType
  }

  /// EMU per typographic point (914400 EMU per inch, 72 pt per inch).
  static let emuPerPoint: CGFloat = 914_400 / 72

  static func points(fromEMU emu: Int) -> CGFloat {
    CGFloat(emu) / emuPerPoint
  }
}
