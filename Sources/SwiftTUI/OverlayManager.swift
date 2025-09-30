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

  //TODO: add message box drawing code here
  
  public func activeOverlays() -> [Renderable] {
    overlays
  }

  public func clear() {
    overlays.removeAll()
    onChange?()
  }
}
