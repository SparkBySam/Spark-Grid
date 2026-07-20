import AppKit
import SwiftUI

struct FormattingToolbar: View {
  @Bindable var viewModel: SpreadsheetViewModel
  @Bindable var store: SpreadsheetDocumentStore
  @Bindable private var settings = AppSettings.shared
  let undoManager: UndoManager?

  @State private var textColor: Color = .primary
  @State private var fillColor: Color = .clear
  @State private var borderColor: Color = .primary
  @State private var fontSizeText = "12"
  @State private var showTextPopover = false
  @State private var showFillPopover = false
  @State private var showBorderPopover = false
  /// Prevents ColorPicker `onChange` from writing synced swatch values back onto the selection.
  @State private var suppressColorApply = false

  private var showLabels: Bool { settings.showToolbarLabels }
  private var toolbarHeight: CGFloat { SpreadsheetChrome.toolbarHeight(showLabels: showLabels) }
  private var dividerHeight: CGFloat { showLabels ? 36 : 30 }
  private var iconAreaHeight: CGFloat { 24 }

  var body: some View {
    HStack(spacing: 0) {
      ScrollView(.horizontal, showsIndicators: false) {
        toolbarContent
          .fixedSize(horizontal: true, vertical: false)
      }
      .frame(maxWidth: .infinity)

      AutosaveStatusView(store: store)
        .padding(.horizontal, 10)
    }
    .frame(maxWidth: .infinity)
    .frame(height: toolbarHeight)
    .background(toolbarBackground)
    .overlay(alignment: .bottom) { Divider() }
    .onChange(of: viewModel.selection) { _, _ in
      syncColorsFromSelection()
      syncFontSizeFromSelection()
    }
    .onAppear {
      syncColorsFromSelection()
      syncFontSizeFromSelection()
    }
  }

  private var toolbarContent: some View {
    HStack(spacing: 8) {
      historyGroup
      toolbarDivider
      numberGroup
      toolbarDivider
      fontGroup
      toolbarDivider
      styleGroup
      toolbarDivider
      colorGroup
      toolbarDivider
      mergeGroup
      toolbarDivider
      alignGroup
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 4)
    .foregroundStyle(Color(nsColor: .labelColor))
  }

  private var toolbarBackground: Color {
    Color(nsColor: .controlBackgroundColor)
  }

  // MARK: - Groups

  private var historyGroup: some View {
    HStack(spacing: 4) {
      ToolbarIconButton(systemName: "arrow.uturn.backward", title: "Undo", showLabel: showLabels, active: false) {
        undoManager?.undo()
      }
      .disabled(!(undoManager?.canUndo ?? false))

      ToolbarIconButton(systemName: "arrow.uturn.forward", title: "Redo", showLabel: showLabels, active: false) {
        undoManager?.redo()
      }
      .disabled(!(undoManager?.canRedo ?? false))
    }
  }

  private var numberGroup: some View {
    HStack(spacing: 4) {
      ToolbarIconButton(
        systemName: "dollarsign",
        title: "Currency",
        showLabel: showLabels,
        active: viewModel.selectedFormat.numberFormat == .currency
      ) {
        viewModel.setNumberFormat(.currency)
      }

      ToolbarIconButton(
        systemName: "percent",
        title: "Percent",
        showLabel: showLabels,
        active: viewModel.selectedFormat.numberFormat == .percent
      ) {
        viewModel.setNumberFormat(.percent)
      }

      ToolbarDecimalButton(decrease: true, title: "Decimals", showLabel: showLabels) {
        viewModel.decreaseDecimalPlaces()
      }

      ToolbarDecimalButton(decrease: false, title: "Decimals", showLabel: showLabels) {
        viewModel.increaseDecimalPlaces()
      }

      ToolbarMenuButton(title: "Format", showLabel: showLabels, width: showLabels ? 44 : 32) {
        Button("General") { viewModel.setNumberFormat(.general) }
        Button("Number") { viewModel.setNumberFormat(.number) }
        Button("Scientific") { viewModel.setNumberFormat(.scientific) }
      } label: {
        Text("123")
          .font(.system(size: 13, weight: .medium, design: .monospaced))
      }
    }
  }

