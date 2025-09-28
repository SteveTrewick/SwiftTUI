import Foundation

#if canImport(Trace)
import Trace
#endif

/// `TerminalInputHandler` incrementally decodes the raw byte stream coming from the
/// terminal into higher level key and response events.  It keeps a rolling buffer so
/// that escape sequences that arrive over multiple reads are reassembled before we
/// attempt to decode them.
public struct TerminalInputHandler {

  /// Option set describing the modifier keys that were active for a key event.
  public struct Modifiers: OptionSet {
    public let rawValue: Int

    public init(rawValue: Int) {
      self.rawValue = rawValue
    }

    public static let shift   = Modifiers(rawValue: 1 << 0)
    public static let control = Modifiers(rawValue: 1 << 1)
    public static let alt     = Modifiers(rawValue: 1 << 2)
  }

  /// Special non-character keys frequently reported by ANSI terminals.
  public enum SpecialKey {
    case home
    case end
    case insert
    case delete
    case pageUp
    case pageDown
    case backTab
  }

  /// A semantic representation of a decoded key.
  public enum Key {
    case control(TerminalInput.ControlKey)
    case cursor(TerminalInput.CursorKey)
    case function(Int)
    case character(Character)
    case special(SpecialKey)
  }

  /// High level terminal input event.
  public enum Event {
    case key(KeyEvent)
    case response(TerminalInput.Response)
    case unknown(Data)
  }

  /// Represents a key press, including any modifier state.
  public struct KeyEvent {
    public let key: Key
    public let modifiers: Modifiers
  }

  private var buffer = Data()

  public init() {}

  /// Feed additional bytes from the terminal into the handler.
  /// - Parameter bytes: New bytes read from the terminal.
  /// - Returns: All fully decoded events that were completed after appending the bytes.
  public mutating func process(_ bytes: Data) -> [Event] {
    buffer.append(bytes)
    return drain(allowLonelyEscape: false)
  }

  /// Flushes any pending escape prefix. Call this when the input source is idle to
  /// commit an isolated ESC key press.
  public mutating func flushPending() -> [Event] {
    return drain(allowLonelyEscape: true)
  }

  // MARK: - Parsing

  private mutating func drain(allowLonelyEscape: Bool) -> [Event] {
    var events: [Event] = []

    while let event = nextEvent(allowLonelyEscape: allowLonelyEscape) {
      events.append(event)
    }

    return events
  }

  private mutating func nextEvent(allowLonelyEscape: Bool) -> Event? {
    guard !buffer.isEmpty else { return nil }

    guard let firstByte = buffer.first else { return nil }

    if firstByte == 0x1b {
      return parseEscape(allowLonelyEscape: allowLonelyEscape)
    }

    if let control = Self.controlKeyMap[firstByte] {
      buffer.removeFirst()
      return .key(KeyEvent(key: .control(control), modifiers: []))
    }

    return parseCharacter(modifiers: [])
  }

  private mutating func parseEscape(allowLonelyEscape: Bool) -> Event? {
    if buffer.count == 1 {
      guard allowLonelyEscape else { return nil }
      buffer.removeFirst()
      return .key(KeyEvent(key: .control(.ESC), modifiers: []))
    }

    guard let secondByte = buffer.dropFirst().first else {
      return nil
    }

    switch secondByte {
      case 0x5b: // "[" CSI
        return parseCSI()
      case 0x4f: // "O" SS3
        return parseSS3()
      default:
        return parseAltSequence()
    }
  }

