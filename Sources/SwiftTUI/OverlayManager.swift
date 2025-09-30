import Foundation


public final class OverlayManager {

  private var overlays: [Renderable]
  private var interactiveOverlays: [OverlayInputHandling]

  public var onChange: (() -> Void)? = nil

  public init(overlays: [Renderable] = []) {
    self.overlays            = overlays
    self.interactiveOverlays = []
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
    row      : Int?              = nil,
    col      : Int?              = nil,
    style    : ElementStyle      = ElementStyle(),
    buttonText: String           = "OK",
    activationKey: TerminalInput.ControlKey = .RETURN
  ) {

    let overlay = MessageBoxOverlay(
      message      : message,
      row          : row,
      col          : col,
      style        : style,
      buttonText   : buttonText,
      activationKey: activationKey,
      onDismiss    : { [weak self] in self?.clear() }
    )

    overlays.append ( overlay )
    interactiveOverlays.append( overlay )
    onChange?()
  }



  public func activeOverlays() -> [Renderable] {
    overlays
  }

  public func handle(inputs: [TerminalInput.Input]) -> Bool {

    guard !interactiveOverlays.isEmpty else { return false }

    for input in inputs {
      let handlers = interactiveOverlays
      for overlay in handlers {
        if overlay.handle(input) {
          return true
        }
      }
    }

    return false
  }

  public func clear() {
    overlays.removeAll()
    interactiveOverlays.removeAll()
    onChange?()
  }
}


private final class MessageBoxOverlay: Renderable, OverlayInputHandling {

  private let messageBox: MessageBox
  private let button    : Button

  init(
    message      : String,
    row          : Int?,
    col          : Int?,
    style        : ElementStyle,
    buttonText   : String,
    activationKey: TerminalInput.ControlKey,
    onDismiss    : @escaping () -> Void
  ) {

    var body = message
    if !body.hasSuffix("\n") {
      body += "\n"
    }
    body += "\n"

    self.messageBox = MessageBox(message: body, row: row, col: col, style: style)
    self.button     = Button(
      bounds      : BoxBounds(row: row ?? 1, col: col ?? 1, width: buttonText.count + 4, height: 1),
      text        : buttonText,
      style       : style,
      activationKey: activationKey,
      onActivate  : onDismiss
    )
  }

  func render(in size: winsize) -> [AnsiSequence]? {

    guard let layout = messageBox.layout(in: size) else { return nil }
    guard var sequences = messageBox.render(in: size) else { return nil }

    let bounds         = layout.bounds
    let interiorWidth  = bounds.width - 2
    guard button.minimumWidth <= interiorWidth else { return sequences }

    let labelWidth     = max(button.minimumWidth, 1)
    let textStartRow   = bounds.row + 1
    let buttonRow      = textStartRow + max(layout.lines.count - 1, 0)
    let buttonCol      = bounds.col + 1 + max(0, (interiorWidth - labelWidth) / 2)

    button.bounds = BoxBounds(
      row   : buttonRow,
      col   : buttonCol,
      width : labelWidth,
      height: 1
    )

    if let buttonSequences = button.render(in: size) {
      sequences += buttonSequences
    }

    return sequences
  }

  func handle(_ input: TerminalInput.Input) -> Bool {
    return button.handle(input)
  }
}
