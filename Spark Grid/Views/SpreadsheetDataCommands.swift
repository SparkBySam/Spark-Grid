import AppKit
import SwiftUI

struct SpreadsheetDataCommands: Commands {
  @FocusedValue(\.spreadsheetViewModel) private var viewModel: SpreadsheetViewModel?

  var body: some Commands {
    CommandMenu("Data") {
      Button("Sort Range…") {
        presentSortDialog()
      }
      .disabled(viewModel == nil)

      Divider()

      Button("Create a Filter") {
        viewModel?.createFilter()
      }
      .disabled(viewModel == nil)

      Button("Clear Filter") {
        viewModel?.clearFilter()
      }
      .disabled(viewModel?.filterState == nil)
    }
  }

  private func presentSortDialog() {
    guard let viewModel else { return }
    let range = viewModel.effectiveSortRange()
    let n = range.normalized
    let columns = Array(n.minCol...n.maxCol)

    let alert = NSAlert()
    alert.messageText = "Sort Range"
    alert.informativeText = "Sort rows in \(CellAddress(row: n.minRow, col: n.minCol).a1):\(CellAddress(row: n.maxRow, col: n.maxCol).a1)"
    alert.alertStyle = .informational
    alert.addButton(withTitle: "Sort")
    alert.addButton(withTitle: "Cancel")

    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 8
    stack.translatesAutoresizingMaskIntoConstraints = false

    let columnLabel = NSTextField(labelWithString: "Sort by column")
    let columnPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    for col in columns {
      columnPopup.addItem(withTitle: A1Notation.columnLabel(for: col))
      columnPopup.lastItem?.tag = col
    }
    columnPopup.selectItem(withTag: n.minCol)

    let directionPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    directionPopup.addItem(withTitle: "A → Z")
    directionPopup.addItem(withTitle: "Z → A")

    let headerCheckbox = NSButton(
      checkboxWithTitle: "Header row",
      target: nil,
      action: nil
    )
    headerCheckbox.state = (n.maxRow > n.minRow) ? .on : .off

    stack.addArrangedSubview(columnLabel)
    stack.addArrangedSubview(columnPopup)
    stack.addArrangedSubview(directionPopup)
    stack.addArrangedSubview(headerCheckbox)

    columnPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
    directionPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
    stack.frame = NSRect(x: 0, y: 0, width: 220, height: 110)
    alert.accessoryView = stack

    guard alert.runModal() == .alertFirstButtonReturn else { return }
    let column = columnPopup.selectedItem?.tag ?? n.minCol
    let direction: SortDirection = directionPopup.indexOfSelectedItem == 0 ? .ascending : .descending
    let hasHeader = headerCheckbox.state == .on
    viewModel.sortRange(column: column, direction: direction, hasHeader: hasHeader)
  }
}
