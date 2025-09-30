


import Foundation

#if canImport(OSLog)
import OSLog
#else
import GLibc
#endif



public struct AppContext {
  
  var input  : TerminalInputController
  var output : OutputController
  
  public init (
    input : TerminalInputController = TerminalInputController(),
    output: OutputController        = OutputController()
  ) {
    self.input  = input
    self.output = output
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
  
  public init (app: AppContext ) {
    self.app = app
  }
}

public typealias MenuActionExecution = (MenuActionContext, MenuItem) -> Void


public struct MenuAction {
  
  public var execute : MenuActionExecution
  
  public static func logMessage ( _ body: String) -> MenuAction {
    MenuAction { context, item in
      context.app.log("\(item.name): \(body)")
    }
  }
  
}


