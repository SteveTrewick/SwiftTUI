import Foundation

public final class MenuItem : Renderable {

  public var name   : String
  public var style  : ElementStyle
  public var action : MenuAction
  public var context: MenuActionContext
  
  private var originRow: Int
  private var originCol: Int
  
  

  public init ( name: String, style: ElementStyle, context: MenuActionContext, action: MenuAction ) {
    self.name       = name
    self.context    = context
    self.action     = action
    self.style      = style
    self.originRow  = 1
    self.originCol  = 1
    
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


  public func width ( maxWidth: Int? = nil ) -> Int {
    let baseWidth = name.count + 2
    guard let maxWidth = maxWidth else { return baseWidth }
    return min(baseWidth, max(0, maxWidth))
  }


  public func render ( in size: winsize ) -> [AnsiSequence]? {

    let rows    = Int(size.ws_row)
    let columns = Int(size.ws_col)

    guard !name.isEmpty else { return nil }

    // Validate the terminal dimensions before emitting any bytes. Rendering
    // outside the reported window would at best waste work and at worst leave
    // the cursor in an unexpected position for the caller.
    guard rows > 0 && columns > 0 else { return nil }
    guard originRow >= 1 && originRow <= rows else { return nil }
    guard originCol >= 1 && originCol <= columns else { return nil }

    var remaining = columns - originCol + 1
    // If the menu origin is beyond the last visible column there is nothing to
    // paint; return early so we do not emit color resets or other stray bytes.
    guard remaining > 0 else { return nil }

    // Build the sequence list beginning with cursor placement and the color
    // attributes that define this item's visual style. These must precede any
    // text so the glyphs inherit the intended foreground/background pairing.
    var sequences: [AnsiSequence] = [
      .moveCursor ( row: originRow, col: originCol ),
      .backcolor  ( style.background ),
      .forecolor  ( style.foreground )
    ]

    // Insert a leading space when possible. This gives each menu entry a
    // consistent gutter so adjacent labels do not touch one another.
    if remaining > 0 {
      sequences.append(.text(" "))
      remaining -= 1
    }

    if remaining > 0 {
      let firstChar = String(name.prefix(1))
      // Emit the first character in bold to signal the keyboard accelerator.
      // The highlight allows users to see which key activates this menu item.
      sequences.append(.bold(firstChar))
      remaining -= 1

      if remaining > 0 {
        let rest = String(name.dropFirst().prefix(remaining))
        if !rest.isEmpty {
          // Append the remaining portion of the label that fits within the
          // allocated width. Truncation is handled implicitly by prefixing with
          // the number of columns still available.
          sequences.append(.text(rest))
          remaining -= rest.count
        }
      }
    }

    if remaining > 0 {
      let trailingSpaceCount = min(1, remaining)
      // Pad with a trailing space when there is still room. This ensures the
      // background color extends through the cell immediately following the
      // label, producing a solid block under the menu entry.
      sequences.append(.text(String(repeating: " ", count: trailingSpaceCount)))
      remaining -= trailingSpaceCount
    }

    // Restore the caller's color configuration so subsequent drawing routines
    // are not forced to undo our styling choices.
    sequences.append(.resetcolor)

    return sequences
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
