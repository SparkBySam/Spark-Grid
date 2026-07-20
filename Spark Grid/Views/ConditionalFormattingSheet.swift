import AppKit
import SwiftUI

struct ConditionalFormattingSheet: View {
  @Bindable var viewModel: SpreadsheetViewModel
  let onDismiss: () -> Void

  @State private var segment: Segment = .newRule
  @State private var ruleType: RuleType = .highlightCells

  // Highlight Cells
  @State private var highlightKind: HighlightKind = .greaterThan
  @State private var valueText = "100"
  @State private var value2Text = "200"
  @State private var fillStyle: FillStyle = .red

  // Formula
  @State private var formulaText = "=A1>100"

  // Data Bars / Icon Sets
  @State private var dataBarColor: DataBarColorChoice = .blue
  @State private var iconSetStyle: IconSetStyle = .threeTrafficLights

  enum Segment: String, CaseIterable, Identifiable {
    case newRule = "New Rule"
    case manage = "Manage Rules"
    var id: String { rawValue }
  }

  enum RuleType: String, CaseIterable, Identifiable {
    case highlightCells = "Highlight Cells"
    case formula = "Formula"
    case colorScale = "Color Scale"
    case dataBars = "Data Bars"
    case iconSets = "Icon Sets"
    var id: String { rawValue }
  }

  enum HighlightKind: String, CaseIterable, Identifiable {
    case greaterThan = "Greater than"
    case lessThan = "Less than"
    case greaterOrEqual = "Greater or equal"
    case lessOrEqual = "Less or equal"
    case equal = "Equal to"
    case between = "Between"
    case textContains = "Text contains"
    case blanks = "Blanks"
    case nonBlanks = "Non-blanks"
    var id: String { rawValue }

    var needsValue: Bool {
      switch self {
      case .blanks, .nonBlanks: return false
      default: return true
      }
    }

    var needsSecondValue: Bool { self == .between }
  }

  enum FillStyle: String, CaseIterable, Identifiable {
    case red = "Light red"
    case yellow = "Light yellow"
    case green = "Light green"
    case blue = "Light blue"
    case orange = "Light orange"
    case purple = "Light purple"
    case gray = "Light gray"
    var id: String { rawValue }

    var style: ConditionalFormatStyle {
      switch self {
      case .red: return .redFill
      case .yellow: return .yellowFill
      case .green: return .greenFill
      case .blue: return .blueFill
      case .orange: return .orangeFill
      case .purple: return .purpleFill
      case .gray: return .grayFill
      }
    }
  }

  enum DataBarColorChoice: String, CaseIterable, Identifiable {
    case blue = "Blue"
    case green = "Green"
    var id: String { rawValue }

    var style: DataBarStyle {
      switch self {
      case .blue: return .blue
      case .green: return .green
      }
    }
  }

  private var selectionRangeLabel: String {
    Self.rangeLabel(viewModel.selectionRange)
  }

  private var rules: [ConditionalFormatRule] {
    viewModel.activeSheet.conditionalFormats
  }