  private mutating func parseCSI() -> Event? {
    guard let finalIndex = indexOfFinalByte(startingAt: 2) else { return nil }

    let count = finalIndex + 1
    let sequence = popPrefix(count)
    let body = sequence.dropFirst(2)
    guard let finalByte = body.last else { return nil }

    let parameterBytes = body.dropLast()
    let parameters = parseParameters(ArraySlice(parameterBytes))
    let (modifiers, remainingParameters) = extractModifiers(from: parameters)

    switch finalByte {
      case 0x41: // A
        return .key(KeyEvent(key: .cursor(.up), modifiers: modifiers))
      case 0x42: // B
        return .key(KeyEvent(key: .cursor(.down), modifiers: modifiers))
      case 0x43: // C
        return .key(KeyEvent(key: .cursor(.right), modifiers: modifiers))
      case 0x44: // D
        return .key(KeyEvent(key: .cursor(.left), modifiers: modifiers))
      case 0x46: // F (End)
        return .key(KeyEvent(key: .special(.end), modifiers: modifiers))
      case 0x48: // H (Home)
        return .key(KeyEvent(key: .special(.home), modifiers: modifiers))
      case 0x52: // R - cursor position report
        if remainingParameters.count >= 2,
           let row = remainingParameters[safe: 0],
           let column = remainingParameters[safe: 1] {
          return .response(.CUROSR(row: row, column: column))
        }
      case 0x5a: // Z - Back tab
        var mods = modifiers
        if mods.isEmpty { mods.insert(.shift) }
        return .key(KeyEvent(key: .special(.backTab), modifiers: mods))
      case 0x7e: // ~
        if let code = remainingParameters.first {
          return parseCSITilde(code: code, modifiers: modifiers)
        }
      default:
        break
    }

    return .unknown(sequence)
  }

  private mutating func parseSS3() -> Event? {
    guard let finalIndex = indexOfFinalByte(startingAt: 2) else { return nil }

    let count = finalIndex + 1
    let sequence = popPrefix(count)
    let body = sequence.dropFirst(2)
    guard let finalByte = body.last else { return nil }

    let parameterBytes = body.dropLast()
    let parameters = parseParameters(ArraySlice(parameterBytes))
    let (modifiers, _) = extractModifiers(from: parameters)

    switch finalByte {
      case 0x41: // A
        return .key(KeyEvent(key: .cursor(.up), modifiers: modifiers))
      case 0x42: // B
        return .key(KeyEvent(key: .cursor(.down), modifiers: modifiers))
      case 0x43: // C
        return .key(KeyEvent(key: .cursor(.right), modifiers: modifiers))
      case 0x44: // D
        return .key(KeyEvent(key: .cursor(.left), modifiers: modifiers))
      case 0x48: // H
        return .key(KeyEvent(key: .special(.home), modifiers: modifiers))
      case 0x46: // F
        return .key(KeyEvent(key: .special(.end), modifiers: modifiers))
      case 0x50: // P
        return .key(KeyEvent(key: .function(1), modifiers: modifiers))
      case 0x51: // Q
        return .key(KeyEvent(key: .function(2), modifiers: modifiers))
      case 0x52: // R
        return .key(KeyEvent(key: .function(3), modifiers: modifiers))
      case 0x53: // S
        return .key(KeyEvent(key: .function(4), modifiers: modifiers))
      default:
        break
    }

    return .unknown(sequence)
  }

  private mutating func parseAltSequence() -> Event? {
    guard let (scalar, length) = decodeFirstScalar(in: buffer, startingAt: 1) else {
      return nil
    }

    let consumed = 1 + length
    let modifiers: Modifiers = [.alt]
    let value = scalar.value

    if let control = Self.controlKeyMap[UInt8(truncatingIfNeeded: value)] {
      buffer.removeFirst(consumed)
      return .key(KeyEvent(key: .control(control), modifiers: modifiers))
    }

    if value == 0x1b { // Alt+Esc
      buffer.removeFirst(consumed)
      return .key(KeyEvent(key: .control(.ESC), modifiers: modifiers))
    }

    if let event = parseCharacter(consuming: consumed, modifiers: modifiers) {
      return event
    }

    return nil
  }

  private mutating func parseCharacter(modifiers: Modifiers) -> Event? {
    guard let (_, length) = decodeFirstScalar(in: buffer, startingAt: 0) else {
      return nil
    }

    return parseCharacter(consuming: length, modifiers: modifiers)
  }

  private mutating func parseCharacter(consuming length: Int, modifiers: Modifiers) -> Event? {
    guard buffer.count >= length else { return nil }

    let slice = buffer.prefix(length)
    guard let string = String(data: slice, encoding: .utf8), let character = string.first else {
      return nil
    }

    buffer.removeFirst(length)
    return .key(KeyEvent(key: .character(character), modifiers: modifiers))
  }

  private func parseParameters(_ bytes: ArraySlice<UInt8>) -> [Int] {
    guard !bytes.isEmpty else { return [] }

    let string = String(decoding: Data(bytes), as: UTF8.self)
    if string.isEmpty { return [] }

    return string.split(separator: ";").compactMap { component -> Int? in
      let trimmed = component.trimmingCharacters(in: Self.parameterTrimCharacters)
      return Int(trimmed)
    }
  }

