
import Foundation

public class Renderer {

  public enum ClearMode {
    case none
    case full
    case overlayDismissal
  }

  weak var context: AppContext?
  
  public init ( context: AppContext? = nil ) {
    self.context = context
  }

  
  // we begin to repeat ourselves, and even though "uncle" bob can GFH
  // we should still extract this. And tbqhwyf the following are all kinda repeaty too.
  func send ( _ seq: AnsiSequence ) {
    
    print  ( seq.description, terminator: "")
    fflush ( stdout )
    
    usleep(700)  // without ths, big problems
                  // seems terminal can't keep up with us
                  // originally, adding the logging prevented bad output pointing to a timing issue

  }
  
  
  // use to send ANSI sequences to e.g get responses
  // these sequences do not durectly update the screem, so we do not track the cursor
  public func send (_ ansi: AnsiSequence... ) {
    // and what did we learn from below? if we are sending loads of these
    // we get crap behaviour
    DispatchQueue.main.async { [self] in
      for seq in ansi {
        send(seq)
      }
    }
    
  }
  
  
  // use to send text that should be displayed, to incude ANSI sequences.
  // this one tracks the cursor position
  
  public func display (_ ansi: AnsiSequence... ) {
    DispatchQueue.main.async { [self] in
      for seq in ansi {
        send(seq)
      }
       send( .cursorPosition )
    }
  }
  
  
  
  // same but for an array of ANSI sequences
  public func render (_ ansi: [AnsiSequence]?, tracking: Bool = true ) {

    guard let ansi = ansi else { return }
    
    DispatchQueue.main.async { [self] in
      for seq in ansi {
        send(seq)
      }
      if tracking { send( .cursorPosition ) }
    }
  }



  // draw a collection of Renderable elements
  public func render ( elements: [Renderable], in size: winsize, tracking: Bool = true ) {
    
    DispatchQueue.main.async { [self] in
      
      for element in elements {
        if let ansi = element.render(in: size) {
          for seq in ansi {
              send(seq)
          }
          if tracking { print ( AnsiSequence.cursorPosition.description, terminator: "" ) }
        }
      }
    }
  
  }

  
  public func clear ( rectangle: BoxBounds ) {

    guard rectangle.width  > 0 else { return }
    guard rectangle.height > 0 else { return }

    let top       = rectangle.row
    let left      = rectangle.col
    let width     = rectangle.width
    let height    = rectangle.height
    let bottom    = top + height - 1
    let blankLine = AnsiSequence.repeatChars(" ", count: width)

    // Save and restore the cursor so the caller's active draw position is untouched while
    // we manually scrub each row with the classic CSI erase primitives.
    var sequences : [AnsiSequence] = [ .saveCursor ]

    for row in top...bottom {
      sequences += [
        .moveCursor(row: row, col: left),
        blankLine
      ]
    }

    sequences.append ( .restoreCursor )

    render ( sequences )
  }
  
  
  public func renderFrame ( base: [Renderable], overlay: [Renderable], in size: winsize, defaultStyle: ElementStyle, clearMode: ClearMode, onFullClear: (() -> Void)? ) {

    // Always restore the default palette before beginning a frame so any element specific colours do not leak
    send (
      .forecolor(defaultStyle.foreground),
      .backcolor(defaultStyle.background)
    )

    
    switch clearMode {
      
    case .none: break

      case .full:
        // A resize or explicit full clear demands a terminal reset so the chrome can be redrawn.
        send ( .cls )

        if !base.isEmpty {
          render (
            elements: base,
            in      : size
          )
        }

        onFullClear?()

      case .overlayDismissal:
        // Overlays render between the menu and status rows. When they disappear we punch a DECERA window
        // through that region so we do not disturb the chrome framing the workspace.
        let rows    = Int ( size.ws_row )
        let columns = Int ( size.ws_col )
        let height  = rows - 2

        if columns > 0 && height > 0 {
          clear (
            rectangle: BoxBounds (
              row    : 2,
              col    : 1,
              width  : columns,
              height : height
            )
          )
        }
    }

    if !overlay.isEmpty {
      // Overlays always render after the base content so that they appear above it
      render (
        elements: overlay,
        in      : size
      )
    }

    // Reinstate the palette so subsequent prints outside the renderer stay consistent
    send (
      .forecolor ( defaultStyle.foreground ),
      .backcolor ( defaultStyle.background )
    )
  }
}
