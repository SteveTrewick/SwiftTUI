
import Foundation

public struct Renderer {

  public enum ClearMode {
    case none
    case full
    case overlayDismissal
  }

  public init() {}

  // use to send ANSI sequences to e.g get responses
  // these sequences do not durectly update the screem, so we do not track the cursor
  public func send(_ ansi: AnsiSequence...) {
    DispatchQueue.main.async {
      print ( ansi.map { $0.description }.joined(separator: ""), terminator: "" )
    }
  }
  
  
  // use to send text that should be displayed, to incude ANSI sequences.
  // this one tracks the cursor position
  
  public func display (_ ansi: AnsiSequence...) {
    DispatchQueue.main.async { [self] in
      print( ansi.map { $0.description }.joined(separator: ""), terminator: "" )
      send( .cursorPosition )
    }
  }
  
  // same but for an array of ANSI sequences
  public func display (_ ansi: [AnsiSequence]?) {

    guard let ansi = ansi else { return }

    DispatchQueue.main.async { [self] in
      print( ansi.map { $0.description }.joined(separator: ""), terminator: "" )
      send( .cursorPosition )
    }
  }


  // Clearing a rectangular area allows overlays to refresh portions of the screen without a full CLS.
  // Xterm supports DECERA which erases the supplied rectangle, replacing all cells with blanks.
  public func clear ( rectangle: BoxBounds ) {

    guard rectangle.width  > 0 else { return }
    guard rectangle.height > 0 else { return }

    let top    = rectangle.row
    let left   = rectangle.col
    let bottom = rectangle.row + rectangle.height - 1
    let right  = rectangle.col + rectangle.width  - 1

    send (
      .eraseRectangularArea(
        top   : top,
        left  : left,
        bottom: bottom,
        right : right
      )
    )
  }


  // draw a collection of Renderable elements
  public func render ( elements: [Renderable], in size: winsize  ) {
    
    // we need some way to determine which ones though
    // since we only want to redraw as much of the screen as we need
    
    DispatchQueue.main.async {
      for element in elements {
        
        if let ansi = element.render(in: size) {
          for seq in ansi {

            print  ( seq.description, terminator: "")
            fflush ( stdout )
            
            usleep(700)  // without ths, big problems
                          // seems terminal can't keep up with us
                          // originally, adding the logging prevented bad output pointing to a timing issue
          }
          
          print ( AnsiSequence.cursorPosition.description, terminator: "" )
        }


      }
    }
  }

  public func renderFrame ( base: [Renderable], overlay: [Renderable], in size: winsize, defaultStyle: ElementStyle, clearMode: ClearMode, onFullClear: (() -> Void)? ) {

    // Always restore the default palette before beginning a frame so any element specific colours do not leak
    send (
      .forecolor(defaultStyle.foreground),
      .backcolor(defaultStyle.background)
    )

    switch clearMode {
      case .none:
        break

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
        let rows    = Int(size.ws_row)
        let columns = Int(size.ws_col)
        let height  = rows - 2

        if columns > 0 && height > 0 {
          clear (
            rectangle: BoxBounds(
              row   : 2,
              col   : 1,
              width : columns,
              height: height
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
      .forecolor(defaultStyle.foreground),
      .backcolor(defaultStyle.background)
    )
  }
}