  private var canApply: Bool {
    switch ruleType {
    case .highlightCells:
      return buildHighlightPredicate() != nil
    case .formula:
      return !normalizedFormula().isEmpty
    case .colorScale, .dataBars, .iconSets:
      return true
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      content
      Divider()
      footer
    }
    .frame(width: 440, height: 420)
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Conditional Formatting")
        .font(.title3.weight(.semibold))
      Text("Applies to selection \(selectionRangeLabel)")
        .font(.subheadline)
        .foregroundStyle(.secondary)
      Picker("Mode", selection: $segment) {
        ForEach(Segment.allCases) { item in
          Text(item.rawValue).tag(item)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
    }
    .padding(20)
    .padding(.bottom, 4)
  }

  @ViewBuilder
  private var content: some View {
    switch segment {
    case .newRule:
      newRulePane
    case .manage:
      managePane
    }
  }

  private var newRulePane: some View {
    Form {
      Picker("Type", selection: $ruleType) {
        ForEach(RuleType.allCases) { type in
          Text(type.rawValue).tag(type)
        }
      }

      switch ruleType {
      case .highlightCells:
        highlightFields
      case .formula:
        formulaFields
      case .colorScale:
        Text("Applies a 3-color scale across the selection (low → mid → high).")
          .foregroundStyle(.secondary)
      case .dataBars:
        Picker("Color", selection: $dataBarColor) {
          ForEach(DataBarColorChoice.allCases) { choice in
            Text(choice.rawValue).tag(choice)
          }
        }
      case .iconSets:
        Picker("Icon set", selection: $iconSetStyle) {
          ForEach(IconSetStyle.allCases, id: \.self) { style in
            Text(style.title).tag(style)
          }
        }
      }
    }
    .formStyle(.grouped)
    .padding(.horizontal, 8)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  @ViewBuilder
  private var highlightFields: some View {
    Picker("Rule", selection: $highlightKind) {
      ForEach(HighlightKind.allCases) { kind in
        Text(kind.rawValue).tag(kind)
      }
    }

    if highlightKind.needsValue {
      TextField(
        highlightKind == .textContains ? "Text" : "Value",
        text: $valueText
      )
    }

    if highlightKind.needsSecondValue {
      TextField("And", text: $value2Text)
    }

    Picker("Format", selection: $fillStyle) {
      ForEach(FillStyle.allCases) { style in
        Text(style.rawValue).tag(style)
      }
    }
  }

  private var formulaFields: some View {
    Group {
      TextField("Formula", text: $formulaText)
      Text("Evaluated relative to the top-left cell of the selection.")
        .font(.caption)
        .foregroundStyle(.secondary)
      Picker("Format", selection: $fillStyle) {
        ForEach(FillStyle.allCases) { style in
          Text(style.rawValue).tag(style)
        }
      }
    }
  }

  private var managePane: some View {
    Group {
      if rules.isEmpty {
        ContentUnavailableView(
          "No rules",
          systemImage: "paintpalette",
          description: Text("Create a rule on the New Rule tab.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        List {
          ForEach(rules) { rule in
            HStack(alignment: .top, spacing: 12) {
              VStack(alignment: .leading, spacing: 2) {
                Text(rule.predicate.title)
                  .font(.body.weight(.medium))
                Text(Self.rangeLabel(rule.range))
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer(minLength: 8)
              Button("Delete", role: .destructive) {
                viewModel.removeConditionalFormatRules(ids: [rule.id])
              }
              .buttonStyle(.borderless)
            }
            .padding(.vertical, 2)
          }
        }
        .listStyle(.inset)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var footer: some View {
    HStack {
      if segment == .manage {
        Button("Clear All", role: .destructive) {
          viewModel.replaceConditionalFormats([], actionName: "Clear Conditional Formats")
        }
        .disabled(rules.isEmpty)
      }
      Spacer()
      Button("Done") {
        onDismiss()
      }
      .keyboardShortcut(.cancelAction)
      .help("Close without applying another rule")

      if segment == .newRule {
        Button("Apply Rule") {
          applyNewRule()
        }
        .keyboardShortcut(.defaultAction)
        .buttonStyle(.borderedProminent)
        .disabled(!canApply)
        .help("Add this rule to the selection, then review in Manage Rules")
      }
    }
    .padding(16)
  }

  private func applyNewRule() {
    guard let rule = buildRule() else { return }
    viewModel.addConditionalFormatRule(rule)
    segment = .manage
  }

  private func buildRule() -> ConditionalFormatRule? {
    let range = viewModel.selectionRange
    switch ruleType {
    case .highlightCells:
      guard let predicate = buildHighlightPredicate() else { return nil }
      return ConditionalFormatRule(range: range, predicate: predicate, style: fillStyle.style)

    case .formula:
      let formula = normalizedFormula()
      guard !formula.isEmpty else { return nil }
      return ConditionalFormatRule(range: range, predicate: .formula(formula), style: fillStyle.style)

    case .colorScale:
      return ConditionalFormatRule(
        range: range,
        stopIfTrue: false,
        predicate: .colorScale(Self.defaultColorScaleStops),
        style: ConditionalFormatStyle()
      )

    case .dataBars:
      return ConditionalFormatRule(
        range: range,
        stopIfTrue: false,
        predicate: .dataBar(dataBarColor.style),
        style: ConditionalFormatStyle()
      )

    case .iconSets:
      return ConditionalFormatRule(
        range: range,
        stopIfTrue: false,
        predicate: .iconSet(iconSetStyle),
        style: ConditionalFormatStyle()
      )
    }
  }

  private func buildHighlightPredicate() -> ConditionalFormatPredicate? {
    switch highlightKind {
    case .greaterThan:
      guard let v = Self.parseNumber(valueText) else { return nil }
      return .greaterThan(v)
    case .lessThan:
      guard let v = Self.parseNumber(valueText) else { return nil }
      return .lessThan(v)
    case .greaterOrEqual:
      guard let v = Self.parseNumber(valueText) else { return nil }
      return .greaterOrEqual(v)
    case .lessOrEqual:
      guard let v = Self.parseNumber(valueText) else { return nil }
      return .lessOrEqual(v)
    case .equal:
      guard let v = Self.parseNumber(valueText) else { return nil }
      return .equal(v)
    case .between:
      guard let a = Self.parseNumber(valueText), let b = Self.parseNumber(value2Text) else { return nil }
      return .between(a, b)
    case .textContains:
      let text = valueText
      guard !text.isEmpty else { return nil }
      return .textContains(text)
    case .blanks:
      return .blanks
    case .nonBlanks:
      return .nonBlanks
    }
  }

  private func normalizedFormula() -> String {
    var formula = formulaText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !formula.isEmpty else { return "" }
    if !formula.hasPrefix("=") { formula = "=\(formula)" }
    return formula
  }

  private static func parseNumber(_ raw: String) -> Double? {
    Double(raw.replacingOccurrences(of: ",", with: ""))
  }

  private static func rangeLabel(_ range: CellRange) -> String {
    let n = range.normalized
    let start = CellAddress(row: n.minRow, col: n.minCol).a1
    let end = CellAddress(row: n.maxRow, col: n.maxCol).a1
    return start == end ? start : "\(start):\(end)"
  }

  private static let defaultColorScaleStops: [ColorScaleStop] = [
    ColorScaleStop(
      type: .min,
      value: nil,
      color: CodableColor(red: 0.99, green: 0.72, blue: 0.72, alpha: 1)
    ),
    ColorScaleStop(
      type: .percentile,
      value: 50,
      color: CodableColor(red: 1.0, green: 0.95, blue: 0.7, alpha: 1)
    ),
    ColorScaleStop(
      type: .max,
      value: nil,
      color: CodableColor(red: 0.72, green: 0.9, blue: 0.72, alpha: 1)
    ),
  ]
}

// MARK: - AppKit presenter

enum ConditionalFormattingPresenter {
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

    let rootView = ConditionalFormattingSheet(viewModel: viewModel) {
      controller.close()
    }
    let hosting = NSHostingController(rootView: rootView)
    let sheetWindow = NSWindow(contentViewController: hosting)
    sheetWindow.title = "Conditional Formatting"
    sheetWindow.styleMask = [.titled, .closable]
    sheetWindow.setContentSize(NSSize(width: 440, height: 420))
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
