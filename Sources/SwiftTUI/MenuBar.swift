import Foundation

public final class MenuItem : Renderable {

  public var name      : String
  public var foreground: ANSIForecolor
  public var background: ANSIBackcolor

  private var originRow: Int
  private var originCol: Int

  

  public init (
    name      : String,
    foreground: ANSIForecolor = .black,
    background: ANSIBackcolor = .bgWhite
  ) {
    self.name       = name
    self.foreground = foreground
    self.background = background
    self.originRow  = 1
    self.originCol  = 1
    
  }

  func responds ( to select: Character ) -> Bool {
    if let char = name.first?.uppercased(), char == select.uppercased() { return true  }
    else                                                                { return false }
  }
  
  func performAction() {
    log(name)
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

    guard rows > 0 && columns > 0 else { return nil }
    guard originRow >= 1 && originRow <= rows else { return nil }
    guard originCol >= 1 && originCol <= columns else { return nil }

    let available = columns - originCol + 1
    guard available > 0 else { return nil }

    var sequences: [AnsiSequence] = [
      .moveCursor(row: originRow, col: originCol),
      .backcolor ( background ),
      .forecolor ( foreground )
    ]

    var remaining = available

    if remaining > 0 {
      sequences.append(.text(" "))
      remaining -= 1
    }

    if remaining > 0 && !name.isEmpty {
      let firstChar = String(name.prefix(1))
      sequences.append(.bold(firstChar))
      remaining -= 1

      if remaining > 0 {
        let rest = String(name.dropFirst().prefix(remaining))
        if !rest.isEmpty {
          sequences.append(.text(rest))
          remaining -= rest.count
        }
      }
    }

    if remaining > 0 {
      let trailingSpaceCount = min(1, remaining)
      sequences.append(.text(String(repeating: " ", count: trailingSpaceCount)))
      remaining -= trailingSpaceCount
    }

    sequences.append(.resetcolor)

    return sequences
  }
}


public final class MenuBar : Renderable {

  public var items     : [MenuItem]
  public var foreground: ANSIForecolor
  public var background: ANSIBackcolor


  public init (
    items     : [MenuItem],
    foreground: ANSIForecolor = .black,
    background: ANSIBackcolor = .bgWhite
  ) {
    self.items      = items
    self.foreground = foreground
    self.background = background
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
      .moveCursor(row: 1, col: 1),
      .backcolor ( background ),
      .forecolor ( foreground ),
      .repeatChars(" ", count: columns),
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
