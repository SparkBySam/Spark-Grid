import AppKit
import SwiftUI

struct SpreadsheetStructureCommands: Commands {
  @FocusedValue(\.spreadsheetViewModel) private var focusedViewModel: SpreadsheetViewModel?

  private var viewModel: SpreadsheetViewModel? {
    focusedViewModel ?? (NSApp.delegate as? SparkGridAppDelegate)?.resolvedSpreadsheetViewModel()
  }

  var body: some Commands {
    CommandMenu("Sheet") {
      let axis = viewModel?.selectionAxis ?? .cells

      Button("Insert Row Above") { viewModel?.insertRowsAbove() }
        .disabled(viewModel == nil || axis == .column)
      Button("Insert Row Below") { viewModel?.insertRowsBelow() }
        .disabled(viewModel == nil || axis == .column)
      Button("Delete Row(s)") { viewModel?.deleteSelectedRows() }
        .disabled(viewModel == nil || axis == .column)

      Divider()

      Button("Insert Column Left") { viewModel?.insertColumnsLeft() }
        .disabled(viewModel == nil || axis == .row)
      Button("Insert Column Right") { viewModel?.insertColumnsRight() }
        .disabled(viewModel == nil || axis == .row)
      Button("Delete Column(s)") { viewModel?.deleteSelectedColumns() }
        .disabled(viewModel == nil || axis == .row)

      Divider()

      Button("Freeze Panes") {
        guard viewModel?.freezePanesAtSelection() == true else {
          SpreadsheetGridNSView.presentFreezeRequiresOffsetAlert(axis: .both)
          return
        }
      }
      .disabled(viewModel == nil)
      Button("Freeze Rows") {
        guard viewModel?.freezeRowsAtSelection() == true else {
          SpreadsheetGridNSView.presentFreezeRequiresOffsetAlert(axis: .rows)
          return
        }
      }
      .disabled(viewModel == nil)
      Button("Freeze Columns") {
        guard viewModel?.freezeColumnsAtSelection() == true else {
          SpreadsheetGridNSView.presentFreezeRequiresOffsetAlert(axis: .columns)
          return
        }
      }
      .disabled(viewModel == nil)
      Button("Unfreeze Panes") { viewModel?.unfreezePanes() }
        .disabled(viewModel == nil)

      Divider()

      Menu("Merge Cells") {
        Button("Merge All") { viewModel?.mergeSelection(axis: .all) }
          .disabled(viewModel?.canMergeSelection != true)
        Button("Merge Across") { viewModel?.mergeSelection(axis: .horizontal) }
          .disabled(viewModel?.canMergeHorizontally != true)
        Button("Merge Vertically") { viewModel?.mergeSelection(axis: .vertical) }
          .disabled(viewModel?.canMergeVertically != true)
        Divider()
        Button("Unmerge Cells") { viewModel?.unmergeSelection() }
          .disabled(viewModel?.canUnmergeSelection != true)
      }
      .disabled(viewModel == nil)

      Divider()

      Menu("Insert Chart") {
        Button("Bar Chart") { viewModel?.insertChart(kind: .bar) }
        Button("Line Chart") { viewModel?.insertChart(kind: .line) }
        Button("Area Chart") { viewModel?.insertChart(kind: .area) }
      }
      .disabled(viewModel == nil)

      Divider()

      Button("Define Named Range…") {
        Self.promptDefineNamedRange(viewModel: viewModel)
      }
      .disabled(viewModel == nil)
    }

    CommandGroup(replacing: .printItem) {
      Button("Print…") {
        (NSApp.delegate as? SparkGridAppDelegate)?.printDocument(nil)
      }
      .keyboardShortcut("p", modifiers: .command)
    }
  }

  private static func promptDefineNamedRange(viewModel: SpreadsheetViewModel?) {
    guard let viewModel else { return }
    let alert = NSAlert()
    alert.messageText = "Define Named Range"
    alert.informativeText = "Name the current selection (\(viewModel.selectionRange.start.a1):\(viewModel.selectionRange.end.a1))."
    alert.alertStyle = .informational
    alert.addButton(withTitle: "Define")
    alert.addButton(withTitle: "Cancel")
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
    field.placeholderString = "Sales"
    alert.accessoryView = field
    alert.window.initialFirstResponder = field
    let response = alert.runModal()
    guard response == .alertFirstButtonReturn else { return }
    viewModel.defineNamedRange(name: field.stringValue)
  }
}
