import Foundation
#if canImport(Trace)
import Trace
#endif

/*
  Handle the various things that the macOS (and this is NOT portable)
  terminal will stuff into the STDIN pipe in response to a whole bunch of stuff.

  Basically it's all in band signalling, so that's where everything goes,
  especially with a term in raw mode there is very little to be done with signal
  handlers and such, so we need to catch a lot of, well, stuff.

  I havent written a whole ANSI spec parser because life is too short

  and stuff.

*/


public struct TerminalInput {


  // ASCII <= 0x1f, and on the mac also DEL at 0x7f as well as arrow keys
  // all of these occur by the user pressing a key, some of them require
  // us to do stuff (move the cursor, translate a CR/LF sequence, backspace, etc
  // some of them we pass to remoter terminal equipment, either way, they are all
  // special and require us to make decisions, so they each have an enum. sigh.

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


  // If the terminal is sending us escape sequences via stdin then it's (probably)
  // in response to something we asked it. This is likely to expand as we build
  // more features

  public enum Response : Hashable {
    case CURSOR (row: Int, column: Int)  // for now just cursor position
  }


  // our eventual output will be an array of these

  public enum Input : Hashable {
    case key     (TerminalInput.ControlKey)  // spesh key
    case cursor  (TerminalInput.CursorKey)   // cursor key
    case response(TerminalInput.Response)    // query response
    case ascii   (Data)                      // single ascii byte (not 7 bit clean, sigh)
    case unicode (Data)                      // multiple bytes
  }
  // ok, so we split ascii and unicode mainly because a) it probably isnt a great idea
  // to stuff unicode down a serial pipe and b) that's basically anky key ant ALT on
  // the mac and I want those for UI control, menus, etc. fight me.


  // intermediate struct for decoding escape sequences

  struct ASNISequence {
    let function :  String
    let params   : [String]
  }



  // O(1) map of ASCII codes to their symbolic enum

