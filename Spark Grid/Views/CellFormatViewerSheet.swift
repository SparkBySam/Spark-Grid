import AppKit
import SwiftUI

struct CellFormatViewerSheet: View {
  private enum Category: String, CaseIterable, Identifiable {
    case general, number, currency, percent, scientific, date, time, custom

    var id: String { rawValue }

    var title: String {
      switch self {
      case .general: return "General"
      case .number: return "Number"
      case .currency: return "Currency"
      case .percent: return "Percent"
      case .scientific: return "Scientific"
      case .date: return "Date"
      case .time: return "Time"
      case .custom: return "Custom"
      }
    }

    var explanation: String {
      switch self {
      case .general:
        return "Shows the value as it was entered."
      case .number:
        return "Fixed number of decimal places."
      case .currency:
        return "Dollar sign and decimal places."
      case .percent:
        return "Multiplies by 100 and adds a percent sign."
      case .scientific:
        return "Scientific notation."
      case .date:
        return "Month, day, and year."
      case .time:
        return "Hour, minute, and second."
      case .custom:
        return "Type a format code. Sections are positive, negative, zero, and text. Put words in quotes."
      }
    }

    var preset: CellFormat.NumberFormat {
      switch self {
      case .general, .custom: return .general
      case .number: return .number
      case .currency: return .currency
      case .percent: return .percent
      case .scientific: return .scientific
      case .date: return .date
      case .time: return .time
      }
    }

    init(_ format: CellFormat.NumberFormat) {
      switch format {
      case .general: self = .general
      case .number: self = .number
      case .currency: self = .currency
      case .percent: self = .percent
      case .scientific: self = .scientific
      case .date: self = .date
      case .time: self = .time
      }
    }
  }

  @Bindable var viewModel: SpreadsheetViewModel
  let onDismiss: () -> Void

