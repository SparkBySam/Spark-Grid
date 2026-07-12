import AppKit
import SwiftUI

struct FormulaBarView: View {
  @Bindable var viewModel: SpreadsheetViewModel
  @Bindable var store: SpreadsheetDocumentStore

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        Text(viewModel.selection.a1)
          .font(.system(.body, design: .monospaced))
          .foregroundStyle(.secondary)
          .frame(width: 48, alignment: .trailing)

        Divider()

        FormulaBarTextField(
          text: Binding(
            get: { viewModel.formulaBarText },
            set: { viewModel.formulaBarText = $0 }
          ),
          liveText: viewModel.formulaBarText,
          namedRanges: Array(viewModel.workbook.namedRanges.keys),
          highlights: viewModel.formulaReferenceHighlights,
          focusedHighlightIndex: viewModel.focusedFormulaHighlightIndex,
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
        .frame(maxWidth: .infinity, minHeight: 22, maxHeight: 22)

        Divider()

        AutosaveStatusView(store: store)
          .padding(.trailing, 2)
      }
      .padding(.horizontal, 10)
      .frame(height: 28)

      if let explanation = viewModel.selectedFormulaErrorExplanation {
        FormulaErrorBanner(text: explanation)
      }
    }
    .frame(maxWidth: .infinity)
    .background(Color(nsColor: .controlBackgroundColor))
    .foregroundStyle(Color(nsColor: .labelColor))
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
    .padding(.vertical, 6)
    .background(Color(nsColor: .systemRed).opacity(0.12))
    .overlay(alignment: .top) {
      Rectangle()
        .fill(Color(nsColor: .systemRed).opacity(0.35))
        .frame(height: 1)
    }
  }
}
