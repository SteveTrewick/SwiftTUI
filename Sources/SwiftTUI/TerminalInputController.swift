import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

#if canImport(Trace)
import Trace
#endif
#if canImport(PosixInputStream)
import PosixInputStream
#endif

/*
  TerminalInputController now carries both the streaming controller and the
  translation tables that used to live in TerminalInput. Folding the types into
  a single class keeps the decoder state, translation maps and platform facing
  APIs aligned so a consumer never has to choose between two entry points.
*/
public class TerminalInputController {

  public enum ControlKey : Hashable {
    case NULL
    case STX
    case SOT
    case ETX        // CTRL - C
    case EOT        // CTRL - D
    case ENQ
    case ACK
    case BEL
    case BACKSPACE  // Backspace
    case TAB        // Tab
    case LF
    case VT
    case FF
    case RETURN     // CTRL - M (return on macOS terminal
    case SO
    case SI
    case DLE
    case DC1
    case DC2
    case DC3
    case DC4
    case NAK
    case SYN
    case ETB
    case CAN
    case EM
    case SUB         // CTRL - Z
    case ESC
    case FS
    case GS
    case RS
    case US
    case DEL         // sent by <- key on macOS (backspace vs del bunfight)
  }


  public enum CursorKey : Hashable {
    case left, right, up, down
  }


  public enum Response : Hashable {
    case CURSOR (row: Int, column: Int)
  }


  public enum Input : Hashable {
    case key     (TerminalInputController.ControlKey)
    case cursor  (TerminalInputController.CursorKey)
    case response(TerminalInputController.Response)
    case ascii   (Data)
    case unicode (Data)
  }


  struct ASNISequence {
    let function :  String
    let params   : [String]
  }


  struct ParserContext {

    let ascii_table : [UInt8 : TerminalInputController.ControlKey] = [
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


    let cursor_table : [String : TerminalInputController.CursorKey] = [
      "[A" : .up,
      "[B" : .down,
      "[C" : .right,
      "[D" : .left
    ]


    func translate(_ u8: UInt8) -> TerminalInputController.ControlKey? {
      ascii_table[u8]
    }


    func translate(_ string: String) -> TerminalInputController.CursorKey? {
      cursor_table[string]
    }


    func translate(_ sequence: TerminalInputController.ASNISequence) -> TerminalInputController.Response? {

      switch sequence.function {

        case "R" :
          guard sequence.params.count >= 2 else { return nil }
          guard let row    = Int(sequence.params[0])  else { return nil }
          guard let column = Int(sequence.params[1])  else { return nil }

          return .CURSOR(row: row, column: column)

        default : return nil
      }
    }


    func decompose( _ sequence: String) -> TerminalInputController.ASNISequence {
      TerminalInputController.ASNISequence (
        function: String(sequence.last!),
        params  : sequence.dropFirst().dropLast().components(separatedBy: ";")
      )
    }


    func errordesc(_ bytes: Data) -> String {
      String(describing: String(data: bytes, encoding: .utf8))
    }
  }


  /*
    Decoder used to be a struct with mutating methods. It carries buffers and
    state machines that must survive across feed() calls so making it a class
    prevents accidental copies and matches the fact that it owns mutable state.
  */
  class Decoder {

    enum TextContext {
      case plain
      case meta
    }


    enum OSCTerminator {
      case bel
      case st
    }


    struct OSCState {
      let terminator : OSCTerminator
      var sawEscape  : Bool
    }


    enum ParserState {
      case ground
      case escape
      case csi
      case osc (OSCState)
      case utf8(TextContext, remaining: Int)
    }


    let parser        : TerminalInputController.ParserContext
    var state         : ParserState
    var escapeBuffer  : Data
    var unicodeBuffer : Data
    var textBuffer    : Data


    init ( context: TerminalInputController.ParserContext ) {
      self.parser        = context
      self.state         = .ground
      self.escapeBuffer  = Data()
      self.unicodeBuffer = Data()
      self.textBuffer    = Data()
    }


