

import Foundation
import Trace

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
  
  public enum ControlKey {
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
  
  
  public enum CursorKey {
    case left, right, up, down
  }
  
  
  // If the terminal is sending us escape sequences via stdin then it's (probably)
  // in response to something we asked it. This is likely to expand as we build
  // more features
  
  public enum Response {
    case CUROSR (row: Int, column: Int)  // for now just cursor position
  }
  
  
  // our eventual output will be an array of these
  
  public enum Input {
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
        guard let row    = Int(sequence.params[0])  else { return nil } // NB this will crash if params
        guard let column = Int(sequence.params[1])  else { return nil } // aren't there. hmm.
        
        return .CUROSR(row: row, column: column)
      
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
  
  
  // occasionally xterm will stuff multiple control seqs in the pipe, this splits
  // them up and drops the ESC prefixes, leaving us with e,g, [ "[r;cR", ...]

  func split(_ sequence: Data) -> [String]? {
    String(data: sequence, encoding: .utf8)?
        .dropFirst()
        .components(separatedBy: "\u{1b}")
  }

  
  // robust error handling
  
  func errordesc(_ bytes: Data) -> String {
    String(describing: String(data: bytes, encoding: .utf8))
  }
  
  
  // OK, here we go go.
  // take some bytes from STDIN and basically add contextual wrapping to them
  // we return either a Key, a Response or some ascii or unicode bytes
  
  
  public func translate(bytes: Data) -> Result<[TerminalInput.Input], Trace> {
    
    guard bytes.count > 0 else { return .failure(Trace(self, tag: "zero byte count")) }
    
    // single byte is either an alphanum char or an ASCII control char,
    // let's check out the control chars first
    
    if bytes.count == 1 {
      if let key = translate( bytes[0] ) { return .success( [.key   (key)   ] ) }
      else                               { return .success( [.ascii (bytes) ] ) }
    }
    
    
    // ok, we have a multibyte sequence, does it start with an ESC ?
    // if so we'll do a split on it to try and catch any xterm spam we caused
    
    switch bytes[0] {
    
      case 0x1b :
      
        var inputs : [TerminalInput.Input] = []
      
        guard let sequences = split(bytes)
        else {
          return .failure(Trace(self, tag: "borked splitting sequences '\(errordesc(bytes))" ))
        }
        
        
      
        for sequence in sequences {
          
          switch sequence.prefix(1) {
            
            // right now we only care about regular control sequences,
            // if we strt getting device (P) or OS (]) control sequences, we wont know what to
            // do, so we bail.
              
            case "[" :
              
              if let cursor   = translate(sequence) {
                inputs += [ .cursor(cursor) ]
                break
              }
              
              if let response = translate( decompose(sequence) ) { inputs += [.response(response)] }
              else                                               { fallthrough                     }
            
            default : return .failure(Trace(self, tag: "unhandled sequence \(errordesc(bytes))") )
          }
        }
      
        return .success(inputs)
      
      // if we're here we have a multibyte sequence that isnt a control seq, so ...
      default : return .success( [.unicode(bytes)] )
          
    }
    
  }
  
}