  private var fontGroup: some View {
    HStack(spacing: 8) {
      Picker("Font", selection: fontFamilyBinding) {
        ForEach(CellFormatRenderer.fontFamilies, id: \.self) { family in
          Text(family).tag(family)
        }
      }
      .labelsHidden()
      .frame(width: 130)

      HStack(spacing: 4) {
        ToolbarIconButton(systemName: "minus", title: "Smaller", showLabel: showLabels, active: false) {
          viewModel.adjustFontSize(by: -1)
          syncFontSizeFromSelection()
        }
        FontSizeTextField(text: $fontSizeText, onSubmit: applyFontSizeFromField)
          .frame(width: 32)
        ToolbarIconButton(systemName: "plus", title: "Larger", showLabel: showLabels, active: false) {
          viewModel.adjustFontSize(by: 1)
          syncFontSizeFromSelection()
        }
      }
    }
  }

  private var styleGroup: some View {
    HStack(spacing: 4) {
      ToolbarIconButton(systemName: "bold", title: "Bold", showLabel: showLabels, active: viewModel.selectedFormat.bold) {
        viewModel.toggleBold()
      }

      ToolbarIconButton(systemName: "italic", title: "Italic", showLabel: showLabels, active: viewModel.selectedFormat.italic) {
        viewModel.toggleItalic()
      }

      ToolbarIconButton(systemName: "strikethrough", title: "Strike", showLabel: showLabels, active: viewModel.selectedFormat.strikethrough) {
        viewModel.toggleStrikethrough()
      }

      ToolbarIconButton(systemName: "underline", title: "Underline", showLabel: showLabels, active: viewModel.selectedFormat.underline) {
        viewModel.toggleUnderline()
      }
    }
  }

  private var colorGroup: some View {
    HStack(spacing: 6) {
      ToolbarSwatchDisclosure(
        title: "Text",
        showLabel: showLabels,
        selection: $textColor,
        isPopoverPresented: $showTextPopover,
        suppressColorApply: suppressColorApply,
        onColorChange: { color in
          viewModel.setTextColor(CellFormatRenderer.codableColor(from: NSColor(color)))
        },
        icon: {
          Text("A")
            .font(.system(size: 15, weight: .semibold))
            .underline(true, color: textColor)
        },
        popoverContent: {
          ColorPicker("Color", selection: textColorBinding, supportsOpacity: false)
        }
      )

      ToolbarSwatchDisclosure(
        title: "Fill",
        showLabel: showLabels,
        selection: $fillColor,
        isPopoverPresented: $showFillPopover,
        suppressColorApply: suppressColorApply,
        onColorChange: applyFillColor,
        icon: {
          Image(systemName: "paintbrush.fill")
            .font(.system(size: 14))
            .foregroundStyle(fillColor == .clear ? Color(nsColor: .labelColor) : fillColor)
            .overlay(alignment: .bottom) {
              RoundedRectangle(cornerRadius: 1)
                .fill(fillColor == .clear ? Color(nsColor: .labelColor).opacity(0.25) : fillColor)
                .frame(height: 3)
                .padding(.horizontal, 1)
                .offset(y: 4)
            }
        },
        popoverContent: {
          VStack(alignment: .leading, spacing: 12) {
            ColorPicker("Color", selection: fillColorBinding, supportsOpacity: false)

            Button("No Fill") {
              suppressColorApply = true
              fillColor = .clear
              viewModel.setFillColor(nil)
              DispatchQueue.main.async { suppressColorApply = false }
              showFillPopover = false
            }
            .buttonStyle(.bordered)
          }
        }
      )

      ToolbarSwatchDisclosure(
        title: "Borders",
        showLabel: showLabels,
        selection: $borderColor,
        isPopoverPresented: $showBorderPopover,
        suppressColorApply: suppressColorApply,
        onColorChange: { color in
          viewModel.setBorderColor(CellFormatRenderer.codableColor(from: NSColor(color)))
        },
        icon: {
          Image(systemName: "square.split.2x2")
            .font(.system(size: 13))
            .overlay(alignment: .bottom) {
              BorderStylePreview(style: viewModel.borderStyle, color: borderColor)
                .frame(height: 3)
                .padding(.horizontal, 2)
                .offset(y: 3)
            }
        },
        popoverContent: {
          BorderPopoverContent(
            viewModel: viewModel,
            borderColor: borderColor,
            onApplyPreset: { preset in
              viewModel.applyBorderPreset(preset)
              showBorderPopover = false
            }
          )
        }
      )
    }
  }

