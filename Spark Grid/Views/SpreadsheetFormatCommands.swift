import AppKit
import SwiftUI

struct SpreadsheetFormatCommands: Commands {
  @FocusedValue(\.spreadsheetViewModel) private var viewModel: SpreadsheetViewModel?

  var body: some Commands {
    CommandMenu("Format") {
      Menu("Conditional Formatting") {
        Button("Highlight Cells Rules…") {
          presentHighlightCellsDialog()
        }
        .disabled(viewModel == nil)

        Button("New Formula Rule…") {
          presentFormulaRuleDialog()
        }
        .disabled(viewModel == nil)

        Button("Color Scale…") {
          presentColorScaleDialog()
        }
        .disabled(viewModel == nil)

        Divider()

        Button("Clear Rules from Selection") {
          guard let viewModel else { return }
          viewModel.clearConditionalFormats(intersecting: viewModel.selectionRange)
        }
        .disabled(viewModel == nil || viewModel?.activeSheet.conditionalFormats.isEmpty == true)

        Button("Manage Rules…") {
          presentManageRulesDialog()
        }
        .disabled(viewModel == nil || viewModel?.activeSheet.conditionalFormats.isEmpty == true)
      }
    }
  }

  private func presentHighlightCellsDialog() {
    guard let viewModel else { return }
    let alert = NSAlert()
    alert.messageText = "Highlight Cells"
    alert.informativeText = "Apply a fill when cell values in the selection match the rule."
    alert.alertStyle = .informational
    alert.addButton(withTitle: "Apply")
    alert.addButton(withTitle: "Cancel")

    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 8

    let rulePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let ruleTitles = [
      "Greater than",
      "Less than",
      "Greater or equal",
      "Less or equal",
      "Equal to",
      "Between",
      "Text contains",
      "Blanks",
      "Non-blanks",
    ]
    ruleTitles.forEach { rulePopup.addItem(withTitle: $0) }

    let valueField = NSTextField(string: "100")
    valueField.placeholderString = "Value"
    let value2Field = NSTextField(string: "200")
    value2Field.placeholderString = "Upper value"
    value2Field.isHidden = true

    let colorPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    colorPopup.addItem(withTitle: "Light red fill")
    colorPopup.addItem(withTitle: "Yellow fill")
    colorPopup.addItem(withTitle: "Green fill")

    stack.addArrangedSubview(labeled("Rule", rulePopup))
    stack.addArrangedSubview(labeled("Value", valueField))
    stack.addArrangedSubview(labeled("And", value2Field))
    stack.addArrangedSubview(labeled("Format", colorPopup))

    valueField.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
    value2Field.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
    rulePopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
    colorPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true

    let syncFields = {
      let index = rulePopup.indexOfSelectedItem
      let needsValue = index <= 6
      let needsSecond = index == 5
      valueField.isHidden = !needsValue || index >= 7
      value2Field.isHidden = !needsSecond
      if index == 6 {
        valueField.placeholderString = "Text"
        if valueField.stringValue == "100" { valueField.stringValue = "" }
      } else {
        valueField.placeholderString = "Value"
      }
    }
    rulePopup.target = FilterPopupTarget.shared
    rulePopup.action = #selector(FilterPopupTarget.shared.popupChanged(_:))
    FilterPopupTarget.shared.handler = syncFields
    syncFields()

    stack.frame = NSRect(x: 0, y: 0, width: 260, height: 160)
    alert.accessoryView = stack

    guard alert.runModal() == .alertFirstButtonReturn else { return }

    let style: ConditionalFormatStyle
    switch colorPopup.indexOfSelectedItem {
    case 1: style = .yellowFill
    case 2: style = .greenFill
    default: style = .redFill
    }

    let predicate: ConditionalFormatPredicate?
    switch rulePopup.indexOfSelectedItem {
    case 0:
      guard let v = Double(valueField.stringValue.replacingOccurrences(of: ",", with: "")) else { return }
      predicate = .greaterThan(v)
    case 1:
      guard let v = Double(valueField.stringValue.replacingOccurrences(of: ",", with: "")) else { return }
      predicate = .lessThan(v)
    case 2:
      guard let v = Double(valueField.stringValue.replacingOccurrences(of: ",", with: "")) else { return }
      predicate = .greaterOrEqual(v)
    case 3:
      guard let v = Double(valueField.stringValue.replacingOccurrences(of: ",", with: "")) else { return }
      predicate = .lessOrEqual(v)
    case 4:
      guard let v = Double(valueField.stringValue.replacingOccurrences(of: ",", with: "")) else { return }
      predicate = .equal(v)
    case 5:
      guard
        let a = Double(valueField.stringValue.replacingOccurrences(of: ",", with: "")),
        let b = Double(value2Field.stringValue.replacingOccurrences(of: ",", with: ""))
      else { return }
      predicate = .between(a, b)
    case 6:
      let text = valueField.stringValue
      guard !text.isEmpty else { return }
      predicate = .textContains(text)
    case 7:
      predicate = .blanks
    case 8:
      predicate = .nonBlanks
    default:
      predicate = nil
    }
    guard let predicate else { return }

    let rule = ConditionalFormatRule(
      range: viewModel.selectionRange,
      predicate: predicate,
      style: style
    )
    viewModel.addConditionalFormatRule(rule)
  }

