import Foundation

public final class StatusBar : Renderable {

  public var style : ElementStyle
  public var text  : String
  
 
  public init ( text: String, style: ElementStyle ) {
    self.text   = text
    self.style  = style
  }

  
  public func render ( in size: winsize ) -> [AnsiSequence]? {

    let row     = Int(size.ws_row)
    let columns = Int(size.ws_col)

    guard row > 0 && columns > 0 else { return nil }

    let visibleText  = String ( text.prefix(columns) )
    let paddingCount = max ( 0, columns - visibleText.count )
    let paddedText   = visibleText + String ( repeating: " ", count: paddingCount )
    let bounds       = BoxBounds ( row: row, col: 1, width: paddedText.count, height: 1 )
    // The helper keeps palette and cursor handling consistent with other single-row widgets.
    let element      = TUIElement.textRow ( bounds: bounds, style: style, text: paddedText )

    return element.render ( in: size )
  }
}
