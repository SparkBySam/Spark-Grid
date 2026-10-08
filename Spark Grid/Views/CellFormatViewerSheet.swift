import AppKit
import SwiftUI

struct CellFormatViewerSheet: View {
  @Bindable var viewModel: SpreadsheetViewModel
  let onDismiss: () -> Void

  @State private var codeText = ""
  @State private var loadedSelection = ""
  @State private var selectedRuleID: UUID?
  @State private var ruleRangeText = ""
  @State private var rulePrimary = ""
  @State private var ruleSecondary = ""
  @State private var ruleError: String?

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          numberSection
          rulesSection
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      Divider()
      footer
    }
    .frame(width: 560, height: 640)
    .background(Color(nsColor: .windowBackgroundColor))
    .onAppear { reloadCode() }
    .onChange(of: viewModel.selection) { _, _ in
      reloadCode()
    }
    .onChange(of: viewModel.workbook.activeSheetIndex) { _, _ in
      reloadCode()
      selectedRuleID = nil
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Cell Format")
        .font(.title3.weight(.semibold))
      Text(selectionLabel)
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(20)
    .padding(.bottom, 4)
  }

  private var selectionLabel: String {
    let range = viewModel.selectionRange
    if range.isSingleCell {
      return "Number format for \(range.start.a1)"
    }
    return "Number format for \(range.a1Label)"
  }

  private var draftFormat: CellFormat {
    var format = viewModel.selectedFormat
    let trimmed = codeText.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty || trimmed.caseInsensitiveCompare("General") == .orderedSame {
      format.numberFormat = .general
      format.formatCode = nil
      format.decimalPlaces = nil
    } else {
      format.formatCode = trimmed
      format.numberFormat = ExcelFormatCode.numberFormatKind(for: trimmed)
      format.decimalPlaces = nil
    }
    return format
  }

  private var previewText: String {
    let address = viewModel.selection
    let value = viewModel.displayValue(at: address)
    let raw = viewModel.activeSheet.cell(at: address).raw
    return CellFormatRenderer.displayText(for: value, format: draftFormat, fallbackRaw: raw)
  }

  private var categoryTitle: String {
    switch draftFormat.numberFormat {
    case .general:
      if let code = draftFormat.formatCode, !code.isEmpty { return "Stored code" }
      return "General"
    case .number:
      if draftFormat.viewerFormatCode.contains("#,") { return "Number, thousands separators" }
      return "Number"
    case .currency:
      return "Currency"
    case .percent:
      return "Percent"
    case .scientific:
      return "Scientific"
    case .date:
      return "Date"
    case .time:
      return "Time"
    }
  }

  private var numberSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Number format")
        .font(.headline)
      TextField("Format code", text: $codeText)
        .textFieldStyle(.roundedBorder)
        .font(.system(.body, design: .monospaced))
      Text(categoryTitle)
        .font(.subheadline)
        .foregroundStyle(.secondary)
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text("Preview")
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(previewText.isEmpty ? " " : previewText)
          .font(.system(.body, design: .monospaced))
      }
      Text("Uses the format code already stored for this cell. Dates, times, currency, and thousands separators follow that code.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var rules: [ConditionalFormatRule] {
    viewModel.activeSheet.conditionalFormats
  }

  private var selectedRule: ConditionalFormatRule? {
    guard let selectedRuleID else { return nil }
    return rules.first { $0.id == selectedRuleID }
  }

  private var rulesSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Conditional formatting")
        .font(.headline)
      Text("Rules already stored on \(viewModel.activeSheet.name).")
        .font(.caption)
        .foregroundStyle(.secondary)

      if rules.isEmpty {
        Text("No conditional formatting rules on this sheet.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .padding(.vertical, 8)
      } else {
        ForEach(rules) { rule in
          ruleRow(rule)
        }
        if let rule = selectedRule {
          ruleEditor(rule)
        }
      }
    }
  }

  private func ruleRow(_ rule: ConditionalFormatRule) -> some View {
    Button {
      selectRule(rule)
    } label: {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(rule.range.a1Label)
          .font(.system(.body, design: .monospaced))
        Text(rule.predicate.title)
          .foregroundStyle(.secondary)
          .lineLimit(2)
        Spacer()
      }
      .padding(.vertical, 6)
      .padding(.horizontal, 8)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        selectedRuleID == rule.id
          ? Color.accentColor.opacity(0.16)
          : Color(nsColor: .controlBackgroundColor),
        in: RoundedRectangle(cornerRadius: 6)
      )
    }
    .buttonStyle(.plain)
  }

  private func ruleEditor(_ rule: ConditionalFormatRule) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      TextField("Applies to", text: $ruleRangeText)
        .textFieldStyle(.roundedBorder)
        .font(.system(.body, design: .monospaced))
      if rule.predicate.editsValues {
        TextField(rule.predicate.secondaryEditText == nil ? "Value" : "First value", text: $rulePrimary)
          .textFieldStyle(.roundedBorder)
        if rule.predicate.secondaryEditText != nil {
          TextField("Second value", text: $ruleSecondary)
            .textFieldStyle(.roundedBorder)
        }
      }
      if let ruleError {
        Text(ruleError)
          .font(.caption)
          .foregroundStyle(Color(nsColor: .systemRed))
      }
      HStack {
        Button("Update Rule") { updateRule(rule) }
        Button("Delete Rule") {
          viewModel.removeConditionalFormatRules(ids: [rule.id])
          selectedRuleID = nil
        }
      }
    }
    .padding(.top, 4)
  }

  private var footer: some View {
    HStack {
      Button("Clear Format") {
        viewModel.setFormatCode(nil)
        reloadCode(force: true)
      }
      Spacer()
      Button("Close") { onDismiss() }
        .keyboardShortcut(.cancelAction)
      Button("Apply") {
        viewModel.setFormatCode(codeText)
        reloadCode(force: true)
      }
      .keyboardShortcut(.defaultAction)
      .buttonStyle(.borderedProminent)
    }
    .padding(16)
  }

  private func reloadCode(force: Bool = false) {
    let key = "\(viewModel.workbook.activeSheetIndex):\(viewModel.selection.a1)"
    if !force, key == loadedSelection, !codeText.isEmpty { return }
    loadedSelection = key
    codeText = viewModel.selectedFormat.viewerFormatCode
  }

  private func selectRule(_ rule: ConditionalFormatRule) {
    selectedRuleID = rule.id
    ruleRangeText = rule.range.a1Label
    rulePrimary = rule.predicate.primaryEditText ?? ""
    ruleSecondary = rule.predicate.secondaryEditText ?? ""
    ruleError = nil
  }

  private func updateRule(_ rule: ConditionalFormatRule) {
    guard let edited = rule.edited(rangeText: ruleRangeText, primary: rulePrimary, secondary: ruleSecondary) else {
      ruleError = "That range or value doesn’t match this rule."
      return
    }
    ruleError = nil
    viewModel.replaceConditionalFormatRule(edited)
  }
}

enum CellFormatViewerPresenter {
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
    let rootView = CellFormatViewerSheet(viewModel: viewModel) {
      controller.close()
      if let key {
        controllersByWindow[key] = nil
      }
    }
    let hosting = NSHostingController(rootView: rootView)
    let sheetWindow = NSWindow(contentViewController: hosting)
    sheetWindow.title = "Cell Format"
    sheetWindow.styleMask = [.titled, .closable]
    sheetWindow.setContentSize(NSSize(width: 560, height: 640))
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
