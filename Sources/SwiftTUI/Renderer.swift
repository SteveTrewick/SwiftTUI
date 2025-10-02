
import Foundation

public struct Renderer {

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
  
}