  private var mergeGroup: some View {
    HStack(spacing: 4) {
      Menu {
        Button("Merge All") { viewModel.mergeSelection(axis: .all) }
          .disabled(!viewModel.canMergeSelection)
        Button("Merge Across") { viewModel.mergeSelection(axis: .horizontal) }
          .disabled(!viewModel.canMergeHorizontally)
        Button("Merge Vertically") { viewModel.mergeSelection(axis: .vertical) }
          .disabled(!viewModel.canMergeVertically)
        Divider()
        Button("Unmerge") { viewModel.unmergeSelection() }
          .disabled(!viewModel.canUnmergeSelection)
      } label: {
        VStack(spacing: 2) {
          Image(systemName: "rectangle.split.2x1")
            .font(.system(size: 13))
            .frame(width: showLabels ? 48 : 32, height: showLabels ? 24 : 32)
          if showLabels {
            Text("Merge")
              .font(.system(size: 9))
              .lineLimit(1)
          }
        }
        .frame(minWidth: 40)
        .contentShape(Rectangle())
      }
      .menuStyle(.borderlessButton)
      .help("Merge cells")
    }
  }

  private var alignGroup: some View {
    HStack(spacing: 4) {
      ToolbarMenuButton(title: "Align", showLabel: showLabels, width: 32) {
        Button { viewModel.setHorizontalAlign(.left) } label: {
          Label("Align left", systemImage: "text.alignleft")
        }
        Button { viewModel.setHorizontalAlign(.center) } label: {
          Label("Align center", systemImage: "text.aligncenter")
        }
        Button { viewModel.setHorizontalAlign(.right) } label: {
          Label("Align right", systemImage: "text.alignright")
        }
      } label: {
        Image(systemName: horizontalAlignIcon)
          .font(.system(size: 13))
      }

      ToolbarMenuButton(title: "Vertical", showLabel: showLabels, width: 32) {
        Button { viewModel.setVerticalAlign(.top) } label: {
          Label("Align top", systemImage: "arrow.up.to.line")
        }
        Button { viewModel.setVerticalAlign(.middle) } label: {
          Label("Align middle", systemImage: "arrow.up.and.down")
        }
        Button { viewModel.setVerticalAlign(.bottom) } label: {
          Label("Align bottom", systemImage: "arrow.down.to.line")
        }
      } label: {
        Image(systemName: "arrow.up.and.down.text.horizontal")
          .font(.system(size: 13))
      }

      ToolbarIconButton(systemName: "text.word.spacing", title: "Wrap", showLabel: showLabels, active: viewModel.selectedFormat.wrapText) {
        viewModel.toggleWrapText()
      }

      RotateToolbarMenu(
        viewModel: viewModel,
        showLabel: showLabels,
        iconHeight: iconAreaHeight
      )
    }
  }

  private var toolbarDivider: some View {
    Divider().frame(height: dividerHeight)
  }

  private var fontFamilyBinding: Binding<String> {
    Binding(
      get: { viewModel.selectedFormat.fontFamily ?? CellFormatRenderer.defaultFontFamily },
      set: { viewModel.setFontFamily($0) }
    )
  }

  private var textColorBinding: Binding<Color> {
    Binding(
      get: { textColor },
      set: { newColor in
        textColor = newColor
        guard !suppressColorApply else { return }
        viewModel.setTextColor(CellFormatRenderer.codableColor(from: NSColor(newColor)))
      }
    )
  }

  private var fillColorBinding: Binding<Color> {
    Binding(
      get: { fillColor },
      set: { newColor in
        fillColor = newColor
        applyFillColor(newColor)
      }
    )
  }

  private var horizontalAlignIcon: String {
    switch viewModel.selectedFormat.horizontalAlign {
    case .center: return "text.aligncenter"
    case .right: return "text.alignright"
    default: return "text.alignleft"
    }
  }

