import Foundation

public final class MenuItem : Renderable {

  public var name    : String
  public var style   : ElementStyle
  public var action  : MenuAction
  public var context : AppContext

  private var originRow        : Int
  private var originCol        : Int
  private var isHighlightActive: Bool

  // Expose the anchor through a computed property so overlays can align
  // themselves relative to the menu item while keeping the mutable state local
  // to the item. The stored coordinates remain private to avoid external
  // mutation while still allowing callers to reason about placement.
  public var anchor : (row: Int, col: Int) {
    (row: originRow, col: originCol)
  }

  

  public init ( name: String, style: ElementStyle, context: AppContext, action: MenuAction ) {
    self.name       = name
    self.context    = context
    self.action     = action
    self.style      = style
    self.originRow         = 1
    self.originCol         = 1
    self.isHighlightActive = false
    
  }

  func responds ( to select: Character ) -> Bool {
    if let char = name.first?.uppercased(), char == select.uppercased() { return true  }
    else                                                                { return false }
  }
  
  func performAction() {
    action.execute(context, self)
  }

  func setOrigin ( row: Int, col: Int ) {
    originRow = row
    originCol = col
  }

  func setHighlightActive ( _ active: Bool ) {
    isHighlightActive = active
  }


  public func width ( maxWidth: Int? = nil ) -> Int {
    let baseWidth = name.count + 2
    guard let maxWidth = maxWidth else { return baseWidth }
    return min(baseWidth, max(0, maxWidth))
  }


  public func render ( in size: winsize ) -> [AnsiSequence]? {

    guard !name.isEmpty else { return nil }

    let columns     = Int(size.ws_col)
    let available   = columns - originCol + 1
    let targetWidth = width ( maxWidth: available )

    guard available > 0 else { return nil }
    guard targetWidth > 0 else { return nil }

    let highlightPalette = ElementStyle.highlightPalette ( for: style )
    let activeBackground = isHighlightActive ? highlightPalette.background : style.background
    let activeForeground = isHighlightActive ? highlightPalette.foreground : style.foreground

    var remaining  = targetWidth
    var sequences: [AnsiSequence] = [
      .hideCursor,
      .moveCursor ( row: originRow, col: originCol ),
      .backcolor  ( activeBackground ),
      .forecolor  ( activeForeground ),
    ]

    if remaining > 0 {
      sequences.append ( .text(" ") )
      remaining -= 1
    }

    if remaining > 0 {
      let firstChar = String ( name.prefix(1) )
      sequences.append ( .bold(firstChar) )
      remaining -= 1

      if remaining > 0 {
        let rest = String ( name.dropFirst().prefix(remaining) )
        if !rest.isEmpty {
          sequences.append ( .text(rest) )
          remaining -= rest.count
        }
      }
    }

    if remaining > 0 {
      let trailingSpaceCount = min(1, remaining)
      sequences.append ( .text(String(repeating: " ", count: trailingSpaceCount)) )
      remaining -= trailingSpaceCount
    }

    // Wrap the assembled row so the renderer can validate placement alongside other components.
    let bounds  = BoxBounds ( row: originRow, col: originCol, width: targetWidth, height: 1 )
    let element = TUIElement ( bounds: bounds, sequences: sequences )

    return element.render ( in: size )
  }

}


public final class MenuBar : Renderable {

  public var items : [MenuItem]
  public var style : ElementStyle


  public init ( items: [MenuItem], style: ElementStyle = ElementStyle() ) {
    self.items = items
    self.style = style
  }

  func locateMenuItem ( select: Character ) -> MenuItem? {
    for item in items {
      if item.responds(to: select) { return item }
    }
    return nil
  }

  public func render ( in size: winsize ) -> [AnsiSequence]? {

    let rows    = Int(size.ws_row)
    let columns = Int(size.ws_col)

    guard rows > 0 && columns > 0 else { return nil }

    var sequences: [AnsiSequence] = [
      .moveCursor  ( row: 1, col: 1),
      .backcolor   ( style.background ),
      .forecolor   ( style.foreground ),
      .repeatChars ( " ", count: columns),
      .resetcolor
    ]

    var currentColumn = 1

    for item in items {
      let available = columns - currentColumn + 1
      guard available > 0 else { break }

      item.setOrigin(row: 1, col: currentColumn)

      if let itemSequences = item.render(in: size) {
        sequences += itemSequences
      }

      currentColumn += item.width(maxWidth: available)
    }

    return sequences
  }
}
