
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
    let bottom    = rectangle.row + rectangle.height - 1
    
    // Save and restore the cursor so the caller's active draw position is untouched 
    var sequences : [AnsiSequence] = [ .saveCursor ]

    for row in top...bottom {
      sequences += [
        .moveCursor  (row: row, col  : rectangle.col  ),
        .repeatChars (" ",      count: rectangle.width)
      ]
    }

    sequences.append ( .restoreCursor )

    render ( sequences )
  }
  
  
  public func renderFrame ( base: [Renderable], overlay: [Renderable], in size: winsize, defaultStyle: ElementStyle, clearMode: ClearMode, onFullClear: (() -> Void)?, overlayClearBounds: [BoxBounds] = [] ) {

    // Always restore the default palette before beginning a frame so any element specific colours do not leak
    send (
      .forecolor ( defaultStyle.foreground ),
      .backcolor ( defaultStyle.background )
    )

    
    var hasRenderedBase = false

    func handleFullClear () {

      // so annoyingly, it turns out that we can't actually just use cls for this as it just resets
      // the terminal's defaults. arse
      // send ( .cls )

      clear ( rectangle: BoxBounds ( row: 1, col: 1, width: Int ( size.ws_col ), height: Int ( size.ws_row ) ) )

      if !base.isEmpty {
        // we track the base rendering so later logic knows not to double-draw the same elements
        // during a full clear cycle. skipping the second render prevents pointless redraw work.
        hasRenderedBase = true
        render (
          elements: base,
          in      : size
        )
      }

      onFullClear?()
    }

    
    
    func handleOverlayDismissal () {
      
      if !overlayClearBounds.isEmpty { overlayClearBounds.forEach { clear ( rectangle: $0 ) } }
      else
      {
        // Fall back to the legacy blanket clear if no overlays reported a visible region.
        let columns = Int ( size.ws_col )
        let height  = Int ( size.ws_row ) - 2

        if columns > 0 && height > 0 {
          var sequences: [AnsiSequence] = [ .saveCursor ]

          for offset in 0..<height {
            let row = 2 + offset
            // Use the terminal's native clear so dismissal cannot leave artifacts in
            // rows that previously held overlay content.
            sequences += [
              .moveCursor(row: row, col: 1),
              .killLine
            ]
          }

          sequences.append ( .restoreCursor )
          render ( sequences )
        }

      }
    
    }

    switch clearMode {

      case .none              : break
      case .full              : handleFullClear()
      case .overlayDismissal  : handleOverlayDismissal()
    }

    if !base.isEmpty && !hasRenderedBase {
      // render the base when we did not go through the full clear path so overlays keep their
      // expected stacking order.
      render (
        elements: base,
        in      : size
      )
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
