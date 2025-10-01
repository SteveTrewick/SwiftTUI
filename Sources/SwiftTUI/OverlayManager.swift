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
    activationKey: TerminalInput.ControlKey = .RETURN,
    buttons  : [MessageBoxButton] = []
  ) {

    let buttonConfigs: [MessageBoxButton]
    if buttons.isEmpty {
      buttonConfigs = [MessageBoxButton(text: buttonText, activationKey: activationKey)]
    } else {
      buttonConfigs = buttons
    }

    let overlay = MessageBoxOverlay (
      message  : message,
      row      : row,
      col      : col,
      style    : style,
      buttons  : buttonConfigs,
      onDismiss: { [weak self] in self?.clear() },
      onUpdate : { [weak self] in self?.onChange?() }
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


public struct MessageBoxButton {

  public let text          : String
  public let activationKey : TerminalInput.ControlKey
  public let handler       : (() -> Void)?

  public init ( text: String, activationKey: TerminalInput.ControlKey = .RETURN, handler: (() -> Void)? = nil ) {
    self.text          = text
    self.activationKey = activationKey
    self.handler       = handler
  }
}

private final class MessageBoxOverlay: Renderable, OverlayInputHandling {

  private let messageBox  : MessageBox
  private var buttons     : [Button]
  private var activeIndex : Int
  private let onUpdate    : (() -> Void)?

  init(
    message   : String,
    row       : Int?,
    col       : Int?,
    style     : ElementStyle,
    buttons   : [MessageBoxButton],
    onDismiss : @escaping () -> Void,
    onUpdate  : (() -> Void)?
  ) {

    var body = message
    if !body.hasSuffix("\n") {
      body += "\n"
    }
    body += "\n"

    let minimumInteriorWidth = MessageBoxOverlay.minimumInteriorWidth(for: buttons)

    // Expand the underlying message box so that the button row is always wide
    // enough for the supplied button labels. Without this, wide button sets get
    // clipped because the default layout only considered the message text.
    self.messageBox  = MessageBox(
      message: body,
      row    : row,
      col    : col,
      style  : style,
      minimumInteriorWidth: minimumInteriorWidth
    )
    self.activeIndex = 0
    self.onUpdate    = onUpdate

    // Convert the base element style into a highlight palette so buttons stay
    // visually consistent with the rest of the overlay.
    let highlightPalette = MessageBoxOverlay.highlightPalette(for: style)

    self.buttons = buttons.enumerated().map { index, config in
      let action = config.handler
      return Button (
        bounds             : BoxBounds(row: row ?? 1, col: col ?? 1, width: config.text.count + 4, height: 1),
        text               : config.text,
        style              : style,
        activationKey      : config.activationKey,
        onActivate         : { action?(); onDismiss() },
        highlightForeground: highlightPalette.foreground,
        highlightBackground: highlightPalette.background,
        usesDimHighlight    : true,
        isHighlightActive   : index == 0
      )
    }
  }

  func render ( in size: winsize ) -> [AnsiSequence]? {

    guard let layout    = messageBox.layout(in: size) else { return nil }
    guard var sequences = messageBox.render(in: size) else { return nil }

    guard !buttons.isEmpty else { return sequences }

    let bounds        = layout.bounds
    let interiorWidth = bounds.width - 2

    let minimumButtonWidths = buttons.reduce(0) { $0 + $1.minimumWidth }
    let gapCount            = max(buttons.count - 1, 0)
    let minimumRowWidth     = minimumButtonWidths + gapCount

    guard minimumRowWidth <= interiorWidth else { return sequences }

    let availableGap = interiorWidth - minimumButtonWidths
    let spacing      = buttons.count > 1 ? min(2, availableGap / max(gapCount, 1)) : 0
    let totalWidth   = minimumButtonWidths + spacing * gapCount
    let textStartRow = bounds.row + 1
    let buttonRow    = textStartRow + max(layout.lines.count - 1, 0)
    let startCol     = bounds.col + 1 + max(0, (interiorWidth - totalWidth) / 2)

    var currentCol = startCol

    for (index, button) in buttons.enumerated() {
      button.isHighlightActive = (index == activeIndex)

      button.bounds = BoxBounds(
        row   : buttonRow,
        col   : currentCol,
        width : button.minimumWidth,
        height: 1
      )

      if let buttonSequences = button.render(in: size) {
        sequences += buttonSequences
      }

      currentCol += button.minimumWidth + spacing
    }

    return sequences
  }

  func handle(_ input: TerminalInput.Input) -> Bool {

    guard !buttons.isEmpty else { return false }

    // The overlay owns left/right navigation so only the focused button sees the
    // activation key. This keeps keyboard handling predictable for callers.
    switch input {

      case .cursor(let key):
        let previousIndex = activeIndex

        switch key {
          case .left  : activeIndex = max(0, activeIndex - 1)
          case .right : activeIndex = min(buttons.count - 1, activeIndex + 1)
          default     : break
        }

        if activeIndex != previousIndex {
          onUpdate?()
          return true
        }

        return activeIndex != previousIndex

      default:
        return buttons[activeIndex].handle(input)
    }
  }

  private static func highlightPalette(for style: ElementStyle) -> (foreground: ANSIForecolor, background: ANSIBackcolor) {

    let highlightBackground = MessageBoxOverlay.backcolor(for: style.foreground)
    let fallbackForeground  = MessageBoxOverlay.forecolor(for: style.background)

    if highlightBackground == style.background {
      // If the highlight would match the surrounding box fall back to white so
      // the selected button remains visible against darker themes.
      return (fallbackForeground, .white)
    }

    return (fallbackForeground, highlightBackground)
  }

  private static func minimumInteriorWidth(for buttons: [MessageBoxButton]) -> Int {

    guard !buttons.isEmpty else { return 0 }

    let labelWidth = buttons.reduce(0) { width, config in
      width + MessageBoxOverlay.buttonWidth(for: config.text)
    }

    return labelWidth + max(buttons.count - 1, 0)
  }

  private static func buttonWidth(for text: String) -> Int {
    // Button labels are rendered as "[ text ]" so we add four characters to the
    // raw label length to account for the brackets and surrounding spaces.
    return text.count + 4
  }

  private static func backcolor(for forecolor: ANSIForecolor) -> ANSIBackcolor {
    switch forecolor {
      case .black  : return .black
      case .red    : return .red
      case .green  : return .green
      case .yellow : return .yellow
      case .blue   : return .blue
      case .magenta: return .magenta
      case .cyan   : return .vyan
      case .white  : return .white
    }
  }

  private static func forecolor(for backcolor: ANSIBackcolor) -> ANSIForecolor {
    switch backcolor {
      case .black  : return .black
      case .red    : return .red
      case .green  : return .green
      case .yellow : return .yellow
      case .blue   : return .blue
      case .magenta: return .magenta
      case .vyan   : return .cyan
      case .white  : return .black
      case .grey   : return .white
    }
  }
}
