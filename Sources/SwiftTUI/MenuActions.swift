


import Foundation

#if canImport(OSLog)
import OSLog
#else
import Glibc
#endif



public struct AppContext {

  var input   : TerminalInputController
  var output  : OutputController
  var overlays: OverlayManager

  public init (
    input : TerminalInputController = TerminalInputController(),
    output: OutputController        = OutputController(),
    overlays: OverlayManager?       = nil
  ) {
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


public struct MenuActionContext {

  // TODO: needs more properties/methods for UI overlay
  public var app : AppContext
  public var overlays: OverlayManager { app.overlays }

  public init (app: AppContext ) {
    self.app = app
  }
}

public typealias MenuActionExecution = (MenuActionContext, MenuItem) -> Void


public struct MenuAction {
  
  public var execute : MenuActionExecution
  
  public static func logMessage ( _ body: String ) -> MenuAction {
    MenuAction { context, item in
      context.app.log("\(item.name): \(body)")
    }
  }

  public static func box (_ element: BoxElement ) -> MenuAction {
    MenuAction { context, item in
      context.overlays.drawBox ( element ) 
    }
  }
  
  public static func messageBox ( _ message: String ) -> MenuAction {
    MenuAction { context, item in
      //TODO: add message box drawing code here
    }
  }

}


