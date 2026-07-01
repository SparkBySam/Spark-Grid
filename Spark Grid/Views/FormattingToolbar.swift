import AppKit
import SwiftUI

struct FormattingToolbar: View {
  @Bindable var viewModel: SpreadsheetViewModel
  let undoManager: UndoManager?

  @State private var textColor: Color = .primary
  @State private var fillColor: Color = .clear

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      toolbarContent
        .fixedSize(horizontal: true, vertical: false)
    }
    .frame(maxWidth: .infinity)
    .frame(height: 44)
    .background(toolbarBackground)
    .overlay(alignment: .bottom) { Divider() }
    .onChange(of: viewModel.selection) { _, _ in syncColorsFromSelection() }
    .onAppear { syncColorsFromSelection() }
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
      ToolbarIconButton(systemName: "arrow.uturn.backward", tooltip: "Undo", active: false) {
        undoManager?.undo()
      }
      .disabled(!(undoManager?.canUndo ?? false))

      ToolbarIconButton(systemName: "arrow.uturn.forward", tooltip: "Redo", active: false) {
        undoManager?.redo()
      }
      .disabled(!(undoManager?.canRedo ?? false))
    }
  }

  private var numberGroup: some View {
    HStack(spacing: 4) {
      ToolbarIconButton(
        systemName: "dollarsign",
        tooltip: "Currency",
        active: viewModel.selectedFormat.numberFormat == .currency
      ) {
        viewModel.setNumberFormat(.currency)
      }

      ToolbarIconButton(
        systemName: "percent",
        tooltip: "Percent",
        active: viewModel.selectedFormat.numberFormat == .percent
      ) {
        viewModel.setNumberFormat(.percent)
      }

      ToolbarIconButton(systemName: "decrease.decimal", tooltip: "Decrease decimals", active: false) {
        viewModel.decreaseDecimalPlaces()
      }

      ToolbarIconButton(systemName: "increase.decimal", tooltip: "Increase decimals", active: false) {
        viewModel.increaseDecimalPlaces()
      }

      Menu {
        Button("General") { viewModel.setNumberFormat(.general) }
        Button("Number") { viewModel.setNumberFormat(.number) }
        Button("Currency") { viewModel.setNumberFormat(.currency) }
        Button("Percent") { viewModel.setNumberFormat(.percent) }
        Button("Scientific") { viewModel.setNumberFormat(.scientific) }
      } label: {
        Text("123")
          .font(.system(size: 13, weight: .medium, design: .monospaced))
          .frame(width: 32, height: 32)
          .contentShape(RoundedRectangle(cornerRadius: 4))
      }
      .menuStyle(.button)
      .buttonStyle(.plain)
      .help("Number format")
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
        ToolbarIconButton(systemName: "minus", tooltip: "Smaller", active: false) {
          viewModel.adjustFontSize(by: -1)
        }
        Text("\(Int(viewModel.selectedFormat.fontSize ?? CellFormatRenderer.defaultFontSize))")
          .font(.system(size: 12, design: .monospaced))
          .frame(width: 24)
        ToolbarIconButton(systemName: "plus", tooltip: "Larger", active: false) {
          viewModel.adjustFontSize(by: 1)
        }
      }
    }
  }

  private var styleGroup: some View {
    HStack(spacing: 4) {
      ToolbarIconButton(systemName: "bold", tooltip: "Bold", active: viewModel.selectedFormat.bold) {
        viewModel.toggleBold()
      }

      ToolbarIconButton(systemName: "italic", tooltip: "Italic", active: viewModel.selectedFormat.italic) {
        viewModel.toggleItalic()
      }

      ToolbarIconButton(systemName: "strikethrough", tooltip: "Strikethrough", active: viewModel.selectedFormat.strikethrough) {
        viewModel.toggleStrikethrough()
      }

      ToolbarIconButton(systemName: "underline", tooltip: "Underline", active: viewModel.selectedFormat.underline) {
        viewModel.toggleUnderline()
      }
    }
  }

  private var colorGroup: some View {
    HStack(spacing: 0) {
      ToolbarColorPicker(
        tooltip: "Text color",
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
        tooltip: "Fill color",
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
      ToolbarMenuButton(tooltip: "Horizontal align", width: 32) {
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
      }

      ToolbarMenuButton(tooltip: "Vertical align", width: 32) {
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
      }

      ToolbarIconButton(systemName: "text.word.spacing", tooltip: "Wrap text", active: viewModel.selectedFormat.wrapText) {
        viewModel.toggleWrapText()
      }
    }
  }

  private var toolbarDivider: some View {
    Divider().frame(height: 24)
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
}

// MARK: - Toolbar controls

private struct ToolbarIconButton: View {
  let systemName: String
  let tooltip: String
  var active = false
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: 13, weight: active ? .semibold : .regular))
        .frame(width: 32, height: 32)
        .background(active ? Color.accentColor.opacity(0.22) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
        .contentShape(RoundedRectangle(cornerRadius: 4))
    }
    .buttonStyle(.plain)
    .help(tooltip)
  }
}

private struct ToolbarMenuButton<Label: View, MenuContent: View>: View {
  let tooltip: String
  var width: CGFloat = 32
  @ViewBuilder var menuContent: () -> MenuContent
  @ViewBuilder var label: () -> Label

  var body: some View {
    Menu {
      menuContent()
    } label: {
      label()
        .frame(width: width, height: 32)
        .background(Color.clear, in: RoundedRectangle(cornerRadius: 4))
        .contentShape(RoundedRectangle(cornerRadius: 4))
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .help(tooltip)
  }
}

private struct ToolbarColorPicker<Label: View>: View {
  let tooltip: String
  @ViewBuilder var label: () -> Label
  @Binding var selection: Color
  let onChange: (Color) -> Void

  var body: some View {
    ColorPicker("", selection: $selection, supportsOpacity: false)
      .labelsHidden()
      .frame(width: 32, height: 32)
      .overlay {
        label()
          .allowsHitTesting(false)
      }
      .background(Color.clear, in: RoundedRectangle(cornerRadius: 4))
      .contentShape(RoundedRectangle(cornerRadius: 4))
      .help(tooltip)
      .onChange(of: selection) { _, color in
        onChange(color)
      }
  }
}
