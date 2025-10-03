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
  
  private let window       : WindowChanges
  private let statusBar    : StatusBar
  private let menuBar      : MenuBar
  private let context      : AppContext
  private var cursor       : Cursor
  private var defaultStyle : ElementStyle
  
  private var awaitingMenuSelection: Bool
  
  public init ( menuBar: MenuBar, statusBar: StatusBar, context: AppContext, defaultStyle: ElementStyle, window: WindowChanges = WindowChanges() )
  {
    self.cursor                 = Cursor(row: 0, col: 0)
    self.window                 = window
    self.defaultStyle           = defaultStyle
    self.context                = context
    self.statusBar              = statusBar
    self.menuBar                = menuBar
    self.awaitingMenuSelection  = false

    
    
    // TODO: this is sematically unpleaseant and in the wrong place, we need a new strategy for change tracking and rendering, these probably belong in Renderer
    // Overlay changes either trigger a light overlay repaint or a DECERA pass when they disappear.
    self.context.overlays.onChange = { [weak self] change in
      switch change {
        case .updated : self?.render(clearMode: .none)
        case .cleared : self?.render(clearMode: .overlayDismissal)
      }
    }
    
    
    // hook the window change handler, if the window size changes, we need to redraw
    // basically everything
    self.window.onChange = { [self] size in
      self.render (clearMode: .full)
    }
    
    // hook stdin input (keyboard input and xterm messages)
    self.context.input.handler = { [self] input in
      switch input {
        case .failure(let trace) : log ( String(describing: trace) )
        case .success(let input) : process( input )
      }
    }
    
    // redirect stderr to null so we dont spam log/error messages to the terminal
    freopen("/dev/null", "w", stderr)
    
    // capture all input
    self.context.input.makeRaw()
    

    // clear and initialise the screen
    self.context.output.send (
      .altBuffer,
      .clearScrollBack,
      .cls,
      .moveCursor(row: 1, col: 1)
    )
    
    // start input handler
    self.context.input.stream.resume()
  }

  
  
  
  // process stdin
  func process (_ inputs: [TerminalInput.Input] ) {

    defer { awaitingMenuSelection = false }

    if context.overlays.handle(inputs: inputs) {
      return
    }

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

  }
  
  // we probably nned to track the cursor position don't we?
  func process ( _ response: TerminalInput.Response ) {
    switch response {
      case .CUROSR(let row, let col): cursor = Cursor(row: row, col: col)
                                      //log( String(describing: cursor) )
    }
  }
  
  
  // we will need to track which things we change and why and whether that requires
  // us to redraw the whole lot, or just parts.
  // for now, just do this.
  
  
  func render ( clearMode: Renderer.ClearMode = .full ) {

    let size             = window.size
    let statusElement    = updateStatusBar(for: size)
    let baseElements     : [Renderable] = [ menuBar, statusElement ]
    let overlayElements  = context.overlays.activeOverlays()
    let invalidation     : (() -> Void)? = (clearMode == .full) ? { [context] in context.overlays.invalidateActiveOverlays() } : nil

    // Capture the cleared overlay bounds so the renderer can target its scrub pass.
    let overlayClearBounds = (clearMode == .overlayDismissal) ? context.overlays.consumeClearedOverlayBounds() : []

    context.output.renderFrame (
      base              : baseElements,
      overlay           : overlayElements,
      in                : size,
      defaultStyle      : defaultStyle,
      clearMode         : clearMode,
      onFullClear       : invalidation,
      overlayClearBounds: overlayClearBounds
    )

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
    render ( clearMode: .full )
    window.track()
  }

  
  public func stop() {
    window.untrack()
  }
  
  deinit {
    window.untrack()
  }
}
