import AppKit
import SwiftUI

struct SpreadsheetGridView: NSViewRepresentable {
  var viewModel: SpreadsheetViewModel

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeNSView(context: Context) -> SpreadsheetGridNSView {
    let view = SpreadsheetGridNSView()
    view.viewModel = viewModel
    context.coordinator.lastSheetKey = context.coordinator.sheetKey(for: viewModel)
    context.coordinator.lastContentRevision = viewModel.contentRevision
    context.coordinator.lastGridRefreshToken = viewModel.gridRefreshToken
    context.coordinator.lastSelectionAnchor = viewModel.selectionAnchor
    context.coordinator.lastSelectionEnd = viewModel.selectionEnd
    context.coordinator.lastSelectionRevision = viewModel.selectionRevision
    context.coordinator.lastFormulaHighlightRevision = viewModel.formulaHighlightRevision
    context.coordinator.scheduleInitialFocus(for: view)
    return view
  }

  func updateNSView(_ nsView: SpreadsheetGridNSView, context: Context) {
    if nsView.viewModel !== viewModel {
      nsView.viewModel = viewModel
    }
    let sheetKey = context.coordinator.sheetKey(for: viewModel)
    if sheetKey != context.coordinator.lastSheetKey {
      context.coordinator.lastSheetKey = sheetKey
      context.coordinator.lastContentRevision = viewModel.contentRevision
      nsView.reloadContent(resetScrollPosition: true)
    } else if viewModel.contentRevision != context.coordinator.lastContentRevision {
      context.coordinator.lastContentRevision = viewModel.contentRevision
      context.coordinator.lastGridRefreshToken = viewModel.gridRefreshToken
      nsView.syncDisplay()
    } else if viewModel.gridRefreshToken != context.coordinator.lastGridRefreshToken {
      context.coordinator.lastGridRefreshToken = viewModel.gridRefreshToken
      nsView.applyFreezePanesLayout()
    } else if viewModel.selectionRevision != context.coordinator.lastSelectionRevision
      || viewModel.selectionAnchor != context.coordinator.lastSelectionAnchor
      || viewModel.selectionEnd != context.coordinator.lastSelectionEnd
    {
      context.coordinator.lastSelectionRevision = viewModel.selectionRevision
      context.coordinator.lastSelectionAnchor = viewModel.selectionAnchor
      context.coordinator.lastSelectionEnd = viewModel.selectionEnd
      context.coordinator.lastFormulaHighlightRevision = viewModel.formulaHighlightRevision
      nsView.refreshSelectionDisplay()
    } else if viewModel.formulaHighlightRevision != context.coordinator.lastFormulaHighlightRevision {
      context.coordinator.lastFormulaHighlightRevision = viewModel.formulaHighlightRevision
      // Redraw ref borders; refresh in-cell colored tokens when focus changes.
      nsView.refreshFormulaHighlights()
    }
  }

  final class Coordinator {
    var lastSheetKey = ""
    var lastContentRevision = 0
    var lastGridRefreshToken = 0
    var lastSelectionRevision = 0
    var lastSelectionAnchor = CellAddress.origin
    var lastSelectionEnd = CellAddress.origin
    var lastFormulaHighlightRevision = 0
    private var didScheduleInitialFocus = false

    func scheduleInitialFocus(for gridView: SpreadsheetGridNSView) {
      guard !didScheduleInitialFocus else { return }
      didScheduleInitialFocus = true
      DispatchQueue.main.async {
        gridView.claimInitialFocusIfNeeded()
      }
    }

    func sheetKey(for viewModel: SpreadsheetViewModel) -> String {
      let sheet = viewModel.activeSheet
      return "\(viewModel.workbook.activeSheetIndex)-\(sheet.id.uuidString)-\(sheet.effectiveRowCount)-\(sheet.effectiveColumnCount)-\(sheet.frozenRows)-\(sheet.frozenColumns)"
    }
  }
}
