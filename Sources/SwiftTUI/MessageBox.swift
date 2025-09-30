import Foundation

/// A simple multiline message box rendered using the same box drawing primitives.
/// We build the border with the existing `Box` type so the style stays consistent,
/// then draw each line of text with a single character of padding on either side.
public struct MessageBox : Renderable {

  public let message   : String
  public let foreground: ANSIForecolor
  public let background: ANSIBackcolor
  public let row       : Int?
  public let col       : Int?

  public init (
    message   : String,
    row       : Int? = nil,
    col       : Int? = nil,
    foreground: ANSIForecolor = .white,
    background: ANSIBackcolor = .bgBlack
  ) {
    self.message    = message
    self.row        = row
    self.col        = col
    self.foreground = foreground
    self.background = background
  }

  public func render ( in size: winsize ) -> [AnsiSequence]? {

    let rows    = Int(size.ws_row)
    let columns = Int(size.ws_col)

    guard rows > 0 && columns > 0 else { return nil }

    // Split on newlines while preserving empty trailing rows so blank lines render.
    var lines = message.split(separator: "\n", omittingEmptySubsequences: false)
      .map(String.init)
    if lines.isEmpty { lines = [""] }

    let maxLineLength = lines.map { $0.count }.max() ?? 0

    // One space of padding on either side of the text, plus the two border columns.
    let interiorWidth = maxLineLength + 2
    let width         = interiorWidth + 2
    let height        = lines.count + 2

    guard width  <= columns else { return nil }
    guard height <= rows    else { return nil }

    let top = row ?? max(1, ((rows    - height) / 2) + 1)
    let left = col ?? max(1, ((columns - width ) / 2) + 1)

    let bottom = top  + height - 1
    let right  = left + width  - 1

    guard top    >= 1 else { return nil }
    guard left   >= 1 else { return nil }
    guard bottom <= rows else { return nil }
    guard right  <= columns else { return nil }

    guard var sequences = Box(
      row: top,
      col: left,
      width: width,
      height: height,
      foreground: foreground,
      background: background
    ).render ( in: size ) else { return nil }

    let textStartRow = top + 1
    let textStartCol = left + 1
    let textAreaWidth = width - 2

    for (idx, line) in lines.enumerated() {
      let rowPosition = textStartRow + idx
      let padded = " " + line + String(repeating: " ", count: max(0, textAreaWidth - 1 - line.count))
      sequences += [
        .moveCursor(row: rowPosition, col: textStartCol),
        .backcolor(background),
        .forecolor(foreground),
        .text(padded),
        .resetcolor
      ]
    }

    return sequences
  }
}
