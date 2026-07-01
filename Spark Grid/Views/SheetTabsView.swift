import SwiftUI

struct SheetTabsView: View {
  let sheetName: String

  var body: some View {
    HStack(spacing: 0) {
      Text(sheetName)
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.15))
        .overlay(alignment: .top) {
          Rectangle()
            .fill(Color.accentColor)
            .frame(height: 2)
        }
      Spacer()
    }
    .frame(height: 28)
    .background(.bar)
  }
}