  @State private var category: Category = .general
  @State private var codeText = ""
  @State private var loadedKey = ""
  @State private var formatFieldFocusToken = 0
  @State private var selectedRuleID: UUID?
  @State private var ruleRangeText = ""
  @State private var rulePrimary = ""
  @State private var ruleSecondary = ""
  @State private var ruleError: String?
  @State private var ruleBold = false
  @State private var ruleBoldTouched = false

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
    .frame(width: 620, height: 680)
    .background(Color(nsColor: .windowBackgroundColor))
    .onAppear { reloadCode() }
    .onChange(of: storedFormatKey) { _, _ in
      reloadCode()
    }
    .onChange(of: viewModel.workbook.activeSheetIndex) { _, _ in
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

  private var storedFormatKey: String {
    let format = viewModel.selectedFormat
    let places = format.decimalPlaces.map { String($0) } ?? ""
    return "\(viewModel.workbook.activeSheetIndex):\(viewModel.selection.a1):\(format.numberFormat.rawValue):\(format.formatCode ?? ""):\(places)"
  }

  private var draftFormat: CellFormat {
    var format = viewModel.selectedFormat
    if category == .custom {
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
    } else {
      format.numberFormat = category.preset
      format.formatCode = nil
      if format.decimalPlaces == nil {
        format.decimalPlaces = Self.defaultDecimalPlaces(for: category.preset)
      }
    }
    return format
  }

  private var sampleUsesExample: Bool {
    if case .blank = viewModel.displayValue(at: viewModel.selection) { return true }
    return false
  }

  private var sampleText: String {
    let format = draftFormat
    let shown: String
    if sampleUsesExample {
      shown = CellFormatRenderer.displayText(for: exampleValue, format: format, fallbackRaw: "")
    } else {
      let address = viewModel.selection
      let value = viewModel.displayValue(at: address)
      let raw = viewModel.activeSheet.cell(at: address).raw
      shown = CellFormatRenderer.displayText(for: value, format: format, fallbackRaw: raw)
    }
    return shown.isEmpty ? " " : shown
  }

  private var exampleValue: CellValue {
    switch draftFormat.numberFormat {
    case .date:
      return .number(ExcelDate.serial(from: Self.exampleDate))
    case .time:
      return .number(0.75)
    case .percent:
      return .number(0.256)
    default:
      return .number(1234.5)
    }
  }

  private static let exampleDate: Date = {
    var components = DateComponents()
    components.calendar = Calendar(identifier: .gregorian)
    components.timeZone = TimeZone(secondsFromGMT: 0)
    components.year = 2026
    components.month = 10
    components.day = 8
    components.hour = 12
    return components.date ?? Date(timeIntervalSince1970: 0)
  }()

  private static func defaultDecimalPlaces(for format: CellFormat.NumberFormat) -> Int {
    switch format {
    case .general, .date, .time: return 0
    case .number, .currency, .percent, .scientific: return 2
    }
  }

  private var numberSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Number format")
        .font(.headline)
      HStack(alignment: .top, spacing: 16) {
        VStack(alignment: .leading, spacing: 2) {
          ForEach(Category.allCases) { item in
            categoryButton(item)
          }
        }
        .padding(4)
        .frame(width: 140)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

        VStack(alignment: .leading, spacing: 8) {
          Text(category.explanation)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          if category == .custom {
            CellFormatCodeField(
              text: $codeText,
              focusToken: formatFieldFocusToken,
              onSubmit: { runPanel(.apply) }
            )
            .frame(height: 24)
          }
          sampleBox
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  private var sampleBox: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Sample")
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(sampleText)
        .font(.system(.body, design: .monospaced))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
          RoundedRectangle(cornerRadius: 6)
            .strokeBorder(Color(nsColor: .separatorColor))
        )
      if sampleUsesExample {
        Text("The cell is empty, so the sample uses an example value.")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private func categoryButton(_ item: Category) -> some View {
    Button {
      selectCategory(item)
    } label: {
      Text(item.title)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
          category == item ? Color.accentColor.opacity(0.16) : Color.clear,
          in: RoundedRectangle(cornerRadius: 6)
        )
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(category == item ? .isSelected : AccessibilityTraits())
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
      if rule.predicate.usesFontStyle {
        Toggle("Bold", isOn: Binding(
          get: { ruleBold },
          set: { newValue in
            ruleBold = newValue
            ruleBoldTouched = true
          }
        ))
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
      Button("Close") { runPanel(.close) }
        .keyboardShortcut(.cancelAction)
      Button("Apply") { runPanel(.apply) }
      .keyboardShortcut(.defaultAction)
      .buttonStyle(.borderedProminent)
    }
    .padding(16)
  }

  private func reloadCode(force: Bool = false) {
    let key = storedFormatKey
    if !force, key == loadedKey { return }
    loadedKey = key
    let format = viewModel.selectedFormat
    if let code = format.formatCode?.trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty {
      category = .custom
      codeText = code
    } else {
      category = Category(format.numberFormat)
      codeText = ""
    }
  }

  private func selectCategory(_ next: Category) {
    if next == .custom, codeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      let stored = viewModel.selectedFormat
      if let code = stored.formatCode?.trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty {
        codeText = code
      } else if stored.numberFormat != .general {
        let seeded = stored.viewerFormatCode
        if seeded.caseInsensitiveCompare("General") != .orderedSame {
          codeText = seeded
        }
      }
    }
    category = next
    if next == .custom {
      formatFieldFocusToken += 1
    }
  }

  private func runPanel(_ action: CellFormatPanelAction) {
    CellFormatPanel.perform(action, store: applyDraft, close: onDismiss)
  }

  private func applyDraft() {
    if category == .custom {
      viewModel.setFormatCode(codeText)
    } else {
      viewModel.setNumberFormat(category.preset)
    }
  }

  private func selectRule(_ rule: ConditionalFormatRule) {
    selectedRuleID = rule.id
    ruleRangeText = rule.range.a1Label
    rulePrimary = rule.predicate.primaryEditText ?? ""
    ruleSecondary = rule.predicate.secondaryEditText ?? ""
    ruleBold = rule.style.bold == true
    ruleBoldTouched = false
    ruleError = nil
  }

  private func updateRule(_ rule: ConditionalFormatRule) {
    guard var edited = rule.edited(rangeText: ruleRangeText, primary: rulePrimary, secondary: ruleSecondary) else {
      ruleError = "That range or value doesn’t match this rule."
      return
    }
    if rule.predicate.usesFontStyle {
      edited.style = edited.style.withBoldCheckbox(
        isOn: ruleBold,
        previous: rule.style.bold,
        touched: ruleBoldTouched
      )
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
    sheetWindow.setContentSize(NSSize(width: 620, height: 680))
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

/// Apply stores the draft and closes the panel. Close dismisses without storing.
/// Clicking the parent window leaves the sheet up and does not store.
enum CellFormatPanelAction: Equatable {
  case apply
  case close
  case clickAway
}

struct CellFormatPanelResult: Equatable {
  var storesDraft: Bool
  var closes: Bool
}

enum CellFormatPanel {
  static func result(for action: CellFormatPanelAction) -> CellFormatPanelResult {
    switch action {
    case .apply:
      return CellFormatPanelResult(storesDraft: true, closes: true)
    case .close:
      return CellFormatPanelResult(storesDraft: false, closes: true)
    case .clickAway:
      return CellFormatPanelResult(storesDraft: false, closes: false)
    }
  }

  static func perform(
    _ action: CellFormatPanelAction,
    store: () -> Void,
    close: () -> Void
  ) {
    let outcome = result(for: action)
    if outcome.storesDraft { store() }
    if outcome.closes { close() }
  }
}

/// Edit → Paste and the grid’s ⌘V. The format field takes the paste while it is editing.
enum SpreadsheetPaste {
  static func perform(on viewModel: SpreadsheetViewModel?) {
    if CellFormatCodePaste.pasteIntoEditingField() { return }
    viewModel?.pasteFromPasteboard()
  }
}

enum CellFormatCodePaste {
  static weak var editingField: CellFormatCodeTextField?

  /// Swallows the paste shortcut while the format field is editing so the grid command does not run.
  static func handleKeyDown(_ event: NSEvent) -> NSEvent? {
    guard let field = editingField, AppSettings.shared.matches(.paste, event: event) else {
      return event
    }
    field.insertPasteboardReplacingSelection()
    return nil
  }

  static func pasteIntoEditingField() -> Bool {
    guard let field = editingField ?? fieldFromFirstResponder() else { return false }
    field.insertPasteboardReplacingSelection()
    return true
  }

  private static func fieldFromFirstResponder() -> CellFormatCodeTextField? {
    let responder = NSApp.keyWindow?.firstResponder
    if let field = responder as? CellFormatCodeTextField { return field }
    if let textView = responder as? NSTextView, let field = textView.delegate as? CellFormatCodeTextField {
      return field
    }
    return nil
  }
}

/// Format code box. Paste stays in this field while it is focused.
private struct CellFormatCodeField: NSViewRepresentable {
  @Binding var text: String
  var focusToken: Int
  var onSubmit: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(text: $text, onSubmit: onSubmit)
  }

  func makeNSView(context: Context) -> CellFormatCodeTextField {
    let field = CellFormatCodeTextField()
    field.stringValue = text
    field.placeholderString = "#,##0.00;(#,##0.00);0;@"
    field.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    field.isBezeled = true
    field.bezelStyle = .roundedBezel
    field.delegate = context.coordinator
    field.cell?.isScrollable = true
    field.cell?.wraps = false
    field.cell?.lineBreakMode = .byClipping
    field.setAccessibilityLabel("Format code")
    field.onTextChange = { context.coordinator.text = $0 }
    return field
  }

  func updateNSView(_ field: CellFormatCodeTextField, context: Context) {
    context.coordinator.onSubmit = onSubmit
    field.onTextChange = { context.coordinator.text = $0 }
    field.delegate = context.coordinator
    if field.liveText != text {
      field.replaceLiveText(text)
    }
    if focusToken != context.coordinator.appliedFocusToken {
      context.coordinator.appliedFocusToken = focusToken
      if focusToken != 0 {
        DispatchQueue.main.async {
          field.window?.makeFirstResponder(field)
        }
      }
    }
  }

  final class Coordinator: NSObject, NSTextFieldDelegate {
    @Binding var text: String
    var onSubmit: () -> Void
    var appliedFocusToken = 0

    init(text: Binding<String>, onSubmit: @escaping () -> Void) {
      _text = text
      self.onSubmit = onSubmit
    }

    func controlTextDidChange(_ notification: Notification) {
      guard let field = notification.object as? CellFormatCodeTextField else { return }
      text = field.liveText
    }

    func control(
      _ control: NSControl,
      textView: NSTextView,
      doCommandBy commandSelector: Selector
    ) -> Bool {
      if commandSelector == #selector(NSResponder.insertNewline(_:)) {
        onSubmit()
        return true
      }
      return false
    }
  }
}

final class CellFormatCodeTextField: NSTextField {
  var onTextChange: ((String) -> Void)?
  private var pasteMonitor: Any?

  var isInterceptingPaste: Bool { pasteMonitor != nil }

  var liveText: String {
    if let editor = currentEditor() as? NSTextView { return editor.string }
    return stringValue
  }

  func replaceLiveText(_ text: String) {
    if let editor = currentEditor() as? NSTextView {
      if editor.string != text {
        editor.string = text
      }
    } else if stringValue != text {
      stringValue = text
    }
  }

  /// Plain-text paste at the caret, drawn with the same attributes as typed text.
  /// Replacing into the text storage keeps a black foreground from the pasteboard.
  func insertPasteboardReplacingSelection() {
    guard let pasted = NSPasteboard.general.string(forType: .string) else { return }
    if let editor = ensureEditor(), let storage = editor.textStorage {
      let ns = editor.string as NSString
      var range = editor.selectedRange()
      if range.location == NSNotFound || range.location > ns.length {
        range = NSRange(location: ns.length, length: 0)
      } else if NSMaxRange(range) > ns.length {
        range.length = max(0, ns.length - range.location)
      }
      let typed = attributesMatchingTypedText(in: editor)
      let inserted = NSRange(location: range.location, length: (pasted as NSString).length)
      storage.beginEditing()
      storage.replaceCharacters(in: range, with: pasted)
      if inserted.length > 0, NSMaxRange(inserted) <= storage.length {
        storage.setAttributes(typed, range: inserted)
      }
      storage.endEditing()
      let caret = range.location + (pasted as NSString).length
      editor.setSelectedRange(NSRange(location: min(caret, (editor.string as NSString).length), length: 0))
      editor.typingAttributes = typed
      editor.didChangeText()
      if inserted.length > 0, let storage = editor.textStorage, NSMaxRange(inserted) <= storage.length {
        storage.beginEditing()
        storage.setAttributes(typed, range: inserted)
        storage.endEditing()
      }
    } else {
      stringValue = pasted
    }
    onTextChange?(liveText)
  }

  /// Font and foreground used for characters typed in this field.
  private func attributesMatchingTypedText(in editor: NSTextView) -> [NSAttributedString.Key: Any] {
    var attrs = editor.typingAttributes
    if attrs[.font] == nil {
      attrs[.font] = editor.font ?? font ?? NSFont.monospacedSystemFont(
        ofSize: NSFont.systemFontSize,
        weight: .regular
      )
    }
    if attrs[.foregroundColor] == nil {
      attrs[.foregroundColor] = textColor ?? NSColor.labelColor
    }
    return attrs
  }

  override func becomeFirstResponder() -> Bool {
    let ok = super.becomeFirstResponder()
    if ok { beginInterceptingPaste() }
    return ok
  }

  override func textDidBeginEditing(_ notification: Notification) {
    beginInterceptingPaste()
    super.textDidBeginEditing(notification)
  }

  override func textDidEndEditing(_ notification: Notification) {
    endInterceptingPaste()
    super.textDidEndEditing(notification)
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if window == nil {
      endInterceptingPaste()
    }
  }

  private func beginInterceptingPaste() {
    CellFormatCodePaste.editingField = self
    guard pasteMonitor == nil else { return }
    pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      CellFormatCodePaste.handleKeyDown(event)
    }
  }

  private func endInterceptingPaste() {
    if CellFormatCodePaste.editingField === self {
      CellFormatCodePaste.editingField = nil
    }
    if let pasteMonitor {
      NSEvent.removeMonitor(pasteMonitor)
      self.pasteMonitor = nil
    }
  }

  private func ensureEditor() -> NSTextView? {
    if let editor = currentEditor() as? NSTextView { return editor }
    window?.makeFirstResponder(self)
    return currentEditor() as? NSTextView
  }
}
