
import Foundation

#if canImport(OSLog)
import OSLog
#else
import Glibc
#endif



public class AppContext {

  let input   : TerminalInputController
  let output  : Renderer
  let overlays: OverlayManager
  let style   : ElementStyle
  
  public init ( input: TerminalInputController = TerminalInputController(), output: Renderer = Renderer(), style: ElementStyle, overlays: OverlayManager? = nil ) {
    self.input    = input
    self.output   = output
    self.overlays = overlays ?? OverlayManager()
    self.style    = style
  }
  
  public func log(_ string: String) {
  #if canImport(OSLog)
    os_log(.debug, "%{public}s", "\(string)")
  #else
    fputs(string, stderr)
  #endif
  }
  
}
