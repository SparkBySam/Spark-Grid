import AppKit
import SwiftUI

struct SheetTabsView: View {
  @Bindable var viewModel: SpreadsheetViewModel
  @State private var sheetToRename: Int?
  @State private var renameText = ""

  var body: some View {
    HStack(spacing: 0) {
      Button(action: viewModel.addSheet) {
        Image(systemName: "plus")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.secondary)
          .frame(width: 24, height: 24)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help("Add sheet")

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 1) {
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
    .frame(height: 24)
    .background(Color(nsColor: .windowBackgroundColor))
    .overlay(alignment: .top) { Divider() }
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
        .font(.system(size: 11, weight: isActive ? .semibold : .regular))
        .foregroundStyle(isActive ? Color.primary : Color.secondary)
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background {
          if isActive {
            Color(nsColor: .controlBackgroundColor)
          }
        }
        .overlay(alignment: .bottom) {
          Rectangle()
            .fill(isActive ? Color.accentColor : Color.clear)
            .frame(height: 2)
        }
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}