  private func presentColorScaleDialog() {
    guard let viewModel else { return }
    let alert = NSAlert()
    alert.messageText = "Color Scale"
    alert.informativeText = "Apply a 3-color scale across the selection (low → mid → high)."
    alert.alertStyle = .informational
    alert.addButton(withTitle: "Apply")
    alert.addButton(withTitle: "Cancel")
    guard alert.runModal() == .alertFirstButtonReturn else { return }

    let stops = [
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
    let rule = ConditionalFormatRule(
      range: viewModel.selectionRange,
      stopIfTrue: false,
      predicate: .colorScale(stops),
      style: ConditionalFormatStyle()
    )
    viewModel.addConditionalFormatRule(rule)
  }

  private func presentFormulaRuleDialog() {
    guard let viewModel else { return }
    let alert = NSAlert()
    alert.messageText = "New Formula Rule"
    alert.informativeText = "Formula is evaluated relative to the top-left cell of the selection (Excel-style)."
    alert.alertStyle = .informational
    alert.addButton(withTitle: "Apply")
    alert.addButton(withTitle: "Cancel")

    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 8

    let formulaField = NSTextField(string: "=A1>100")
    formulaField.placeholderString = "=A1>100"
    let colorPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    colorPopup.addItem(withTitle: "Light red fill")
    colorPopup.addItem(withTitle: "Yellow fill")
    colorPopup.addItem(withTitle: "Green fill")

    stack.addArrangedSubview(labeled("Formula", formulaField))
    stack.addArrangedSubview(labeled("Format", colorPopup))
    formulaField.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
    stack.frame = NSRect(x: 0, y: 0, width: 300, height: 90)
    alert.accessoryView = stack

    guard alert.runModal() == .alertFirstButtonReturn else { return }
    var formula = formulaField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !formula.isEmpty else { return }
    if !formula.hasPrefix("=") { formula = "=\(formula)" }

    let style: ConditionalFormatStyle
    switch colorPopup.indexOfSelectedItem {
    case 1: style = .yellowFill
    case 2: style = .greenFill
    default: style = .redFill
    }

    let rule = ConditionalFormatRule(
      range: viewModel.selectionRange,
      predicate: .formula(formula),
      style: style
    )
    viewModel.addConditionalFormatRule(rule)
  }

  private func presentManageRulesDialog() {
    guard let viewModel else { return }
    let rules = viewModel.activeSheet.conditionalFormats
    guard !rules.isEmpty else { return }

    let alert = NSAlert()
    alert.messageText = "Conditional Formatting Rules"
    alert.informativeText = rules.enumerated().map { index, rule in
      let n = rule.range.normalized
      let rangeText = "\(CellAddress(row: n.minRow, col: n.minCol).a1):\(CellAddress(row: n.maxRow, col: n.maxCol).a1)"
      return "\(index + 1). \(rule.predicate.title) — \(rangeText)"
    }.joined(separator: "\n")
    alert.alertStyle = .informational
    alert.addButton(withTitle: "Delete Selected…")
    alert.addButton(withTitle: "Clear All")
    alert.addButton(withTitle: "Done")

    let response = alert.runModal()
    if response == .alertFirstButtonReturn {
      presentDeleteRulePicker(rules: rules, viewModel: viewModel)
    } else if response == .alertSecondButtonReturn {
      viewModel.replaceConditionalFormats([], actionName: "Clear Conditional Formats")
    }
  }

  private func presentDeleteRulePicker(rules: [ConditionalFormatRule], viewModel: SpreadsheetViewModel) {
    let alert = NSAlert()
    alert.messageText = "Delete Rule"
    alert.informativeText = "Choose which rule to remove."
    alert.addButton(withTitle: "Delete")
    alert.addButton(withTitle: "Cancel")

    let popup = NSPopUpButton(frame: .zero, pullsDown: false)
    for (index, rule) in rules.enumerated() {
      popup.addItem(withTitle: "\(index + 1). \(rule.predicate.title)")
      popup.lastItem?.representedObject = rule.id
    }
    popup.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
    alert.accessoryView = popup

    guard alert.runModal() == .alertFirstButtonReturn,
          let id = popup.selectedItem?.representedObject as? UUID
    else { return }
    viewModel.removeConditionalFormatRules(ids: [id])
  }

  private func labeled(_ title: String, _ view: NSView) -> NSView {
    let row = NSStackView()
    row.orientation = .horizontal
    row.spacing = 8
    let label = NSTextField(labelWithString: title)
    label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
    row.addArrangedSubview(label)
    row.addArrangedSubview(view)
    return row
  }
}

/// Tiny target so popup changes can refresh accessory fields.
private final class FilterPopupTarget: NSObject {
  static let shared = FilterPopupTarget()
  var handler: (() -> Void)?

  @objc func popupChanged(_ sender: Any?) {
    handler?()
  }
}
