import Foundation



public struct BoxBounds {
  
  public let row       : Int
  public let col       : Int
  public let width     : Int
  public let height    : Int
  
  public init ( row: Int, col: Int, width: Int, height: Int ) {
    self.row    = row
    self.col    = col
    self.width  = width
    self.height = height
  }
  
}

public struct ElementStyle {
  
  public let foreground: ANSIForecolor
  public let background: ANSIBackcolor
  
  public init ( foreground: ANSIForecolor = .white, background: ANSIBackcolor = .black ) {
    self.foreground = foreground
    self.background = background
  }
}


public struct BoxElement {

  public let bounds: BoxBounds
  public let style : ElementStyle
  
  public init( bounds: BoxBounds, style : ElementStyle = ElementStyle() ) {
    self.bounds = bounds
    self.style  = style
  }
}


public struct Box : Renderable {

  let element: BoxElement

  public init ( element: BoxElement ) {
    // Keep the higher level BoxElement descriptor intact so downstream
    // renderers can inspect both bounds and styling directly.
    self.element = element
  }

  public func render ( in terminalSize: winsize ) -> [AnsiSequence]? {

    let rows    = Int(terminalSize.ws_row)
    let columns = Int(terminalSize.ws_col)

    guard element.bounds.width  >= 2 else { return nil }
    guard element.bounds.height >= 2 else { return nil }

    let top    = element.bounds.row
    let left   = element.bounds.col
    let bottom = top  + element.bounds.height - 1
    let right  = left + element.bounds.width  - 1

    guard top    >= 1 else { return nil }
    guard left   >= 1 else { return nil }
    guard bottom <= rows else { return nil }
    guard right  <= columns else { return nil }

    return [
      .moveCursor(row: top, col: left),
        .backcolor (element.style.background),
        .forecolor (element.style.foreground),
        .box   (.tlc),
        .box   (.horiz(element.bounds.width - 2)),
        .box   (.trc),
        .resetcolor,

      .repeatRow(
        col: left,
        row: top + 1,
        count: element.bounds.height - 2,
        [
          .backcolor (element.style.background),
          .forecolor (element.style.foreground),
          .box   (.vert),
          .resetcolor,
          .repeatChars(" ", count: element.bounds.width - 2),
          .backcolor (element.style.background),
          .forecolor (element.style.foreground),
          .box   (.vert),
          .resetcolor,
        ]
      ),

      .moveCursor(row: bottom, col: left),
        .backcolor (element.style.background),
        .forecolor (element.style.foreground),
        .box   (.blc),
        .box   (.horiz(element.bounds.width - 2)),
        .box   (.brc),
        .resetcolor,
        .hideCursor // for some reason it cmes back
    ]
  }
}
