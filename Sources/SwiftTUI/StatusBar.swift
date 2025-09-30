import Foundation

public final class StatusBar : Renderable {

  public var style : ElementStyle
  public var text  : String
  
  private let output: OutputController

  
  public init ( text: String, style: ElementStyle, output: OutputController = OutputController() ) {
    self.text   = text
    self.style  = style
    self.output = output
  }

  
  public func render ( in size: winsize ) -> [AnsiSequence]? {
    
    let row     = Int(size.ws_row)
    let columns = Int(size.ws_col)
    
    guard row > 0 && columns > 0 else { return nil }

    let visibleText  = String(text.prefix(columns))
    let paddingCount = max(0, columns - visibleText.count)
    let paddedText   = visibleText + String(repeating: " ", count: paddingCount)

    return [
      .moveCursor ( row: row, col: 1 ),
      .backcolor  ( style.background ),
      .forecolor  ( style.foreground ),
      .text       ( paddedText ),
      .resetcolor
    ]
  }
}
