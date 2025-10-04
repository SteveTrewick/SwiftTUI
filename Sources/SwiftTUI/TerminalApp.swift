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


  private var awaitingMenuSelection: Bool
  private let keyHandler            : KeyHandler
  
  public init ( menuBar: MenuBar, statusBar: StatusBar, context: AppContext, window: WindowChanges = WindowChanges() )
  {
    self.cursor                 = Cursor(row: 0, col: 0)
    self.window                 = window
    self.context                = context
    self.statusBar              = statusBar
    self.menuBar                = menuBar
    self.awaitingMenuSelection  = false
    self.keyHandler             = KeyHandler()

    
    
    // TODO: this is sematically unpleaseant and in the wrong place, we need a new strategy for change tracking and rendering, these probably belong in Renderer
    // Overlay changes either trigger a light overlay repaint or a DECERA pass when they disappear.
    self.context.overlays.onChange = { [weak self] change in
      // Overlay updates can now specify whether the surrounding chrome actually
      // changed, letting anchored menus avoid redundant redraws during navigation.
      switch change {
        case .updated ( let needsBaseRedraw ) :
          self?.render ( clearMode: .none, rendersBase: needsBaseRedraw )
        case .cleared                     :
          self?.render ( clearMode: .overlayDismissal )
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

    configureKeyHandler()

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

    // The shared key handler swallows menu shortcuts and terminal responses so
    // callers only need to register the interactions they care about.
    for input in inputs {
      _ = keyHandler.handle ( input )
    }

  }
  
  // we probably nned to track the cursor position don't we?
  func process ( _ response: TerminalInput.Response ) {
    switch response {
      case .CURSOR(let row, let col): cursor = Cursor(row: row, col: col)
                                      //log( String(describing: cursor) )
    }
  }
  
  
  // we will need to track which things we change and why and whether that requires
  // us to redraw the whole lot, or just parts.
  // for now, just do this.
  
  
  func render ( clearMode: Renderer.ClearMode = .full, rendersBase: Bool = true ) {

    let baseElements: [Renderable]

    if rendersBase {
      baseElements = [ menuBar, updateStatusBar(for: window.size) ]
    } else {
      // Anchored selection overlays only nudge the submenu highlight, so skipping
      // the base repaint avoids redundant menu redraws while the overlay is live.
      baseElements = []
    }

    context.output.renderFrame (
      base              : baseElements,
      overlay           : context.overlays.activeOverlays(),
      in                : window.size,
      defaultStyle      : context.style,
      clearMode         : clearMode,
      onFullClear       : (clearMode == .full) ? { [context] in context.overlays.invalidateActiveOverlays() } : nil,
      overlayClearBounds: (clearMode == .overlayDismissal) ? context.overlays.consumeClearedOverlayBounds() : []
    )

  }

  
  private func updateStatusBar(for size: winsize) -> Renderable {

    let columns     = Int(size.ws_col)
    let rows        = Int(size.ws_row)
    statusBar.text  = "Window size: \(columns) x \(rows)"

    return statusBar
  }



  private func configureKeyHandler() {
    // Keep the table definition close to the registration so the dispatch logic
    // mirrors the template provided by the user.  Everything the menu cares
    // about is wrapped into a single entry so we can push/pop in one call.

    let controlHandlers : KeyHandler.ControlInputHandler = [
      .key ( .ESC ) : { [weak self] in
        self?.awaitingMenuSelection = true
        return true
      }
    ]

    let bytesHandler    : KeyHandler.BytesInputHandler = { [weak self] bytes in
      guard let app = self else { return false }

      switch bytes {
        case .ascii   ( let data ),
             .unicode ( let data ) :
          return app.handleMenuSelectionPayload ( data )
      }
    }

    let responseHandler : KeyHandler.ResponseInputHandler = { [weak self] response in
      guard let app = self else { return false }

      guard case .CURSOR = response else { return false }

      // The dispatcher no longer performs wildcard dictionary matching, so this
      // closure inspects the payload and decides whether it wants to swallow the
      // response.  Feeding the concrete response back through process keeps the
      // cursor tracking logic unchanged.
      app.process ( response )
      return true
    }

    keyHandler.pushHandler ( KeyHandler.HandlerTableEntry (
      control   : controlHandlers,
      bytes     : bytesHandler,
      responses : responseHandler
    ) )
  }

  @discardableResult
  private func handleMenuSelectionPayload ( _ data: Data ) -> Bool {

    guard awaitingMenuSelection else { return false }
    awaitingMenuSelection = false

    guard let char = String ( data: data, encoding: .utf8 )?.first else { return false }

    menuBar.locateMenuItem ( select: char )?.performAction()
    return true
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
