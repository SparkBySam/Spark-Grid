import SwiftUI

struct SheetTabsView: View {
  @Bindable var viewModel: SpreadsheetViewModel
  @State private var sheetToRename: Int?
  @State private var renameText = ""

  var body: some View {
    HStack(spacing: 0) {
      Button(action: viewModel.addSheet) {
        Image(systemName: "plus")
          .font(.system(size: 12, weight: .semibold))
          .frame(width: 28, height: 28)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help("Add sheet")

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 0) {
          ForEach(Array(viewModel.workbook.sheets.enumerated()), id: \.element.id) { index, sheet in
            sheetTab(name: sheet.name, isActive: index == viewModel.workbook.activeSheetIndex) {
              viewModel.selectSheet(at: index)
            }
            .contextMenu {
              Button("Rename…") {
                sheetToRename = index
                renameText = sheet.name
              }
              Divider()
              Button("Delete", role: .destructive) {
                viewModel.deleteSheet(at: index)
              }
              .disabled(viewModel.workbook.sheets.count <= 1)
            }
          }
        }
      }

      Spacer(minLength: 0)
    }
    .frame(height: 28)
    .background(.bar)
    .alert("Rename Sheet", isPresented: renameAlertBinding) {
      TextField("Sheet name", text: $renameText)
      Button("Rename") {
        if let index = sheetToRename {
          viewModel.renameSheet(at: index, to: renameText)
        }
        sheetToRename = nil
      }
      Button("Cancel", role: .cancel) {
        sheetToRename = nil
      }
    }
  }

  private var renameAlertBinding: Binding<Bool> {
    Binding(
      get: { sheetToRename != nil },
      set: { if !$0 { sheetToRename = nil } }
    )
  }

  private func sheetTab(name: String, isActive: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(name)
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
        .overlay(alignment: .top) {
          if isActive {
            Rectangle()
              .fill(Color.accentColor)
              .frame(height: 2)
          }
        }
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}
