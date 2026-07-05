import AppKit
import SwiftUI

struct FormattingToolbar: View {
  @Bindable var viewModel: SpreadsheetViewModel
  @Bindable private var settings = AppSettings.shared
  let undoManager: UndoManager?

  @State private var textColor: Color = .primary
  @State private var fillColor: Color = .clear
  @State private var fontSizeText = "12"

  private var showLabels: Bool { settings.showToolbarLabels }
  private var toolbarHeight: CGFloat { 58 }
  private var dividerHeight: CGFloat { showLabels ? 36 : 30 }
  private var iconAreaHeight: CGFloat { 24 }

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      toolbarContent
        .fixedSize(horizontal: true, vertical: false)
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
        Button("Currency") { viewModel.setNumberFormat(.currency) }
        Button("Percent") { viewModel.setNumberFormat(.percent) }
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
        TextField("", text: $fontSizeText)
          .font(.system(size: 12, design: .monospaced))
          .multilineTextAlignment(.center)
          .frame(width: 32)
          .textFieldStyle(.plain)
          .onSubmit(applyFontSizeFromField)
          .onChange(of: fontSizeText) { _, newValue in
            let filtered = newValue.filter(\.isNumber)
            if filtered != newValue { fontSizeText = filtered }
          }
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
    HStack(spacing: 0) {
      ToolbarColorPicker(
        title: "Text",
        showLabel: showLabels,
        label: {
          Text("A")
            .font(.system(size: 15, weight: .semibold))
            .underline(true, color: textColor)
        },
        selection: $textColor
      ) { color in
        viewModel.setTextColor(CellFormatRenderer.codableColor(from: NSColor(color)))
      }

      toolbarDivider
        .padding(.horizontal, 6)

      ToolbarColorPicker(
        title: "Fill",
        showLabel: showLabels,
        label: {
          Image(systemName: "paintbrush.fill")
            .font(.system(size: 14))
            .foregroundStyle(fillColor == .clear ? Color(nsColor: .labelColor) : fillColor)
        },
        selection: $fillColor
      ) { color in
        viewModel.setFillColor(CellFormatRenderer.codableColor(from: NSColor(color)))
      }
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

  private var horizontalAlignIcon: String {
    switch viewModel.selectedFormat.horizontalAlign {
    case .center: return "text.aligncenter"
    case .right: return "text.alignright"
    default: return "text.alignleft"
    }
  }

  private func syncColorsFromSelection() {
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
  }

  private func syncFontSizeFromSelection() {
    let size = Int(viewModel.selectedFormat.fontSize ?? CellFormatRenderer.defaultFontSize)
    fontSizeText = "\(size)"
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

// MARK: - Toolbar controls

private struct RotateToolbarMenu: View {
  @Bindable var viewModel: SpreadsheetViewModel
  var iconHeight: CGFloat

  private let labelHeight: CGFloat = 46

  var body: some View {
    ZStack {
      VStack(spacing: 2) {
        TiltTextToolbarIcon(active: viewModel.selectedFormat.textRotation != 0, embedded: true)
          .frame(width: 32, height: iconHeight)
        Text("Rotate")
          .font(.system(size: 9))
          .lineLimit(1)
          .minimumScaleFactor(0.8)
          .foregroundStyle(Color(nsColor: .labelColor))
      }
      .frame(minWidth: 40)
      .allowsHitTesting(false)

      Menu {
        Button("None") { viewModel.setTextRotation(0) }
        Divider()
        Button("Tilt up") { viewModel.setTextRotation(-45) }
        Button("Tilt down") { viewModel.setTextRotation(45) }
        Button("Stack vertically") { viewModel.setTextRotation(90) }
        Button("Rotate up") { viewModel.setTextRotation(-90) }
        Button("Rotate down") { viewModel.setTextRotation(90) }
      } label: {
        Color.clear
          .frame(width: 44, height: labelHeight)
          .contentShape(Rectangle())
      }
      .menuStyle(.borderlessButton)
      .buttonStyle(.plain)
    }
    .frame(width: 44, height: labelHeight)
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

private struct ToolbarColorPicker<Label: View>: View {
  let title: String
  var showLabel = false
  @ViewBuilder var label: () -> Label
  @Binding var selection: Color
  let onChange: (Color) -> Void

  var body: some View {
  VStack(spacing: 2) {
      ColorPicker("", selection: $selection, supportsOpacity: false)
        .labelsHidden()
        .frame(width: 32, height: showLabel ? 24 : 32)
        .overlay {
          label()
            .allowsHitTesting(false)
        }
        .background(Color.clear, in: RoundedRectangle(cornerRadius: 4))
        .contentShape(RoundedRectangle(cornerRadius: 4))
        .onChange(of: selection) { _, color in
          onChange(color)
        }

      if showLabel {
        Text(title)
          .font(.system(size: 9))
          .lineLimit(1)
          .allowsHitTesting(false)
      }
    }
    .frame(minWidth: 40)
    .help(title)
  }
}
