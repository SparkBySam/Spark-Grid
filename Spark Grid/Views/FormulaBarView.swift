import AppKit
import SwiftUI

struct FormulaBarView: View {
  @Bindable var viewModel: SpreadsheetViewModel
  @Bindable var store: SpreadsheetDocumentStore

  var body: some View {
    HStack(spacing: 8) {
      Text(viewModel.selection.a1)
        .font(.system(.body, design: .monospaced))
        .foregroundStyle(.secondary)
        .frame(width: 48, alignment: .trailing)

      Divider()

      TextField("Cell value", text: Binding(
        get: { viewModel.formulaBarText },
        set: { viewModel.formulaBarText = $0 }
      ))
      .textFieldStyle(.plain)
      .font(.system(.body, design: .monospaced))
      .onSubmit { viewModel.applyFormulaBar() }

      Divider()

      AutosaveStatusView(store: store)
        .padding(.trailing, 2)
    }
    .padding(.horizontal, 10)
    .frame(height: 28)
    .frame(maxWidth: .infinity)
    .background(Color(nsColor: .controlBackgroundColor))
    .foregroundStyle(Color(nsColor: .labelColor))
    .fixedSize(horizontal: false, vertical: true)
  }
}
