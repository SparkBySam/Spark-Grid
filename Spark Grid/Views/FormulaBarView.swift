import AppKit
import SwiftUI

struct FormulaBarView: View {
  @Bindable var viewModel: SpreadsheetViewModel
  @Binding var isExpanded: Bool

  private var contentLineCount: Int {
    SpreadsheetChrome.formulaBarContentLineCount(for: viewModel.formulaBarText)
  }

  private var viewportLineCount: Int {
    SpreadsheetChrome.formulaBarViewportLineCount(
      contentLines: contentLineCount,
      expanded: isExpanded
    )
  }

  private var barHeight: CGFloat {
    SpreadsheetChrome.formulaBarHeight(lineCount: viewportLineCount)
  }

  private var fieldHeight: CGFloat {
    SpreadsheetChrome.formulaFieldHeight(lineCount: viewportLineCount)
  }

  @State private var showFunctionList = false

  private var argumentHint: String? {
    guard viewModel.showsFormulaArgumentHint else { return nil }
    return viewModel.formulaArgumentHint
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(alignment: .top, spacing: 8) {
        Text(viewModel.selection.a1)
          .font(.system(.body, design: .monospaced))
          .foregroundStyle(.secondary)
          .frame(width: 48, alignment: .trailing)
          .padding(.top, 4)

        Rectangle()
          .fill(SpreadsheetChrome.chromeDividerColor)
          .frame(width: SpreadsheetChrome.dividerHeight, height: barHeight)

        VStack(alignment: .leading, spacing: 0) {
          HStack(alignment: .top, spacing: 8) {
            functionButton
            FormulaBarTextField(
              text: Binding(
                get: { viewModel.formulaBarText },
                set: { viewModel.formulaBarText = $0 }
              ),
              liveText: viewModel.formulaBarText,
              caretToken: viewModel.formulaCaretToken,
              caretUTF16: viewModel.formulaCaretUTF16,
              namedRanges: Array(viewModel.workbook.namedRanges.keys),
              highlights: viewModel.formulaReferenceHighlights,
              focusedHighlightIndex: viewModel.focusedFormulaHighlightIndex,
              visibleHeight: fieldHeight,
              onSubmit: { text in
                viewModel.commitFormulaBarText(text)
              },
              onTextChange: {},
              onBeginEditing: {
                if !viewModel.isEditing {
                  viewModel.beginEditing()
                }
              },
              onCaretMoved: { index in
                viewModel.updateFormulaHighlightFocus(atUTF16: index)
              }
            )
            .frame(maxWidth: .infinity, minHeight: fieldHeight, maxHeight: fieldHeight)
            .padding(.vertical, 5)
          }
          .frame(height: barHeight)

          if let argumentHint {
            Text(argumentHint)
              .font(.system(size: 11))
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .padding(.leading, 36)
              .frame(maxWidth: .infinity, alignment: .leading)
              .frame(height: SpreadsheetChrome.formulaArgumentHintHeight)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.horizontal, 10)
      .contentShape(Rectangle())
      .onTapGesture(count: 2) {
        guard contentLineCount > 1 else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
          isExpanded.toggle()
        }
      }
      .help(
        contentLineCount > 1
          ? (isExpanded ? "Double-click to collapse formula bar" : "Double-click to expand formula bar")
          : "Formula bar"
      )

      if let explanation = viewModel.selectedFormulaErrorExplanation {
        FormulaErrorBanner(text: explanation)
      }
    }
    .frame(maxWidth: .infinity)
    .background(Color(nsColor: .controlBackgroundColor))
    .foregroundStyle(Color(nsColor: .labelColor))
    .onChange(of: viewModel.selection) { _, _ in
      isExpanded = false
    }
  }

  /// Excel-style fx, between the name box and the formula text.
  private var functionButton: some View {
    Button {
      showFunctionList.toggle()
    } label: {
      Text("fx")
        .font(.system(size: 14, weight: .medium, design: .serif))
        .italic()
        .frame(width: 28, height: 22)
    }
    .buttonStyle(.plain)
    .foregroundStyle(Color(nsColor: .labelColor))
    .padding(.top, 3)
    .help("Insert function")
    .accessibilityLabel("Insert function")
    .popover(isPresented: $showFunctionList, arrowEdge: .bottom) {
      FormulaFunctionPicker(
        onChoose: { name in
          viewModel.insertFormulaFunction(name)
          showFunctionList = false
        },
        onClose: {
          showFunctionList = false
        }
      )
    }
  }
}

/// Sheets-style callout under the formula bar when the selected cell is an error.
private struct FormulaErrorBanner: View {
  let text: String

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(Color(nsColor: .systemRed))
        .font(.system(size: 12))
        .padding(.top, 1)
      Text(text)
        .font(.system(size: 11))
        .foregroundStyle(Color(nsColor: .labelColor))
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, 12)
    .frame(height: SpreadsheetChrome.formulaErrorBannerHeight)
    .background(Color(nsColor: .systemRed).opacity(0.12))
    .overlay(alignment: .top) {
      Rectangle()
        .fill(Color(nsColor: .systemRed).opacity(0.35))
        .frame(height: 1)
    }
  }
}
