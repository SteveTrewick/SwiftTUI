import Foundation


public final class OverlayManager {

  private var overlays: [Renderable]

  public var onChange: (() -> Void)? = nil

  public init(overlays: [Renderable] = []) {
    self.overlays = overlays
  }


  public func drawBox ( _ element: BoxElement ) {

    let bounds = element.bounds

    guard bounds.width  >= 2 else { return }
    guard bounds.height >= 2 else { return }

    // Persist the descriptor so overlay redraws can recover the full bounds and style.
    let box = Box(element: element)

    overlays.append ( box )
    onChange?()
  }


  public func drawMessageBox (
    _ message: String,
    row      : Int?          = nil,
    col      : Int?          = nil,
    style    : ElementStyle  = ElementStyle()
  ) {

    // Default to the provided style while letting the render pass pick final bounds.
    let messageBox = MessageBox(
      message: message,
      row    : row,
      col    : col,
      style  : style
    )

    overlays.append ( messageBox )
    onChange?()
  }

  
  
  public func activeOverlays() -> [Renderable] {
    overlays
  }

  public func clear() {
    overlays.removeAll()
    onChange?()
  }
}