  private func syncColorsFromSelection() {
    suppressColorApply = true
    let format = viewModel.selectedFormat
    if let text = format.textColor, let ns = CellFormatRenderer.nsColor(text) {
      textColor = Color(nsColor: ns)
    } else {
      textColor = Color(nsColor: .labelColor)
    }
    if let fill = format.fillColor, let ns = CellFormatRenderer.nsColor(fill) {
      fillColor = Color(nsColor: ns)
    } else {
      fillColor = .clear
    }
    if let border = viewModel.borderColor, let ns = CellFormatRenderer.nsColor(border) {
      borderColor = Color(nsColor: ns)
    } else if let edgeColor = format.borders.top?.color
      ?? format.borders.bottom?.color
      ?? format.borders.left?.color
      ?? format.borders.right?.color,
      let ns = CellFormatRenderer.nsColor(edgeColor)
    {
      borderColor = Color(nsColor: ns)
    } else {
      borderColor = Color(nsColor: .labelColor)
    }
    // ColorPicker onChange runs after the binding update; clear on the next turn.
    DispatchQueue.main.async {
      suppressColorApply = false
    }
  }

  private func syncFontSizeFromSelection() {
    let size = Int(viewModel.selectedFormat.fontSize ?? CellFormatRenderer.defaultFontSize)
    fontSizeText = "\(size)"
  }

  private func applyFillColor(_ color: Color) {
    guard !suppressColorApply else { return }
    if color == .clear {
      viewModel.setFillColor(nil)
    } else {
      viewModel.setFillColor(CellFormatRenderer.codableColor(from: NSColor(color)))
    }
  }

  private func applyFontSizeFromField() {
    guard let size = Double(fontSizeText) else {
      syncFontSizeFromSelection()
      return
    }
    viewModel.setFontSize(CGFloat(size))
    syncFontSizeFromSelection()
  }
}

/// Font size field that can be typed into, but won't steal focus on app launch.
private struct FontSizeTextField: NSViewRepresentable {
  @Binding var text: String
  var onSubmit: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(text: $text, onSubmit: onSubmit)
  }

  func makeNSView(context: Context) -> ClickToFocusTextField {
    let field = ClickToFocusTextField(string: text)
    field.delegate = context.coordinator
    field.isBordered = false
    field.isBezeled = false
    field.drawsBackground = false
    field.focusRingType = .default
    field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
    field.alignment = .center
    return field
  }

  func updateNSView(_ field: ClickToFocusTextField, context: Context) {
    context.coordinator.onSubmit = onSubmit
    if field.stringValue != text {
      field.stringValue = text
    }
    field.delegate = context.coordinator
  }

  final class Coordinator: NSObject, NSTextFieldDelegate {
    @Binding var text: String
    var onSubmit: () -> Void

    init(text: Binding<String>, onSubmit: @escaping () -> Void) {
      _text = text
      self.onSubmit = onSubmit
    }

    func controlTextDidChange(_ notification: Notification) {
      guard let field = notification.object as? NSTextField else { return }
      let filtered = field.stringValue.filter(\.isNumber)
      if filtered != field.stringValue {
        field.stringValue = filtered
      }
      text = filtered
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
      if commandSelector == #selector(NSResponder.insertNewline(_:)) {
        onSubmit()
        control.window?.makeFirstResponder(nil)
        return true
      }
      return false
    }
  }
}

private final class ClickToFocusTextField: NSTextField {
  private var allowsKeyboardFocus = false

  override var acceptsFirstResponder: Bool {
    allowsKeyboardFocus
  }

  override func mouseDown(with event: NSEvent) {
    allowsKeyboardFocus = true
    window?.makeFirstResponder(self)
    super.mouseDown(with: event)
  }
}

// MARK: - Toolbar controls

/// Shared Text / Fill / Borders pattern: color swatch + disclosure popover.
private struct ToolbarSwatchDisclosure<Icon: View, PopoverContent: View>: View {
  let title: String
  var showLabel = false
  @Binding var selection: Color
  @Binding var isPopoverPresented: Bool
  var suppressColorApply = false
  let onColorChange: (Color) -> Void
  @ViewBuilder var icon: () -> Icon
  @ViewBuilder var popoverContent: () -> PopoverContent