  let ascii_table : [UInt8 : TerminalInput.ControlKey] = [
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


  // O(1) map of arrow keys to their symbolic enum

  let cursor_table : [String : TerminalInput.CursorKey] = [
    "[A" : .up,
    "[B" : .down,
    "[C" : .right,
    "[D" : .left
  ]

  public init() {}
  // conversion funcs that retun nil if the input isnt one of the tables

  func translate(_ u8: UInt8) -> TerminalInput.ControlKey? {
    ascii_table[u8]
  }



  func translate(_ string: String) -> TerminalInput.CursorKey? {
    cursor_table[string]
  }



  // Add any query responses you want to process here.
  // for now it's just the cursor keys. failure of a sequence to map to
  // a response (or future encapsulation type) should be considered an error

  func translate(_ sequence: ASNISequence) -> TerminalInput.Response? {

    switch sequence.function {

      case "R" :
        guard sequence.params.count >= 2 else { return nil }
        guard let row    = Int(sequence.params[0])  else { return nil } // NB this will crash if params
        guard let column = Int(sequence.params[1])  else { return nil } // aren't there. hmm.

        return .CURSOR(row: row, column: column)

      default : return nil
    }
  }


  // ugly hacky way to extract params from an escape sequence formatted liek "[x;xA"
  // which accounts for many, though certainly not all, of the ones we expect xterm
  // to stuff in the pipe

  func decompose( _ sequence: String) -> ASNISequence {
    ASNISequence (
      function: String(sequence.last!),
      params  : sequence.dropFirst().dropLast().components(separatedBy: ";")
    )
  }


  // robust error handling

  func errordesc(_ bytes: Data) -> String {
    String(describing: String(data: bytes, encoding: .utf8))
  }


  /*
    Streaming decoder that keeps state between reads. The terminal will
    frequently fragment escape sequences across multiple reads, so we keep
    the current buffer and parser state around until we have the full
    sequence. A simple state machine keeps us grounded when we only have
    printable data while still allowing CSI / OSC responses and UTF8 scalars
    to span chunks.
  */

  struct Decoder {

    /*
      Streaming state machine that accepts raw bytes from STDIN and emits high level
      TerminalInput.Input values. The decoder loops byte-by-byte over each chunk,
      mutating a small ParserState enum to remember where we are in a potential
      escape sequence. Ordinary printable ASCII is buffered in textBuffer so we
      can coalesce long runs before emitting them, while multi-byte UTF-8 code
      points are staged in unicodeBuffer until their continuation bytes arrive.

      Control flow is intentionally strict:
        * ground       : default state that accumulates printable bytes and looks for
                         ESC to begin an in-band control sequence.
        * escape       : we have consumed ESC and are determining which control
                         family follows. Depending on the next byte we branch into
                         CSI, OSC, or a meta (ESC-prefixed UTF-8) sequence.
        * csi / osc    : parse parameterised responses from the terminal and map
                         them onto higher level enums. CSI stands for Control
                         Sequence Introducer (escape + "[") and covers cursor
                         motion and responses such as "ESC [ 6 n". A readable spec
                         is available at https://vt100.net/docs/vt510-rm/CSI.html .
                         OSC means Operating System Command (escape + "]" or
                         rarely "ESC P"), a family of terminal status commands such
                         as title changes. The xterm reference lives at
                         https://invisible-island.net/xterm/ctlseqs/ctlseqs.html .
        * utf8         : tracks remaining continuation bytes for both plain text
                         scalars and meta sequences that were introduced by ESC.

      The combination of the state machine and the explicit buffers lets us cope
      with fragmented reads (common on macOS's tty implementation) without losing
      information. emitText() flushes any pending ASCII/unicode runs whenever we
      switch away from ground, keeping ordering deterministic. flush() is provided
      so callers can surface partially received control sequences as errors if the
      input stream ends mid-sequence.
    */


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


    /*
      ParserState encodes the active branch of the state machine. CSI (Control
      Sequence Introducer) is introduced by "ESC [" and allows the terminal to
      report information like cursor position. OSC (Operating System Command) is
      introduced by "ESC ]" (or "ESC P" for ST-terminated variants) and lets the
      terminal send application-level metadata. Both definitions trace back to the
      DEC VT series; see https://vt100.net/docs/vt510-rm/ and
      https://invisible-island.net/xterm/ctlseqs/ctlseqs.html for historical and
      xterm-specific behaviour notes.
    */

    enum ParserState {
      case ground
      case escape
      case csi
      case osc (OSCState)
      case utf8(TextContext, remaining: Int)
    }


    var input         : TerminalInput
    var state         : ParserState
    var escapeBuffer  : Data
    var unicodeBuffer : Data
    var textBuffer    : Data


    init ( input: TerminalInput ) {
      self.input         = input
      self.state         = .ground
      self.escapeBuffer  = Data()
      self.unicodeBuffer = Data()
      self.textBuffer    = Data()
    }


    /*
      Core streaming routine. We walk each incoming byte, advance the state machine,
      and append any newly completed tokens into the outputs array. The method never
      emits partial data: printable text is staged in textBuffer until we know that
      we're leaving ground, and escapeBuffer/unicodeBuffer track in-flight control
      sequences so the caller either receives a fully decoded Input or an error when
      the sequence proves invalid. Returning Result keeps the fast path lean while
      still surfacing malformed UTF-8 or unsupported control messages for diagnosis.
    */

    mutating func feed ( _ chunk: Data ) -> Result<[TerminalInput.Input], Trace> {

      var outputs : [TerminalInput.Input] = []

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

            if let key = input.translate(byte) {
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
              return .failure(Trace(input, tag: "invalid utf8 lead byte \(input.errordesc(Data([byte])))"))
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
                  return .failure(Trace(input, tag: "unhandled control sequence \(input.errordesc(escapeBuffer))"))
                }

                if byte < 0x80 {
                  outputs += [ .key(.ESC), .ascii(Data([byte])) ]
                  escapeBuffer.removeAll()
                  state = .ground
                }
                else {
                  guard let remaining = continuationLength(for: byte) else {
                    return .failure(Trace(input, tag: "invalid utf8 lead byte \(input.errordesc(escapeBuffer))"))
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
                return .failure(Trace(input, tag: "unhandled non utf8 sequence \(input.errordesc(escapeBuffer))"))
              }

              if let cursor = input.translate(sequence) {
                outputs += [ .cursor(cursor) ]
              }
              else if let response = input.translate(input.decompose(sequence)) {
                outputs += [ .response(response) ]
              }
              else {
                return .failure(Trace(input, tag: "unhandled control sequence \(input.errordesc(escapeBuffer))"))
              }

              escapeBuffer.removeAll()
              state = .ground
            }


          case .osc(var oscState) :

            escapeBuffer.append(byte)

            switch oscState.terminator {

              case .bel :
                if byte == 0x07 {
                  return .failure(Trace(input, tag: "unhandled control sequence \(input.errordesc(escapeBuffer))"))
                }

              case .st :
                if oscState.sawEscape {
                  if byte == 0x5c {
                    return .failure(Trace(input, tag: "unhandled control sequence \(input.errordesc(escapeBuffer))"))
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
              return .failure(Trace(input, tag: "invalid utf8 continuation byte \(input.errordesc(Data([byte])))"))
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


    /*
      Flush any accumulated ground-state bytes. macOS often delivers long runs of
      printable characters in multiple reads, so we buffer them until either a control
      sequence or the caller explicitly asks for a flush. Single ASCII bytes remain
      tagged as .ascii to keep hot paths allocation-free, while longer runs and UTF-8
      scalars are surfaced as .unicode so downstream consumers can treat them as text
      without worrying about fragmentation.
    */

    mutating func emitText ( into outputs: inout [TerminalInput.Input] ) {

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


    /*
      Force completion when the reader reaches EOF. Any pending printable data gets
      emitted, but half-parsed control sequences are treated as fatal because they
      would otherwise leave the state machine stuck in escape or UTF-8 modes. This is
      particularly helpful for unit tests where we want deterministic failure rather
      than silent truncation.
    */

    mutating func flush() -> Result<[TerminalInput.Input], Trace> {

      switch state {

        case .ground :
          var outputs : [TerminalInput.Input] = []
          emitText(into: &outputs)
          return .success(outputs)

        case .escape :
          return .failure(Trace(input, tag: "unterminated escape sequence \(input.errordesc(escapeBuffer))"))

        case .csi :
          return .failure(Trace(input, tag: "unterminated control sequence \(input.errordesc(escapeBuffer))"))

        case .osc :
          return .failure(Trace(input, tag: "unterminated control sequence \(input.errordesc(escapeBuffer))"))

        case .utf8(let context, _) :
          switch context {
            case .plain :
              return .failure(Trace(input, tag: "unterminated unicode scalar \(input.errordesc(unicodeBuffer))"))
            case .meta  :
              return .failure(Trace(input, tag: "unterminated meta sequence \(input.errordesc(escapeBuffer))"))
          }
      }
    }


    /*
      CSI sequences terminate when the final byte falls in the 0x40...0x7e range per
      the VT510 manual. Everything before that is parameter bytes that we keep
      buffering.
    */

    func isFinalCSI(_ byte: UInt8) -> Bool {
      byte >= 0x40 && byte <= 0x7e
    }


    /*
      Map a UTF-8 lead byte to the number of continuation bytes we should expect.
      The ranges follow RFC 3629 (the modern UTF-8 restriction that caps sequences at
      4 bytes). Returning nil lets the caller flag illegal encodings early.
    */

    func continuationLength(for byte: UInt8) -> Int? {
      switch byte {
        case 0xc2 ... 0xdf : return 1
        case 0xe0 ... 0xef : return 2
        case 0xf0 ... 0xf4 : return 3
        default            : return nil
      }
    }


    /*
      Simple helper for UTF-8 validation. Continuation bytes always carry the 10xxxxxx
      bit pattern; anything else indicates a broken multibyte scalar.
    */

    func isContinuation(_ byte: UInt8) -> Bool {
      (byte & 0xc0) == 0x80
    }
  }


  //MARK: Public API

  // OK, here we go go.
  // take some bytes from STDIN and basically add contextual wrapping to them
  // we return either a Key, a Response or some ascii or unicode bytes


  public func translate(bytes: Data) -> Result<[TerminalInput.Input], Trace> {

    guard bytes.count > 0 else { return .failure(Trace(self, tag: "zero byte count")) }

    var decoder = Decoder(input: self)

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
