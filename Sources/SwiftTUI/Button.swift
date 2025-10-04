import Foundation
// Interactive overlays need a small protocol so they can tap keystrokes that
// the application loop collects.  The button implements this so the overlay
// manager can wire it up to TerminalApp without tightly coupling the types.
protocol OverlayInputHandling: AnyObject {
  func handle(_ input: TerminalInput.Input) -> Bool
}

// Overlays that maintain internal caches need a hook so the manager can force a
// full redraw when the terminal clears the screen.  The manager only calls this
// when a repaint is unavoidable (window resize, manual clear, etc.) so the
// overlay can flush any cached geometry before it renders again.
protocol OverlayInvalidating: AnyObject {
  func invalidateForFullRedraw()
}

/// Minimal button rendering that keeps the look consistent with the rest of the
/// text UI.  The button draws a bracketed label centred within the supplied
/// bounds using the foreground and background colours supplied at render time.
/// Input handling lives with the overlays that embed the control so this type
/// stays focused on presentation.
public final class Button: Renderable {

  public var bounds: BoxBounds
  public let text  : String
  public let style : ElementStyle

  public var minimumWidth: Int { displayText.count }

  private var displayText: String {
    "[ \(text) ]"
  }
  
  public init ( bounds: BoxBounds, text: String, style: ElementStyle = ElementStyle() ) {
    self.bounds = bounds
    self.text   = text
    self.style  = style

    // Ensure we have at least enough width for the label plus brackets.
    let minimum = max(minimumWidth, bounds.width)
    if minimum != bounds.width {
      self.bounds = BoxBounds(
        row   : bounds.row,
        col   : bounds.col,
        width : minimum,
        height: bounds.height
      )
    }
  }

 

 
  
  public func render ( in size: winsize ) -> [AnsiSequence]? {
    render ( in: size, foreground: nil, background: nil )
  }

  public func render ( in size: winsize, foreground: ANSIForecolor?, background: ANSIBackcolor? ) -> [AnsiSequence]? {

    guard bounds.height >= 1 else { return nil }
    guard bounds.width  >= minimumWidth else { return nil }

    let excessWidth   = bounds.width - minimumWidth
    let leftPadding   = excessWidth / 2
    let rightPadding  = excessWidth - leftPadding
    let paddedContent = String(repeating: " ", count: leftPadding)
                      + displayText
                      + String(repeating: " ", count: rightPadding)

    let activeBackground  = background ?? style.background
    let activeForeground  = foreground ?? style.foreground
    let rowBounds         = BoxBounds ( row: bounds.row, col: bounds.col, width: bounds.width, height: 1 )
    let rowStyle          = ElementStyle ( foreground: activeForeground, background: activeBackground )
    let element           = TUIElement.textRow ( bounds: rowBounds, style: rowStyle, text: paddedContent, includeHideCursor: false )

    return element.render ( in: size )
  }
}
