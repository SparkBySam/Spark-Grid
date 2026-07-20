import AppKit
import SwiftUI

struct SortRangeSheet: View {
  @Bindable var viewModel: SpreadsheetViewModel
  let onDismiss: () -> Void

  private let range: CellRange
  private let columns: [Int]

  @State private var selectedColumn: Int
  @State private var ascending = true
  @State private var hasHeader: Bool

  init(viewModel: SpreadsheetViewModel, onDismiss: @escaping () -> Void) {
    self.viewModel = viewModel
    self.onDismiss = onDismiss
    let range = viewModel.effectiveSortRange()
    let n = range.normalized
    self.range = range
    self.columns = Array(n.minCol...n.maxCol)
    _selectedColumn = State(initialValue: n.minCol)
    _hasHeader = State(initialValue: n.maxRow > n.minRow)
  }

  private var rangeLabel: String {
    let n = range.normalized
    let start = CellAddress(row: n.minRow, col: n.minCol).a1
    let end = CellAddress(row: n.maxRow, col: n.maxCol).a1
    return start == end ? start : "\(start):\(end)"
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      Form {
        Picker("Sort by column", selection: $selectedColumn) {
          ForEach(columns, id: \.self) { col in
            Text(A1Notation.columnLabel(for: col)).tag(col)
          }
        }

        Picker("Order", selection: $ascending) {
          Text("A → Z").tag(true)
          Text("Z → A").tag(false)
        }
        .pickerStyle(.segmented)

        Toggle("Header row", isOn: $hasHeader)
      }
      .formStyle(.grouped)
      .padding(.horizontal, 8)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      Divider()
      footer
    }
    .frame(width: 360, height: 280)
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Sort Range")
        .font(.title3.weight(.semibold))
      Text("Sort rows in \(rangeLabel)")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(20)
    .padding(.bottom, 4)
  }

  private var footer: some View {
    HStack {
      Spacer()
      Button("Cancel") {
        onDismiss()
      }
      .keyboardShortcut(.cancelAction)

      Button("Sort") {
        viewModel.sortRange(
          column: selectedColumn,
          direction: ascending ? .ascending : .descending,
          hasHeader: hasHeader
        )
        onDismiss()
      }
      .keyboardShortcut(.defaultAction)
      .buttonStyle(.borderedProminent)
    }
    .padding(16)
  }
}

enum SortRangePresenter {
  @MainActor
  private final class SheetController: NSObject, NSWindowDelegate {
    var window: NSWindow?

    func windowWillClose(_ notification: Notification) {
      window = nil
    }

    func close() {
      if let window, let sheetParent = window.sheetParent {
        sheetParent.endSheet(window)
      } else {
        window?.close()
      }
      window = nil
    }
  }

  @MainActor
  private static var controller = SheetController()

  @MainActor
  static func present(from viewModel: SpreadsheetViewModel, in window: NSWindow? = nil) {
    viewModel.commitEditIfNeeded()
    if controller.window != nil {
      controller.close()
    }

    let rootView = SortRangeSheet(viewModel: viewModel) {
      controller.close()
    }
    let hosting = NSHostingController(rootView: rootView)
    let sheetWindow = NSWindow(contentViewController: hosting)
    sheetWindow.title = "Sort Range"
    sheetWindow.styleMask = [.titled, .closable]
    sheetWindow.setContentSize(NSSize(width: 360, height: 280))
    sheetWindow.center()
    controller.window = sheetWindow
    sheetWindow.delegate = controller

    if let parent = window ?? NSApp.keyWindow ?? NSApp.mainWindow {
      parent.beginSheet(sheetWindow) { _ in
        controller.window = nil
      }
    } else {
      sheetWindow.makeKeyAndOrderFront(nil)
    }
  }
}
