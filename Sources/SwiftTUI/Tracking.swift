import Foundation

public final class TerminalApp {

  private let window    : WindowChanges
  private let statusBar : StatusBar
  private let output    : OutputController
  private let input     : TerminalInputController
  
  
  public init (
    window: WindowChanges           = WindowChanges(),
    output: OutputController        = OutputController(),
    input : TerminalInputController = TerminalInputController()
  )
  {
    self.window    = window
    self.output    = output
    self.input     = input
    self.statusBar = StatusBar( text: "", output: output )
    
    // hook the window change handler, if the window size changes, we need to redraw
    // basically everything
    self.window.onChange = { [self] size in
      self.render (everything: true)
    }
    
    // capture all input
    input.makeRaw()
    
    // clear and initialise the screen
    output.send (
      .altBuffer,
      .clearScrollBack,
      .cls,
      .moveCursor(row: 1, col: 1)
    )
    
  }

  
  // we need to track which things we change and why and whether that requires
  // us to redraw the whole lot, or just parts.
  // for now, just do this.
  
  
  func render ( everything: Bool = true ) {
    
    if everything {
      
      output.send(
        .cls
      )
      
      output.render (
        elements: [ updateStatusBar (for: window.size) ],
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
