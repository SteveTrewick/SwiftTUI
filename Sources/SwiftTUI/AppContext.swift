
import Foundation

#if canImport(OSLog)
import OSLog
#else
import Glibc
#endif



public class AppContext {

  var input   : TerminalInputController
  var output  : Renderer
  var overlays: OverlayManager

  public init ( input: TerminalInputController = TerminalInputController(), output: Renderer = Renderer(), overlays: OverlayManager? = nil ) {
    self.input    = input
    self.output   = output
    self.overlays = overlays ?? OverlayManager()
  }
  
  public func log(_ string: String) {
  #if canImport(OSLog)
    os_log(.debug, "%{public}s", "\(string)")
  #else
    fputs(string, stderr)
  #endif
  }
  
}
