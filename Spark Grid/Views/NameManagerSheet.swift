import AppKit
import SwiftUI

struct NameManagerSheet: View {
  @Bindable var viewModel: SpreadsheetViewModel
  let onDismiss: () -> Void

  @State private var selectedName: String?
  @State private var nameText = ""
  @State private var refersText = ""
  @State private var editingOriginal: String?
  @State private var errorMessage: String?

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      content
      Divider()
      footer
    }
    .frame(width: 640, height: 520)
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Name Manager")
        .font(.title3.weight(.semibold))
      Text("Defined names in this workbook. A formula such as OFFSET stays as written.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(20)
    .padding(.bottom, 4)
  }

  private var content: some View {
    VStack(spacing: 0) {
      if viewModel.definedNames.isEmpty {
        ContentUnavailableView(
          "No Defined Names",
          systemImage: "text.badge.plus",
          description: Text("Add a name for the current selection, or type a reference.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        List(viewModel.definedNames, id: \.name, selection: $selectedName) { named in
          nameRow(named)
            .tag(named.name)
        }
        .listStyle(.inset)
        .frame(maxHeight: .infinity)
      }

      Divider()
      editor
    }
    .onChange(of: selectedName) { _, name in
      guard let name, let named = viewModel.workbook.namedRange(named: name) else { return }
      load(named)
      viewModel.revealDefinedName(named)
    }
  }

  private func nameRow(_ named: NamedRange) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 8) {
        Text(named.name)
          .font(.body.weight(.medium))
        Spacer()
        Text(named.resolvesToRange ? "Range" : "Formula")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Text(named.referenceText)
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.secondary)
        .lineLimit(2)
      if !named.resolvesToRange {
        Text("Not a range — left as written")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 4)
  }

  private var editor: some View {
    VStack(alignment: .leading, spacing: 8) {
      TextField("Name", text: $nameText)
        .textFieldStyle(.roundedBorder)
      TextField("Refers to", text: $refersText)
        .textFieldStyle(.roundedBorder)
        .font(.system(.body, design: .monospaced))
      if let errorMessage {
        Text(errorMessage)
          .font(.caption)
          .foregroundStyle(Color(nsColor: .systemRed))
      }
    }
    .padding(16)
  }

  private var footer: some View {
    HStack {
      Button("New") { beginNew() }
      Button("Delete") { deleteSelected() }
        .disabled(editingOriginal == nil)
      Spacer()
      Button("Close") { onDismiss() }
        .keyboardShortcut(.cancelAction)
      Button(editingOriginal == nil ? "Add" : "Apply") { apply() }
        .keyboardShortcut(.defaultAction)
        .buttonStyle(.borderedProminent)
    }
    .padding(16)
  }

  private func load(_ named: NamedRange) {
    editingOriginal = named.name
    nameText = named.name
    refersText = named.referenceText
    errorMessage = nil
  }

  private func beginNew() {
    selectedName = nil
    editingOriginal = nil
    nameText = ""
    errorMessage = nil
    let draft = NamedRange(
      name: "Name",
      sheetName: viewModel.activeSheet.name,
      range: viewModel.selectionRange
    )
    refersText = draft.referenceText
  }

  private func apply() {
    errorMessage = viewModel.upsertDefinedName(
      originalName: editingOriginal,
      name: nameText,
      refersTo: refersText
    )
    guard errorMessage == nil else { return }
    let saved = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
    selectedName = saved
    if let named = viewModel.workbook.namedRange(named: saved) {
      load(named)
    }
  }

  private func deleteSelected() {
    guard let editingOriginal else { return }
    viewModel.deleteDefinedName(named: editingOriginal)
    self.editingOriginal = nil
    selectedName = nil
    nameText = ""
    refersText = ""
    errorMessage = nil
  }
}

enum NameManagerPresenter {
  @MainActor
  private final class SheetController: NSObject, NSWindowDelegate {
    var window: NSWindow?
    weak var viewModel: SpreadsheetViewModel?

    func windowWillClose(_ notification: Notification) {
      window = nil
      viewModel = nil
    }

    func close() {
      if let window, let sheetParent = window.sheetParent {
        sheetParent.endSheet(window)
      } else {
        window?.close()
      }
      window = nil
      viewModel = nil
    }
  }

  @MainActor
  private static var controllersByWindow: [ObjectIdentifier: SheetController] = [:]

  @MainActor
  static func present(from viewModel: SpreadsheetViewModel, in window: NSWindow? = nil) {
    viewModel.commitEditIfNeeded()
    let parent = window ?? NSApp.keyWindow ?? NSApp.mainWindow
    let key = parent.map { ObjectIdentifier($0) }

    if let key, let existing = controllersByWindow[key] {
      existing.close()
      controllersByWindow[key] = nil
    } else {
      for (id, controller) in controllersByWindow {
        controller.close()
        controllersByWindow[id] = nil
      }
    }

    let controller = SheetController()
    controller.viewModel = viewModel
    let rootView = NameManagerSheet(viewModel: viewModel) {
      controller.close()
      if let key {
        controllersByWindow[key] = nil
      }
    }
    let hosting = NSHostingController(rootView: rootView)
    let sheetWindow = NSWindow(contentViewController: hosting)
    sheetWindow.title = "Name Manager"
    sheetWindow.styleMask = [.titled, .closable]
    sheetWindow.setContentSize(NSSize(width: 640, height: 520))
    sheetWindow.center()
    controller.window = sheetWindow
    sheetWindow.delegate = controller
    if let key {
      controllersByWindow[key] = controller
    }

    if let parent {
      parent.beginSheet(sheetWindow) { _ in
        controller.window = nil
        controller.viewModel = nil
        if let key {
          controllersByWindow[key] = nil
        }
      }
    } else {
      sheetWindow.makeKeyAndOrderFront(nil)
    }
  }
}
