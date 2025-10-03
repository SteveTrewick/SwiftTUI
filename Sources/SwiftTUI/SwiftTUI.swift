import Foundation
#if canImport(OSLog)
import OSLog
#endif

public func log(_ string: String) {
#if canImport(OSLog)
  os_log(.debug, "%{public}s", "\(string)")
#else
  print(string)
#endif
}

public protocol Renderable {
  func render ( in size: winsize ) -> [AnsiSequence]?
}


struct TUIElement : Renderable {

  var sequences: [AnsiSequence]
  var bounds   : BoxBounds

  init ( bounds: BoxBounds, sequences: [AnsiSequence] ) {
    // Cache the prebuilt sequences so repeated renders avoid rebuilding the same
    // ANSI payload.  Validation still happens per frame to keep bounds in sync
    // with the active terminal size.
    self.bounds    = bounds
    self.sequences = sequences
  }

  static func textRow ( bounds: BoxBounds, style: ElementStyle, text: String, includeHideCursor: Bool = true ) -> TUIElement {

    var sequences: [AnsiSequence] = []

    if includeHideCursor { sequences.append(.hideCursor) }

    sequences += [
      .moveCursor ( row: bounds.row, col: bounds.col ),
      .backcolor  ( style.background ),
      .forecolor  ( style.foreground ),
      .text       ( text ),
    ]

    return TUIElement ( bounds: bounds, sequences: sequences )
  }

  public func render ( in size: winsize ) -> [AnsiSequence]? {
    guard TUIElement.bounds ( bounds, fitIn: size ) else { return nil }
    return sequences
  }

  static func render ( _ elements: [TUIElement], in size: winsize ) -> [AnsiSequence]? {

    var output: [AnsiSequence] = []

    for element in elements {
      guard let sequences = element.render ( in: size ) else { return nil }
      output += sequences
    }

    return output
  }

  private static func bounds ( _ bounds: BoxBounds, fitIn size: winsize ) -> Bool {

    let rows    = Int(size.ws_row)
    let columns = Int(size.ws_col)

    guard bounds.width  > 0 else { return false }
    guard bounds.height > 0 else { return false }

    guard rows    > 0 else { return false }
    guard columns > 0 else { return false }

    guard bounds.row >= 1 else { return false }
    guard bounds.col >= 1 else { return false }

    let bottom = bounds.row + bounds.height - 1
    let right  = bounds.col + bounds.width  - 1

    guard bottom <= rows else { return false }
    guard right  <= columns else { return false }

    return true
  }

}
