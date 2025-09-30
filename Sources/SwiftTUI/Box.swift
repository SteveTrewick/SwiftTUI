import Foundation



struct TermCoord {
  let row: Int
  let col: Int
}

struct TermSize {
  let width  : Int
  let height : Int
}


public struct Box : Renderable {

  let position  : TermCoord
  let extent    : TermSize
  let foreground: ANSIForecolor
  let background: ANSIBackcolor

  public init (
    row       : Int,
    col       : Int,
    width     : Int,
    height    : Int,
    foreground: ANSIForecolor = .white,
    background: ANSIBackcolor = .bgBlue
  ) {
    position   = TermCoord(row: row, col: col)
    extent     = TermSize(width: width, height: height)
    self.foreground = foreground
    self.background = background
  }

  public func render ( in terminalSize: winsize ) -> [AnsiSequence]? {

    let rows    = Int(terminalSize.ws_row)
    let columns = Int(terminalSize.ws_col)

    guard extent.width  >= 2 else { return nil }
    guard extent.height >= 2 else { return nil }

    let top    = position.row
    let left   = position.col
    let bottom = top  + extent.height - 1
    let right  = left + extent.width  - 1

    guard top    >= 1 else { return nil }
    guard left   >= 1 else { return nil }
    guard bottom <= rows else { return nil }
    guard right  <= columns else { return nil }

    return [
      .moveCursor(row: top, col: left),
        .backcolor (background),
        .forecolor (foreground),
        .box   (.tlc),
        .box   (.horiz(extent.width - 2)),
        .box   (.trc),
        .resetcolor,

      .repeatRow(
        col: left,
        row: top + 1,
        count: extent.height - 2,
        [
          .backcolor (background),
          .forecolor (foreground),
          .box   (.vert),
          .resetcolor,
          .repeatChars(" ", count: extent.width - 2),
          .backcolor (background),
          .forecolor (foreground),
          .box   (.vert),
          .resetcolor,
        ]
      ),

      .moveCursor(row: bottom, col: left),
        .backcolor (background),
        .forecolor (foreground),
        .box   (.blc),
        .box   (.horiz(extent.width - 2)),
        .box   (.brc),
        .resetcolor,
    ]
  }
}
