import Foundation

extension SpreadsheetViewModel {
  func selectImage(id: UUID?) {
    guard selectedImageID != id else { return }
    selectedImageID = id
    notifyGridRefresh()
  }

  func image(with id: UUID) -> SheetImage? {
    activeSheet.images.first { $0.id == id }
  }

  /// Updates placement during a drag (no undo). Call `commitImagePlacement` on mouse up.
  func setImagePlacement(
    id: UUID,
    anchorRow: Int,
    anchorCol: Int,
    rowOffsetEMU: Int,
    colOffsetEMU: Int,
    widthEMU: Int? = nil,
    heightEMU: Int? = nil
  ) {
    guard let index = activeSheet.images.firstIndex(where: { $0.id == id }) else { return }
    var sheet = activeSheet
    sheet.images[index].anchorRow = max(0, anchorRow)
    sheet.images[index].anchorCol = max(0, anchorCol)
    sheet.images[index].rowOffsetEMU = max(0, rowOffsetEMU)
    sheet.images[index].colOffsetEMU = max(0, colOffsetEMU)
    if let widthEMU { sheet.images[index].widthEMU = max(SheetImage.emu(fromPoints: 12), widthEMU) }
    if let heightEMU { sheet.images[index].heightEMU = max(SheetImage.emu(fromPoints: 12), heightEMU) }
    setActiveSheetPreservingFormulas(sheet)
    notifyGridRefresh()
  }

  func commitImagePlacement(
    id: UUID,
    before: SheetImage,
    actionName: String = "Move Picture"
  ) {
    guard let after = image(with: id), before != after else { return }
    let undoBefore = replaceImage(before, in: activeSheet.images)
    applyImages(activeSheet.images, undoBefore: undoBefore, actionName: actionName)
  }

  func deleteSelectedImage() {
    guard let id = selectedImageID else { return }
    deleteImage(id: id)
  }

  func deleteImage(id: UUID) {
    commitEditIfNeeded()
    let before = activeSheet.images
    var sheet = activeSheet
    sheet.images.removeAll { $0.id == id }
    if selectedImageID == id { selectedImageID = nil }
    setActiveSheetPreservingFormulas(sheet)
    undoManager?.registerUndo(withTarget: self) { target in
      target.applyImages(before, undoBefore: sheet.images, actionName: "Delete Picture")
    }
    undoManager?.setActionName("Delete Picture")
    notifyGridRefresh()
  }

  private func replaceImage(_ image: SheetImage, in images: [SheetImage]) -> [SheetImage] {
    guard let index = images.firstIndex(where: { $0.id == image.id }) else { return images }
    var next = images
    next[index] = image
    return next
  }

  private func applyImages(_ images: [SheetImage], undoBefore: [SheetImage], actionName: String) {
    var sheet = activeSheet
    sheet.images = images
    setActiveSheetPreservingFormulas(sheet)
    undoManager?.registerUndo(withTarget: self) { target in
      target.applyImages(undoBefore, undoBefore: images, actionName: actionName)
    }
    undoManager?.setActionName(actionName)
    notifyGridRefresh()
  }
}
