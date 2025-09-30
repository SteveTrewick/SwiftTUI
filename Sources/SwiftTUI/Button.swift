import Foundation

// Interactive overlays need a small protocol so they can tap keystrokes that
// the application loop collects.  The button implements this so the overlay
// manager can wire it up to TerminalApp without tightly coupling the types.
protocol OverlayInputHandling: AnyObject {
  func handle(_ input: TerminalInput.Input) -> Bool
}

/// Minimal button rendering that keeps the look consistent with the rest of the
/// text UI.  The button draws a bracketed label centred within the supplied
/// bounds and calls through to a handler when its activation key arrives.
public final class Button: Renderable, OverlayInputHandling {

  public var bounds      : BoxBounds
  public let text        : String
  public let style       : ElementStyle
  public let activationKey: TerminalInput.ControlKey

  private var onActivate : (() -> Void)?
  private var isArmed    : Bool

  public init(
    bounds      : BoxBounds,
    text        : String,
    style       : ElementStyle = ElementStyle(),
    activationKey: TerminalInput.ControlKey = .RETURN,
    onActivate  : (() -> Void)? = nil
  ) {
    self.bounds        = bounds
    self.text          = text
    self.style         = style
    self.activationKey = activationKey
    self.onActivate    = onActivate
    self.isArmed       = true

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

  public var minimumWidth: Int { displayText.count }

  private var displayText: String {
    "[ \(text) ]"
  }

  public func render(in size: winsize) -> [AnsiSequence]? {

    let rows    = Int(size.ws_row)
    let columns = Int(size.ws_col)

    guard rows > 0 && columns > 0 else { return nil }

    let top    = bounds.row
    let left   = bounds.col
    let bottom = top  + max(bounds.height, 1) - 1
    let right  = left + bounds.width        - 1

    guard top    >= 1 else { return nil }
    guard left   >= 1 else { return nil }
    guard bottom <= rows else { return nil }
    guard right  <= columns else { return nil }

    // Only render within the first row of the supplied bounds for now.
    guard bounds.height >= 1 else { return nil }
    guard bounds.width  >= minimumWidth else { return nil }

    let excessWidth   = bounds.width - minimumWidth
    let leftPadding   = excessWidth / 2
    let rightPadding  = excessWidth - leftPadding
    let paddedContent = String(repeating: " ", count: leftPadding)
                      + displayText
                      + String(repeating: " ", count: rightPadding)

    return [
      .moveCursor(row: bounds.row, col: bounds.col),
      .backcolor (style.background),
      .forecolor (style.foreground),
      .text      (paddedContent),
      .resetcolor
    ]
  }

  @discardableResult
  public func handle(_ input: TerminalInput.Input) -> Bool {

    guard isArmed else { return false }

    switch input {

      case .key(let key) where key == activationKey:
        activate()
        return true

      case .ascii(let data) where activationKey == .RETURN:
        if data.contains(0x0d) { // Carriage return
          activate()
          return true
        }
        return false

      default:
        return false
    }
  }

  private func activate() {
    guard isArmed else { return }
    isArmed = false
    onActivate?()
  }
}
