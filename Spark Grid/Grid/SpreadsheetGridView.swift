import AppKit
import SwiftUI

struct SpreadsheetGridView: NSViewRepresentable {
  @Bindable var viewModel: SpreadsheetViewModel

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeNSView(context: Context) -> SpreadsheetGridNSView {
    let view = SpreadsheetGridNSView()
    view.viewModel = viewModel
    context.coordinator.lastSignature = context.coordinator.signature(for: viewModel)
    return view
  }

  func updateNSView(_ nsView: SpreadsheetGridNSView, context: Context) {
    nsView.viewModel = viewModel
    let signature = context.coordinator.signature(for: viewModel)
    if signature != context.coordinator.lastSignature {
      context.coordinator.lastSignature = signature
      nsView.reloadContent()
    } else {
      nsView.syncDisplay()
    }
  }

  final class Coordinator {
    var lastSignature = ""

    func signature(for viewModel: SpreadsheetViewModel) -> String {
      let sheet = viewModel.activeSheet
      return "\(sheet.id.uuidString)-\(sheet.cells.count)-\(sheet.maxPopulatedRow)-\(sheet.maxPopulatedColumn)-\(sheet.columnWidths.count)-\(sheet.rowHeights.count)-\(viewModel.selectionAnchor)-\(viewModel.selectionEnd)"
    }
  }
}