  var body: some View {
    VStack(spacing: 2) {
      HStack(spacing: 0) {
        ColorPicker("", selection: $selection, supportsOpacity: false)
          .labelsHidden()
          .frame(width: 28, height: showLabel ? 24 : 32)
          .overlay {
            icon()
              .allowsHitTesting(false)
          }
          .onChange(of: selection) { _, color in
            guard !suppressColorApply else { return }
            onColorChange(color)
          }

        Button {
          isPopoverPresented.toggle()
        } label: {
          Image(systemName: "chevron.down")
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 14, height: showLabel ? 24 : 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(title) options")
        .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
          popoverContent()
            .padding(12)
            .frame(minWidth: 200)
        }
      }

      if showLabel {
        Text(title)
          .font(.system(size: 9))
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      }
    }
    .frame(minWidth: 48)
    .help(title)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(title)
  }
}

private struct BorderPopoverContent: View {
  @Bindable var viewModel: SpreadsheetViewModel
  var borderColor: Color
  var onApplyPreset: (BorderPreset) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Line Style")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)

      VStack(spacing: 2) {
        ForEach(BorderStyle.allCases, id: \.self) { style in
          Button {
            viewModel.setBorderStyle(style)
          } label: {
            HStack(spacing: 8) {
              BorderStylePreview(style: style, color: borderColor)
                .frame(width: 56, height: 12)
              Text(style.title)
                .foregroundStyle(Color(nsColor: .labelColor))
              Spacer(minLength: 0)
              if viewModel.borderStyle == style {
                Image(systemName: "checkmark")
                  .foregroundStyle(Color.accentColor)
              }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(
              viewModel.borderStyle == style
                ? Color.accentColor.opacity(0.12)
                : Color.clear,
              in: RoundedRectangle(cornerRadius: 4)
            )
          }
          .buttonStyle(.plain)
        }
      }

      Divider()

      Text("Borders")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)

      VStack(spacing: 2) {
        ForEach(BorderPreset.allCases, id: \.self) { preset in
          Button {
            onApplyPreset(preset)
          } label: {
            Label(preset.title, systemImage: preset.systemImage)
              .frame(maxWidth: .infinity, alignment: .leading)
              .contentShape(Rectangle())
              .padding(.horizontal, 6)
              .padding(.vertical, 5)
          }
          .buttonStyle(.plain)
        }
      }
    }
  }
}

private struct BorderStylePreview: View {
  var style: BorderStyle
  var color: Color

  var body: some View {
    Canvas { context, size in
      let stroke = color == .clear ? Color(nsColor: .labelColor) : color
      let y = size.height / 2
      var path = Path()

      switch style {
      case .thin, .medium, .thick:
        path.move(to: CGPoint(x: 0, y: y))
        path.addLine(to: CGPoint(x: size.width, y: y))
        context.stroke(
          path,
          with: .color(stroke),
          style: StrokeStyle(lineWidth: style == .thin ? 1 : (style == .medium ? 1.5 : 2.5))
        )
      case .dashed:
        path.move(to: CGPoint(x: 0, y: y))
        path.addLine(to: CGPoint(x: size.width, y: y))
        context.stroke(
          path,
          with: .color(stroke),
          style: StrokeStyle(lineWidth: 1.2, dash: [4, 2])
        )
      case .dotted:
        path.move(to: CGPoint(x: 0, y: y))
        path.addLine(to: CGPoint(x: size.width, y: y))
        context.stroke(
          path,
          with: .color(stroke),
          style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [0.5, 2.5])
        )
      case .double:
        var top = Path()
        top.move(to: CGPoint(x: 0, y: y - 1.5))
        top.addLine(to: CGPoint(x: size.width, y: y - 1.5))
        var bottom = Path()
        bottom.move(to: CGPoint(x: 0, y: y + 1.5))
        bottom.addLine(to: CGPoint(x: size.width, y: y + 1.5))
        context.stroke(top, with: .color(stroke), lineWidth: 1)
        context.stroke(bottom, with: .color(stroke), lineWidth: 1)
      }
    }
  }
}

