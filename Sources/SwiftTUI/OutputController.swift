
import Foundation

public struct OutputController {

  public init() {}

  // use to send ANSI sequences to e.g get responses

  public func send(_ ansi: AnsiSequence...) {
    DispatchQueue.main.async {
      print ( ansi.map { $0.description }.joined(separator: ""), terminator: "" )
    }
  }
  
  
  // use to send text that should be displayed, to incude ANSI sequences.
  // this one tracks the cursor position
  
  public func display(_ ansi: AnsiSequence...) {
    DispatchQueue.main.async { [self] in
      print( ansi.map { $0.description }.joined(separator: ""), terminator: "" )
      send( .cursorPosition )
    }
  }
}
