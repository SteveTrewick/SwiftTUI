
import Foundation


/*
  there is, of course, a much nicer and more formally correct way to do this
  based on a deep grok of the ANSI spec but life is short and I am easily bored.
 
  we will use this to build up a pseudo DSL for sending stuff to the terminal
  if you write a straight print statement in your sibclass, you will died!! DANGER!
 
  mmkay?
*/


public enum ANSIForecolor : String  {
  case black     = "\u{001B}[38;5;0m"
  case red       = "\u{001B}[38;5;1m"
  case green     = "\u{001B}[38;5;2m"
  case yellow    = "\u{001B}[38;5;3m"
  case blue      = "\u{001B}[38;5;4m"
  case magenta   = "\u{001B}[38;5;5m"
  case cyan      = "\u{001B}[38;5;6m"
  case white     = "\u{001B}[38;5;7m"
}

public enum ANSIBackcolor : String {
  case bgBlack   = "\u{001B}[48;5;0m"
  case bgRed     = "\u{001B}[48;5;1m"
  case bgGreen   = "\u{001B}[48;5;2m"
  case bgYellow  = "\u{001B}[48;5;3m"
  case bgBlue    = "\u{001B}[48;5;4m"
  case bgMagenta = "\u{001B}[48;5;5m"
  case bgCyan    = "\u{001B}[48;5;6m"
  case bgWhite   = "\u{001B}[48;5;7m"
  case bgGrey    = "\u{001B}[48;5;8m"
}

public enum ANSIAttribute : String {
  case bold      = "\u{001B}[1m"
  case underline = "\u{001B}[4m"
  case dim       = "\u{001B}[2m"

  public var offSequence: String {
    switch self {
      case .bold      : return "\u{001B}[22m"
      case .underline : return "\u{001B}[24m"
      case .dim       : return "\u{001B}[22m"
    }
  }
}


public enum UnicodeBox {
  case horiz(Int)  // horizontal line
  case vert        // vertical
  case tlc         // top left corner
  case blc         // bottom left corner
  case trc         // top right corner
  case brc         // bottom right corner
}


// add more as necessary, we also need a custom color type
// because thats not enough colors.

public enum AnsiSequence : CustomStringConvertible {
  
  
  case cls
  case killLine
  
  case forecolor(ANSIForecolor)
  case backcolor(ANSIBackcolor)
  case rgb      (r: Int, g: Int, b: Int)
  case rgb_bg   (r: Int, g: Int, b: Int)
  case resetcolor

  case bold(String)
  case underline(String)
  case dim(String)

  case text(String)


  case moveCursor (row:  Int, col:  Int)
  case hideCursor
  case showCursor
  case cursorPosition
  
  
  case setTermSize(rows: Int, cols: Int)
  
  case setScroll(top: Int, bot: Int)
  
  case clearScrollBack
  
  case altBuffer
  case normBuffer
  
  
  // now box drawing sub DSL
  case box         (UnicodeBox)
  case repeatRow   (col: Int, row : Int, count: Int, [AnsiSequence])
  case repeatChars (String, count: Int)
  case flatten     ([AnsiSequence])
  
  
  public var description: String {
    
    switch self {
      
      case .flatten(let seqs)    : return seqs.map { $0.description }.joined()
      
      case .box(let unibox) :
        switch unibox {
          case .tlc               : return "\u{250c}"  // ┌ we could actually just use unicode literals
          case .trc               : return "\u{2510}"
          case .blc               : return "\u{2514}"
          case .brc               : return "\u{2518}"
          case .vert              : return "\u{2502}"
          case .horiz (let count) : return String(repeating: "\u{2500}", count: count)
        }
      
      case .repeatChars(let chars, let count): return String(repeating: chars, count: count)
      
      case .repeatRow(let col, let row, let count, let seqs) :
        var aseqs : [AnsiSequence] = []
        for i in 0..<count {
            aseqs += [
              .moveCursor(row: row + i, col: col),
            ] + seqs
        }
        return aseqs.map { $0.description }.joined()
      
      case .forecolor(let color)         : return color.rawValue
      case .backcolor(let color)         : return color.rawValue
      case .rgb   (let r, let g,  let b) : return "\u{001B}[38;2;\(r);\(g);\(b)m"
      case .rgb_bg(let r, let g,  let b) : return "\u{001B}[48;2;\(r);\(g);\(b)m"
      case .resetcolor                   : return "\u{001B}[0m"

      case .bold      (let text) : return ANSIAttribute.bold.rawValue + text + ANSIAttribute.bold.offSequence
      case .underline (let text) : return ANSIAttribute.underline.rawValue + text + ANSIAttribute.underline.offSequence
      case .dim       (let text) : return ANSIAttribute.dim.rawValue + text + ANSIAttribute.dim.offSequence

      case .text      (let text) : return text

      case .moveCursor (let row,  let col ): return "\u{001B}[\(row);\(col)H"
      case .hideCursor                     : return "\u{001B}[?25l"
      case .showCursor                     : return "\u{001B}[?25h"
      case .cursorPosition                 : return "\u{001B}[6n"
      
      case .cls                            : return "\u{001B}[2J"
      case .killLine                       : return "\u{01b}[0K"
      case .clearScrollBack                : return "\u{001B}[3J"
      case .setScroll  (let top,  let bot ): return "\u{001B}[\(top);\(bot)r"
      case .altBuffer                      : return "\u{001B}[?1049h"
      case .normBuffer                     : return "\u{001B}[?1049l"
      case .setTermSize(let rows, let cols): return "\u{001B}[8;\(rows);\(cols)t"
      
    }
  }
  
  
}
