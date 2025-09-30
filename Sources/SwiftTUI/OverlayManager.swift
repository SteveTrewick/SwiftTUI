import Foundation


public final class OverlayManager {

  private var overlays: [Renderable]

  public var onChange: (() -> Void)? = nil

  public init(overlays: [Renderable] = []) {
    self.overlays = overlays
  }

  
  public func drawBox ( row: Int, col: Int, width: Int, height: Int, foreground: ANSIForecolor = .white, background: ANSIBackcolor = .bgBlack ) {
   
    guard width >= 2 else { return }
    guard height >= 2 else { return }

    let box = Box(
      row       : row,
      col       : col,
      width     : width,
      height    : height,
      foreground: foreground,
      background: background
    )

    overlays.append ( box )
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
