import Foundation

public final class StatusBar : Renderable {

  public var foreground: ANSIForecolor
  public var background: ANSIBackcolor
  public var text      : String
  
  private let output: OutputController

  
  public init (
    text      : String,
    foreground: ANSIForecolor    = .black,
    background: ANSIBackcolor    = .bgWhite,
    output    : OutputController = OutputController()
  ) {
    self.text       = text
    self.output     = output
    self.foreground = foreground
    self.background = background
  }

  
  public func render ( in size: winsize ) -> [AnsiSequence]? {
    
    let row     = Int(size.ws_row)
    let columns = Int(size.ws_col)
    
    guard row > 0 && columns > 0 else { return nil }

    let visibleText  = String(text.prefix(columns))
    let paddingCount = max(0, columns - visibleText.count)
    let paddedText   = visibleText + String(repeating: " ", count: paddingCount)

    return [
      .moveCursor( row: row, col: 1 ),
      .backcolor ( background ),
      .forecolor ( foreground ),
      .text      ( paddedText ),
      .resetcolor
    ]
  }
}
