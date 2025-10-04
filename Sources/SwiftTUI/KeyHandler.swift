import Foundation

// Centralise keyboard dispatch so overlays can share a small amount of stateful
// behaviour such as ESC swallowing without duplicating switch statements.  The
// handler keeps the registration API deliberately tiny so modal overlays can
// wire the pieces they need and rely on the fallback for delegation.
final class KeyHandler {

  typealias ControlHandler  = () -> Bool
  typealias CursorHandler   = () -> Bool
  typealias PayloadHandler  = (Data) -> Bool
  typealias ResponseHandler = (TerminalInput.Response) -> Bool

  private var controlHandlers  : [TerminalInput.ControlKey: ControlHandler]
  private var cursorHandlers   : [TerminalInput.CursorKey: CursorHandler]
  private var asciiHandlers    : [PayloadHandler]
  private var unicodeHandlers  : [PayloadHandler]
  private var responseHandlers : [ResponseHandler]
  private var fallbackHandler  : ((TerminalInput.Input) -> Bool)?
  private var swallowPrintableAfterESC: Bool

  init ( swallowPrintableAfterESC: Bool = false ) {
    self.controlHandlers          = [:]
    self.cursorHandlers           = [:]
    self.asciiHandlers            = []
    self.unicodeHandlers          = []
    self.responseHandlers         = []
    self.fallbackHandler          = nil
    self.swallowPrintableAfterESC = swallowPrintableAfterESC
  }

  func registerControl ( _ key: TerminalInput.ControlKey, swallowPrintableAfterESC: Bool = false, handler: @escaping ControlHandler ) {
    controlHandlers[key] = handler
    if key == .ESC && swallowPrintableAfterESC {
      self.swallowPrintableAfterESC = true
    }
  }

  func registerCursor ( _ key: TerminalInput.CursorKey, handler: @escaping CursorHandler ) {
    cursorHandlers[key] = handler
  }

  func registerASCII ( _ handler: @escaping PayloadHandler ) {
    asciiHandlers.append(handler)
  }

  func registerUnicode ( _ handler: @escaping PayloadHandler ) {
    unicodeHandlers.append(handler)
  }

  func registerResponse ( _ handler: @escaping ResponseHandler ) {
    responseHandlers.append(handler)
  }

  func registerFallback ( _ handler: @escaping (TerminalInput.Input) -> Bool ) {
    fallbackHandler = handler
  }

  func trapsControl ( _ key: TerminalInput.ControlKey ) -> Bool {
    controlHandlers[key] != nil
  }

  var shouldSwallowPrintableAfterEscape: Bool {
    trapsControl ( .ESC ) && swallowPrintableAfterESC
  }

  @discardableResult
  func handle ( _ input: TerminalInput.Input ) -> Bool {
    switch input {

      case .key ( let key ) :
        if let handler = controlHandlers[key] {
          return handler()
        }

      case .cursor ( let key ) :
        if let handler = cursorHandlers[key] {
          return handler()
        }

      case .ascii ( let data ) :
        for handler in asciiHandlers where handler(data) { return true }

      case .unicode ( let data ) :
        for handler in unicodeHandlers where handler(data) { return true }

      case .response ( let response ) :
        for handler in responseHandlers where handler(response) { return true }
    }

    return fallbackHandler?(input) ?? false
  }
}