  private func extractModifiers(from parameters: [Int]) -> (Modifiers, [Int]) {
    guard let last = parameters.last, let modifiers = modifiers(for: last) else {
      return ([], parameters)
    }

    var remaining = parameters
    remaining.removeLast()
    return (modifiers, remaining)
  }

  private func modifiers(for parameter: Int) -> Modifiers? {
    switch parameter {
      case 2:  return [.shift]
      case 3:  return [.alt]
      case 4:  return [.shift, .alt]
      case 5:  return [.control]
      case 6:  return [.shift, .control]
      case 7:  return [.alt, .control]
      case 8:  return [.shift, .alt, .control]
      default: return nil
    }
  }

  private mutating func parseCSITilde(code: Int, modifiers: Modifiers) -> Event? {
    guard let key = Self.csiTildeMap[code] else { return nil }
    return .key(KeyEvent(key: key, modifiers: modifiers))
  }

  private mutating func indexOfFinalByte(startingAt offset: Int) -> Int? {
    var index = offset
    while index < buffer.count {
      let byte = buffer[index]
      if byte >= 0x40 && byte <= 0x7e {
        return index
      }
      index += 1
    }
    return nil
  }

  private mutating func popPrefix(_ count: Int) -> Data {
    let prefix = buffer.prefix(count)
    buffer.removeFirst(count)
    return Data(prefix)
  }

  private func decodeFirstScalar(in data: Data, startingAt offset: Int) -> (UnicodeScalar, Int)? {
    let remaining = data.count - offset
    guard remaining > 0 else { return nil }

    for length in 1...min(4, remaining) {
      let end = offset + length
      let slice = data[offset..<end]
      if let string = String(data: slice, encoding: .utf8), let scalar = string.unicodeScalars.first, string.unicodeScalars.count == 1 {
        return (scalar, length)
      }
    }

    return nil
  }

  // MARK: - Static helpers

  private static let parameterTrimCharacters = CharacterSet(charactersIn: "?=<> ")

  private static let controlKeyMap: [UInt8: TerminalInput.ControlKey] = [
    0x00 : .NULL,
    0x01 : .STX,
    0x02 : .SOT,
    0x03 : .ETX,
    0x04 : .EOT,
    0x05 : .ENQ,
    0x06 : .ACK,
    0x07 : .BEL,
    0x08 : .BACKSPACE,
    0x09 : .TAB,
    0x0a : .LF,
    0x0b : .VT,
    0x0c : .FF,
    0x0d : .RETURN,
    0x0e : .SO,
    0x0f : .SI,
    0x10 : .DLE,
    0x11 : .DC1,
    0x12 : .DC2,
    0x13 : .DC3,
    0x14 : .DC4,
    0x15 : .NAK,
    0x16 : .SYN,
    0x17 : .ETB,
    0x18 : .CAN,
    0x19 : .EM,
    0x1a : .SUB,
    0x1b : .ESC,
    0x1c : .FS,
    0x1d : .GS,
    0x1e : .RS,
    0x1f : .US,
    0x7f : .DEL
  ]

  private static let csiTildeMap: [Int: Key] = [
    1  : .special(.home),
    2  : .special(.insert),
    3  : .special(.delete),
    4  : .special(.end),
    5  : .special(.pageUp),
    6  : .special(.pageDown),
    7  : .special(.home),
    8  : .special(.end),
    11 : .function(1),
    12 : .function(2),
    13 : .function(3),
    14 : .function(4),
    15 : .function(5),
    17 : .function(6),
    18 : .function(7),
    19 : .function(8),
    20 : .function(9),
    21 : .function(10),
    23 : .function(11),
    24 : .function(12),
    25 : .function(13),
    26 : .function(14),
    28 : .function(15),
    29 : .function(16),
    31 : .function(17),
    32 : .function(18),
    33 : .function(19),
    34 : .function(20)
  ]
}

// MARK: - Safe collection access helper

private extension Array where Element == Int {
  subscript(safe index: Int) -> Int? {
    guard index >= 0, index < count else { return nil }
    return self[index]
  }
}
