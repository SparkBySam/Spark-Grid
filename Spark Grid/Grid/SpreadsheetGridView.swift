import AppKit
import SwiftUI

struct SpreadsheetGridView: NSViewRepresentable {
  @Bindable var viewModel: SpreadsheetViewModel

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeNSView(context: Context) -> SpreadsheetGridNSView {
    let view = SpreadsheetGridNSView()
    view.viewModel = viewModel
    context.coordinator.lastSheetKey = context.coordinator.sheetKey(for: viewModel)
    return view
  }

  func updateNSView(_ nsView: SpreadsheetGridNSView, context: Context) {
    nsView.viewModel = viewModel
    let sheetKey = context.coordinator.sheetKey(for: viewModel)
    if sheetKey != context.coordinator.lastSheetKey {
      context.coordinator.lastSheetKey = sheetKey
      nsView.reloadContent(resetScrollPosition: true)
    } else {
      nsView.syncDisplay()
    }
  }

  final class Coordinator {
    var lastSheetKey = ""

    func sheetKey(for viewModel: SpreadsheetViewModel) -> String {
      let sheet = viewModel.activeSheet
      return "\(viewModel.workbook.activeSheetIndex)-\(sheet.id.uuidString)-\(sheet.effectiveRowCount)-\(sheet.effectiveColumnCount)"
    }
  }
}
