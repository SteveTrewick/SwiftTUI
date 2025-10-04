import Foundation

// Centralise keyboard dispatch so overlays can share a small amount of stateful
// behaviour such as ESC swallowing without duplicating switch statements.  The
// handler keeps the registration API deliberately tiny so modal overlays can
// install the closures they need in a single step that mirrors the template the
// user supplied.
final class KeyHandler {

  enum Bytes {
    case ascii   ( Data )
    case unicode ( Data )
  }

  typealias ControlInputHandler   = [TerminalInput.Input: () -> Bool]
  typealias BytesInputHandler     = ( Bytes ) -> Bool
  typealias ResponseInputHandler  = ( TerminalInput.Response ) -> Bool

  // Each table entry is immutable so callers make one decision about what the
  // overlay wants to trap.  This mirrors the provided example and keeps the
  // stack easy to reason about when overlays push/pop focus.
  struct HandlerTableEntry {
    let control                     : ControlInputHandler?
    let bytes                       : BytesInputHandler?
    let responses                   : ResponseInputHandler?
    let global                      : ControlInputHandler?
    let swallowPrintableAfterEscape : Bool

    init(
      control                     : ControlInputHandler?       = nil,
      bytes                       : BytesInputHandler?         = nil,
      responses                   : ResponseInputHandler?      = nil,
      global                      : ControlInputHandler?       = nil,
      swallowPrintableAfterEscape : Bool                       = false
    ) {
      self.control                     = control
      self.bytes                       = bytes
      self.responses                   = responses
      self.global                      = global
      self.swallowPrintableAfterEscape = swallowPrintableAfterEscape
    }

    func traps ( _ key: TerminalInput.ControlKey ) -> Bool {
      guard let control = control else { return false }
      return control[.key(key)] != nil
    }

    var handlesEscape : Bool {
      guard let control = control else { return false }
      return control[.key(.ESC)] != nil
    }
  }

  private var handlers : [HandlerTableEntry]

  init() {
    self.handlers = []
  }

  func pushHandler ( _ handler: HandlerTableEntry ) {
    handlers.append ( handler )
  }

  func popHandler() {
    guard !handlers.isEmpty else { return }
    handlers.removeLast()
  }

  func trapsControl ( _ key: TerminalInput.ControlKey ) -> Bool {
    guard let entry = handlers.last else { return false }
    return entry.traps ( key )
  }

  var shouldSwallowPrintableAfterEscape: Bool {
    guard let entry = handlers.last else { return false }
    return entry.handlesEscape && entry.swallowPrintableAfterEscape
  }

  @discardableResult
  func handle ( _ input: TerminalInput.Input ) -> Bool {

    guard let handler = handlers.last else { return false }

    switch input {
      case .key, .cursor :
        if let action = handler.control?[input] { return action() }
        if let action = handler.global?[input]  { return action() }

      case .ascii   ( let data ) :
        if let action = handler.bytes { return action ( .ascii ( data ) ) }

      case .unicode ( let data ) :
        if let action = handler.bytes { return action ( .unicode ( data ) ) }

      case .response ( let response ) :
        guard let action = handler.responses else { break }

        // By delegating the matching logic to the consumer we avoid
        // re-implementing wildcard dictionaries here.  The handler now owns the
        // decision about which terminal responses to trap and how to interpret
        // the payload, which keeps this dispatcher tiny and predictable.
        return action ( response )
    }

    return false
  }
}
