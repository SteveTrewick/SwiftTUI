import Foundation

/// A simple multiline message box rendered using the same box drawing primitives.
/// We build the border with the existing `Box` type so the style stays consistent,
/// then draw each line of text with a single character of padding on either side.
public struct MessageBox : Renderable {

  public struct Layout {
    public let bounds: BoxBounds
    public let lines : [String]
  }

  public let message   : String
  public let row       : Int?
  public let col       : Int?
  public let element   : BoxElement
  public let minimumInteriorWidth: Int

  public init (
    message: String,
    row    : Int? = nil,
    col    : Int? = nil,
    element: BoxElement,
    minimumInteriorWidth: Int = 0
  ) {
    self.message = message
    self.row     = row
    self.col     = col
    self.element = element
    self.minimumInteriorWidth = max(0, minimumInteriorWidth)
  }

  public init (
    message: String,
    row    : Int? = nil,
    col    : Int? = nil,
    style  : ElementStyle = ElementStyle(),
    minimumInteriorWidth: Int = 0
  ) {
    
    
    // the fuck?
    
    // Preserve a default style-focused element while deferring bounds to render.
    let placeholderBounds = BoxBounds(
      row   : row ?? 1,
      col   : col ?? 1,
      width : 2,
      height: 2
    )

    self.init(
      message: message,
      row    : row,
      col    : col,
      element: BoxElement( bounds: placeholderBounds, style: style ),
      minimumInteriorWidth: minimumInteriorWidth
    )
  }

  public func layout(in size: winsize) -> Layout? {

    let rows    = Int(size.ws_row)
    let columns = Int(size.ws_col)

    guard rows > 0 && columns > 0 else { return nil }

    // Split on newlines while preserving empty trailing rows so blank lines render.
    var lines = message.split(separator: "\n", omittingEmptySubsequences: false)
                       .map(String.init)

    if lines.isEmpty { lines = [""] }

    let maxLineLength = lines.map { $0.count }.max() ?? 0

    // One space of padding on either side of the text, plus the two border columns.
    let paddedLineWidth = maxLineLength + 2
    let interiorWidth = max(paddedLineWidth, minimumInteriorWidth)
    let width         = interiorWidth + 2
    let height        = lines.count + 2

    guard width  <= columns else { return nil }
    guard height <= rows    else { return nil }

    let top          = row ?? max(1, ((rows    - height) / 2) + 1)
    let proposedLeft = col ?? max(1, ((columns - width ) / 2) + 1)
    // Clamp the left edge so oversized button boxes can still render when callers
    // pin the dialog near the right edge. Without this the wider frame would fall
    // off-screen and the overlay would refuse to render entirely.
    let maxLeft      = max(1, columns - width + 1)
    let left         = min(max(1, proposedLeft), maxLeft)

    let bottom = top  + height - 1
    let right  = left + width  - 1

    guard top    >= 1 else { return nil }
    guard left   >= 1 else { return nil }
    guard bottom <= rows else { return nil }
    guard right  <= columns else { return nil }

    let bounds = BoxBounds(row: top, col: left, width: width, height: height)

    return Layout(bounds: bounds, lines: lines)
  }

  public func render ( in size: winsize ) -> [AnsiSequence]? {

    guard let layout = layout(in: size) else { return nil }

    let bounds     = layout.bounds
    let boxElement = BoxElement(bounds: bounds, style: element.style)

    guard let boxSequences = Box ( element: boxElement ).render ( in: size ) else { return nil }

    // Treat the frame and each body line as discrete elements so overlays can share the same validation path.
    var elements: [TUIElement] = [ TUIElement ( bounds: bounds, sequences: boxSequences ) ]

    let textStartRow  = bounds.row + 1
    let textStartCol  = bounds.col + 1
    let textAreaWidth = bounds.width - 2
    let textStyle     = ElementStyle ( foreground: boxElement.style.foreground, background: boxElement.style.background )

    for (idx, line) in layout.lines.enumerated() {

      let rowPosition = textStartRow + idx
      let padded = " " + line + String(repeating: " ", count: max(0, textAreaWidth - 1 - line.count))
      let rowBounds = BoxBounds ( row: rowPosition, col: textStartCol, width: textAreaWidth, height: 1 )
      let element   = TUIElement.textRow ( bounds: rowBounds, style: textStyle, text: padded )
      elements.append ( element )
    }

    return TUIElement.render ( elements, in: size )
  }
}
