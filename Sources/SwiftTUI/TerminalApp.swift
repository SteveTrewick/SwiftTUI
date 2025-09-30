import Foundation


/*
  this is a rough draft of what a termonal app container would look like.
  we hook our inputs from stdin and any window change events
  and we render our UI elements, much work to be done
 
*/
public final class TerminalApp {

  struct Cursor {
    var row : Int
    var col : Int
  }
  
  private let window    : WindowChanges
  private let statusBar : StatusBar
  private let menuBar   : MenuBar
  private let output    : OutputController
  private let input     : TerminalInputController
  private let overlays  : OverlayManager
  private var cursor    : Cursor
  
  private var awaitingMenuSelection: Bool
  
  public init (
    
    menu   : MenuBar,
    context: AppContext,
    window : WindowChanges = WindowChanges()
  )
  {
    self.cursor                  = Cursor(row: 0, col: 0)
    self.window                  = window
    self.output                  = context.output
    self.input                   = context.input
    self.overlays                = context.overlays
    self.statusBar               = StatusBar( text: "", output: output )
    self.menuBar                 = menu
    self.awaitingMenuSelection  = false

    self.overlays.onChange = { [weak self] in
      self?.render(everything: true)
    }
    
    
    // hook the window change handler, if the window size changes, we need to redraw
    // basically everything
    self.window.onChange = { [self] size in
      self.render (everything: true)
    }
    
    // hook stdin input (keyboard input and xterm messages)
    self.input.handler = { [self] input in
      switch input {
        case .failure(let trace) : log ( String(describing: trace) )
        case .success(let input) : process( input )
      }
    }
    
    // redirect stderr to null so we dont spam log/error messages to the terminal
    freopen("/dev/null", "w", stderr)
    
    // capture all input
    input.makeRaw()
    

    // clear and initialise the screen
    output.send (
      .altBuffer,
      .clearScrollBack,
      .cls,
      .moveCursor(row: 1, col: 1)
    )
    
    // start input handler
    input.stream.resume()
  }

  
  
  
  // process stdin
  func process (_ inputs: [TerminalInput.Input] ) {
    
    // Catch option-key menu shortcuts (sent as ESC-prefixed characters) and
    // trigger the corresponding menu item action.
    
    for input in inputs {
      switch input {

        case .key      ( let key      ) : awaitingMenuSelection = (key == .ESC)
        case .ascii    ( let data     ) : handleMenuSelectionPayload(data)
        case .unicode  ( let data     ) : handleMenuSelectionPayload(data)
        case .response ( let response ) : process ( response )

        default : break
      }
    }

    awaitingMenuSelection = false
  }
  
  // we probably nned to track the cursor position don't we?
  func process ( _ response: TerminalInput.Response ) {
    switch response {
      case .CUROSR(let row, let col): cursor = Cursor(row: row, col: col)
    }
  }
  
  
  // we will need to track which things we change and why and whether that requires
  // us to redraw the whole lot, or just parts.
  // for now, just do this.
  
  
  func render ( everything: Bool = true ) {
    
    if everything {
      
      output.send(
        .cls
      )
      
      let baseElements: [Renderable] = [
        menuBar,
        updateStatusBar(for: window.size)
      ]

      let overlayElements = overlays.activeOverlays()

      output.render (
        elements: baseElements + overlayElements,
        in      : window.size
      )
    
    }
  }
  
  
  private func updateStatusBar(for size: winsize) -> Renderable {

    let columns     = Int(size.ws_col)
    let rows        = Int(size.ws_row)
    statusBar.text  = "Window size: \(columns) x \(rows)"

    return statusBar
  }



  private func handleMenuSelectionPayload(_ data: Data) {
    
    guard awaitingMenuSelection else { return }
    awaitingMenuSelection = false
    
    if let char = String(data: data, encoding: .utf8)?.first {
      menuBar.locateMenuItem(select: char)?.performAction()
    }
    
  }


  
  
  public func start() {
    render ( everything: true )
    window.track()
  }

  
  public func stop() {
    window.untrack()
  }
  
  deinit {
    window.untrack()
  }
}
