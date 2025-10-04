import Foundation

// Centralise keyboard dispatch so overlays can reuse the same registration
// template without duplicating switch statements.  The handler keeps the API
// deliberately tiny so modal overlays can install every closure they need in a
// single step that mirrors the example supplied by the user.
final class KeyHandler {

  enum Bytes {
    case ascii   ( Data )
    case unicode ( Data )
  }

  typealias ControlInputHandler   = [TerminalInput.Input: () -> Bool]
  typealias BytesInputHandler     = ( Bytes ) -> Bool
  typealias ResponseInputHandler  = ( TerminalInput.Response ) -> Bool
  typealias GlobalControlHandler  = ( TerminalInput.Input ) -> Bool
  
  // Each table entry is immutable so callers make one decision about what the
  // overlay wants to trap.  This mirrors the provided example and keeps the
  // stack easy to reason about when overlays push/pop focus.
  struct HandlerTableEntry {
    let control                     : ControlInputHandler?
    let bytes                       : BytesInputHandler?
    let responses                   : ResponseInputHandler?
    let global                      : GlobalControlHandler?

    init(
      control                     : ControlInputHandler?       = nil,
      bytes                       : BytesInputHandler?         = nil,
      responses                   : ResponseInputHandler?      = nil,
      global                      : GlobalControlHandler?      = nil
    ) {
      self.control                     = control
      self.bytes                       = bytes
      self.responses                   = responses
      self.global                      = global
    }

    func traps ( _ key: TerminalInput.ControlKey ) -> Bool {
      guard let control = control else { return false }
      return control[.key(key)] != nil
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

  @discardableResult
  func handle ( _ input: TerminalInput.Input ) -> Bool {

    guard let handler = handlers.last else { return false }

    switch input {
      case .key, .cursor :
        if let action = handler.control?[input] { return action() }
        
        if let action = handler.global { return action ( input ) }

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