private struct RotateToolbarMenu: View {
  @Bindable var viewModel: SpreadsheetViewModel
  var showLabel: Bool
  var iconHeight: CGFloat

  var body: some View {
    Menu {
      Button("None") { viewModel.setTextRotation(0) }
      Divider()
      Button("Tilt up") { viewModel.setTextRotation(-45) }
      Button("Tilt down") { viewModel.setTextRotation(45) }
      Button("Stack vertically") { viewModel.setTextRotation(90) }
      Button("Rotate up") { viewModel.setTextRotation(-90) }
      Button("Rotate down") { viewModel.setTextRotation(90) }
    } label: {
      VStack(spacing: 2) {
        TiltTextToolbarIcon(active: viewModel.selectedFormat.textRotation != 0, embedded: true)
          .frame(width: 32, height: showLabel ? iconHeight : 32)
        if showLabel {
          Text("Rotate")
            .font(.system(size: 9))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(Color(nsColor: .labelColor))
        }
      }
      .frame(minWidth: 40)
      .contentShape(Rectangle())
    }
    .menuStyle(.borderlessButton)
    .buttonStyle(.plain)
    .help("Text rotation")
  }
}

private struct TiltTextToolbarIcon: View {
  var active: Bool
  var embedded = false

  var body: some View {
    HStack(spacing: 1) {
      tiltedDashWithArrows
      Text("A")
        .font(.system(size: 12, weight: .semibold))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(backgroundColor, in: RoundedRectangle(cornerRadius: 4))
    .contentShape(Rectangle())
  }

  private var backgroundColor: Color {
    guard !embedded, active else { return .clear }
    return Color.accentColor.opacity(0.22)
  }

  private var tiltedDashWithArrows: some View {
    HStack(spacing: 0) {
      Image(systemName: "arrowtriangle.left.fill")
        .font(.system(size: 4.5))
      Rectangle()
        .frame(width: 7, height: 1.2)
      Image(systemName: "arrowtriangle.right.fill")
        .font(.system(size: 4.5))
    }
    .rotationEffect(.degrees(-50))
    .offset(y: 1)
  }
}

private struct ToolbarDecimalButton: View {
  let decrease: Bool
  let title: String
  var showLabel = false
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 2) {
        HStack(spacing: 1) {
          if decrease {
            Image(systemName: "chevron.left")
              .font(.system(size: 7, weight: .bold))
          }
          Text(".0")
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
          if !decrease {
            Image(systemName: "chevron.right")
              .font(.system(size: 7, weight: .bold))
          }
        }
        .frame(width: 32, height: showLabel ? 24 : 32)

        if showLabel {
          Text(title)
            .font(.system(size: 9))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
      }
      .frame(minWidth: 40)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(decrease ? "Decrease decimals" : "Increase decimals")
  }
}

private struct ToolbarIconButton: View {
  let systemName: String
  let title: String
  var showLabel = false
  var active = false
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 2) {
        Image(systemName: systemName)
          .font(.system(size: 13, weight: active ? .semibold : .regular))
          .frame(width: 32, height: showLabel ? 24 : 32)
          .background(active ? Color.accentColor.opacity(0.22) : Color.clear, in: RoundedRectangle(cornerRadius: 4))

        if showLabel {
          Text(title)
            .font(.system(size: 9))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
      }
      .frame(minWidth: 40)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(title)
  }
}

private struct ToolbarMenuButton<Label: View, MenuContent: View>: View {
  let title: String
  var showLabel = false
  var width: CGFloat = 32
  @ViewBuilder var menuContent: () -> MenuContent
  @ViewBuilder var label: () -> Label

  var body: some View {
    Menu {
      menuContent()
    } label: {
      VStack(spacing: 2) {
        label()
          .frame(width: width, height: showLabel ? 24 : 32)

        if showLabel {
          Text(title)
            .font(.system(size: 9))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: max(width, 40))
        }
      }
      .frame(minWidth: 40)
      .contentShape(Rectangle())
    }
    .menuStyle(.borderlessButton)
    .buttonStyle(.plain)
    .fixedSize(horizontal: true, vertical: false)
    .help(title)
  }
}