    func feed ( _ chunk: Data ) -> Result<[TerminalInputController.Input], Trace> {

      var outputs : [TerminalInputController.Input] = []

      guard chunk.count > 0 else { return .success(outputs) }

      for byte in chunk {

        switch state {

          case .ground :

            if byte == 0x1b {
              emitText(into: &outputs)
              escapeBuffer = Data([byte])
              state        = .escape
              continue
            }

            if let key = parser.translate(byte) {
              emitText(into: &outputs)
              outputs += [ .key(key) ]
              continue
            }

            if byte < 0x80 {
              textBuffer.append(byte)
              continue
            }

            emitText(into: &outputs)

            guard let remaining = continuationLength(for: byte) else {
              return .failure(Trace(parser, tag: "invalid utf8 lead byte \(parser.errordesc(Data([byte])))"))
            }

            unicodeBuffer = Data([byte])
            state         = .utf8(.plain, remaining: remaining)


          case .escape :

            escapeBuffer.append(byte)

            switch byte {

              case 0x5b :
                state = .csi

              case 0x5d :
                state = .osc(OSCState(terminator: .bel, sawEscape: false))

              case 0x50 :
                state = .osc(OSCState(terminator: .st, sawEscape: false))

              default :

                if byte < 0x20 || byte == 0x7f {
                  return .failure(Trace(parser, tag: "unhandled control sequence \(parser.errordesc(escapeBuffer))"))
                }

                if byte < 0x80 {
                  outputs += [ .key(.ESC), .ascii(Data([byte])) ]
                  escapeBuffer.removeAll()
                  state = .ground
                }
                else {
                  guard let remaining = continuationLength(for: byte) else {
                    return .failure(Trace(parser, tag: "invalid utf8 lead byte \(parser.errordesc(escapeBuffer))"))
                  }

                  outputs += [ .key(.ESC) ]
                  unicodeBuffer = Data([byte])
                  state         = .utf8(.meta, remaining: remaining)
                }
            }


          case .csi :

            escapeBuffer.append(byte)

            if isFinalCSI(byte) {
              let payload = escapeBuffer.dropFirst()

              guard let sequence = String(data: payload, encoding: .utf8) else {
                return .failure(Trace(parser, tag: "unhandled non utf8 sequence \(parser.errordesc(escapeBuffer))"))
              }

              if let cursor = parser.translate(sequence) {
                outputs += [ .cursor(cursor) ]
              }
              else if let response = parser.translate(parser.decompose(sequence)) {
                outputs += [ .response(response) ]
              }
              else {
                return .failure(Trace(parser, tag: "unhandled control sequence \(parser.errordesc(escapeBuffer))"))
              }

              escapeBuffer.removeAll()
              state = .ground
            }


          case .osc(var oscState) :

            escapeBuffer.append(byte)

            switch oscState.terminator {

              case .bel :
                if byte == 0x07 {
                  return .failure(Trace(parser, tag: "unhandled control sequence \(parser.errordesc(escapeBuffer))"))
                }

              case .st :
                if oscState.sawEscape {
                  if byte == 0x5c {
                    return .failure(Trace(parser, tag: "unhandled control sequence \(parser.errordesc(escapeBuffer))"))
                  }
                  else {
                    oscState.sawEscape = false
                  }
                }
                else if byte == 0x1b {
                  oscState.sawEscape = true
                }
            }

            state = .osc(oscState)


          case .utf8(let context, var remaining) :

            guard isContinuation(byte) else {
              return .failure(Trace(parser, tag: "invalid utf8 continuation byte \(parser.errordesc(Data([byte])))"))
            }

            unicodeBuffer.append(byte)

            if context == .meta {
              escapeBuffer.append(byte)
            }

            remaining -= 1

            if remaining == 0 {

              switch context {

                case .plain :
                  outputs += [ .unicode(unicodeBuffer) ]

                case .meta :
                  outputs += [ .unicode(unicodeBuffer) ]
              }

              unicodeBuffer.removeAll()
              escapeBuffer.removeAll()
              state = .ground
            }
            else {
              state = .utf8(context, remaining: remaining)
            }
        }
      }

      emitText(into: &outputs)

      return .success(outputs)
    }


    func emitText ( into outputs: inout [TerminalInputController.Input] ) {

      guard textBuffer.count > 0 else { return }

      let data = textBuffer

      textBuffer = Data()

      if data.count == 1, let first = data.first, first < 0x80 {
        outputs += [ .ascii(data) ]
      }
      else {
        outputs += [ .unicode(data) ]
      }
    }


