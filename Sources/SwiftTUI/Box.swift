import Foundation



struct TermCoord {
  let row: Int
  let col: Int
}

struct TermSize {
  let width  : Int
  let height : Int
}


public struct Box {
  
  let position: TermCoord
  let size    : TermSize

  public init (row: Int, col: Int, width: Int, height: Int) {
    position = TermCoord(row  : row,   col   : col   )
    size     = TermSize (width: width, height: height)
  }
  
  // there is probably a better way to do this.
  // but this is kinda fun
  public func render(foreground: ANSIForecolor, background: ANSIBackcolor) -> AnsiSequence {
    .flatten (
      [
        .moveCursor(row: position.row, col: position.col),
          .backcolor (background),
          .forecolor (foreground),
          .box   (.tlc),
          .box   (.horiz(size.width - 2) ),
          .box   (.trc),
          .resetcolor,
        
        .repeatRow(col: position.col, row: position.row + 1, count: size.height - 2,
            [
              .backcolor       (background),
              .forecolor       (foreground),
              .box         (.vert),
              .repeatChars (" ", count: size.width - 2),
              .box         (.vert),
              .resetcolor,
            ]
        ),
        
        .moveCursor(row: position.row + size.height - 1, col: position.col),
          .backcolor (background),
          .forecolor (foreground),
          .box   (.blc),
          .box   (.horiz(size.width - 2) ),
          .box   (.brc),
          .resetcolor,
      ]
    )
  }
}
