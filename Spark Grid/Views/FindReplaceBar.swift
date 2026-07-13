import SwiftUI

struct FindReplaceBar: View {
  @Bindable var viewModel: SpreadsheetViewModel

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)

      TextField("Find", text: $viewModel.findQuery)
        .textFieldStyle(.roundedBorder)
        .frame(minWidth: 140, maxWidth: 220)
        .onSubmit { viewModel.findNext() }
        .onChange(of: viewModel.findQuery) { _, _ in
          viewModel.refreshFindMatches(selectCurrent: true)
        }

      if viewModel.isFindReplaceMode {
        TextField("Replace", text: $viewModel.findReplaceText)
          .textFieldStyle(.roundedBorder)
          .frame(minWidth: 120, maxWidth: 180)
      }

      Button("Previous") { viewModel.findPrevious() }
        .disabled(viewModel.findMatches.isEmpty)
      Button("Next") { viewModel.findNext() }
        .disabled(viewModel.findMatches.isEmpty)

      if viewModel.isFindReplaceMode {
        Button("Replace") { _ = viewModel.replaceCurrent() }
          .disabled(viewModel.findMatches.isEmpty)
        Button("Replace All") { _ = viewModel.replaceAll() }
          .disabled(viewModel.findMatches.isEmpty)
      }

      Toggle("Match Case", isOn: $viewModel.findMatchCase)
        .toggleStyle(.checkbox)
        .onChange(of: viewModel.findMatchCase) { _, _ in
          viewModel.refreshFindMatches(selectCurrent: true)
        }
      Toggle("Entire Cell", isOn: $viewModel.findEntireCell)
        .toggleStyle(.checkbox)
        .onChange(of: viewModel.findEntireCell) { _, _ in
          viewModel.refreshFindMatches(selectCurrent: true)
        }

      HStack(spacing: 6) {
        Text("Scope")
          .foregroundStyle(.secondary)
          .fixedSize()
        Picker("Scope", selection: $viewModel.findScope) {
          Text("Sheet").tag(FindScope.sheet)
          Text("Selection").tag(FindScope.selection)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 160)
      }
      .onChange(of: viewModel.findScope) { _, _ in
        viewModel.refreshFindMatches(selectCurrent: true)
      }

      if !viewModel.findMatches.isEmpty {
        Text(matchLabel)
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }

      Spacer(minLength: 0)

      Button {
        viewModel.hideFindBar()
      } label: {
        Image(systemName: "xmark.circle.fill")
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
      .help("Close")
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(Color(nsColor: .controlBackgroundColor))
  }

  private var matchLabel: String {
    let index = viewModel.findMatchIndex + 1
    return "\(index) of \(viewModel.findMatches.count)"
  }
}