    func flush() -> Result<[TerminalInputController.Input], Trace> {

      switch state {

        case .ground :
          var outputs : [TerminalInputController.Input] = []
          emitText(into: &outputs)
          return .success(outputs)

        case .escape :
          return .failure(Trace(parser, tag: "unterminated escape sequence \(parser.errordesc(escapeBuffer))"))

        case .csi :
          return .failure(Trace(parser, tag: "unterminated control sequence \(parser.errordesc(escapeBuffer))"))

        case .osc :
          return .failure(Trace(parser, tag: "unterminated control sequence \(parser.errordesc(escapeBuffer))"))

        case .utf8(let context, _) :
          switch context {
            case .plain :
              return .failure(Trace(parser, tag: "unterminated unicode scalar \(parser.errordesc(unicodeBuffer))"))
            case .meta  :
              return .failure(Trace(parser, tag: "unterminated meta sequence \(parser.errordesc(escapeBuffer))"))
          }
      }
    }


    func isFinalCSI(_ byte: UInt8) -> Bool {
      byte >= 0x40 && byte <= 0x7e
    }


    func continuationLength(for byte: UInt8) -> Int? {
      switch byte {
        case 0xc2 ... 0xdf : return 1
        case 0xe0 ... 0xef : return 2
        case 0xf0 ... 0xf4 : return 3
        default            : return nil
      }
    }


    func isContinuation(_ byte: UInt8) -> Bool {
      (byte & 0xc0) == 0x80
    }
  }


  private var termios_orig = termios()
  private var termios_curr = termios()
  private let parserContext = ParserContext()
  private lazy var decoder  : TerminalInputController.Decoder = TerminalInputController.Decoder(context: parserContext)

  public let stream : PosixInputStream

  public var handler : ( (Result<[TerminalInputController.Input], Trace>) -> Void  )? = nil


  public init() {

    tcflush(STDIN_FILENO, TCIFLUSH)
    _ = fcntl(STDIN_FILENO, F_SETFL, O_NONBLOCK)
    tcgetattr(STDIN_FILENO, &termios_orig)

    termios_curr   = termios_orig
    stream         = PosixInputStream(descriptor: STDIN_FILENO)
    stream.handler = self.contextualise
  }


  func contextualise (result: Result<Data, Trace> ) {
    switch result {
      case .failure(let trace) :
        emitTrailingInputs()
        handler? ( .failure(trace) )

      case .success(let bytes) :
        guard !bytes.isEmpty else {
          emitTrailingInputs()
          return
        }

        switch decoder.feed ( bytes ) {
          case .failure(let trace) : handler? ( .failure(trace) )
          case .success(let inputs) :
            guard !inputs.isEmpty else { return }
            handler? ( .success(inputs) )
        }
    }
  }


  public func makeRaw() {
    cfmakeraw(&termios_curr)
    tcsetattr(STDIN_FILENO, TCSANOW, &termios_curr)
  }


  public func unmakeRaw() {
    tcsetattr(STDIN_FILENO, TCSANOW, &termios_orig)
  }


  private func emitTrailingInputs() {

    switch decoder.flush() {

      case .failure(let trace) :
        handler? ( .failure(trace) )

      case .success(let inputs) :
        guard !inputs.isEmpty else { return }
        handler? ( .success(inputs) )
    }
  }


  /*
    Tests and diagnostics still need a stateless helper, so we expose the old
    translate(bytes:) entry point as a static convenience. It spins up a fresh
    decoder with local tables while leaving the shared streaming instance alone.
  */
  public static func translate ( bytes: Data ) -> Result<[TerminalInputController.Input], Trace> {

    let context = ParserContext()

    guard bytes.count > 0 else { return .failure(Trace(context, tag: "zero byte count")) }

    let decoder = Decoder(context: context)

    switch decoder.feed(bytes) {

      case .failure(let trace) :
        return .failure(trace)

      case .success(let outputs) :

        switch decoder.flush() {

          case .failure(let trace) :
            return .failure(trace)

          case .success(let trailing) :
            return .success(outputs + trailing)
        }
    }
  }
}
