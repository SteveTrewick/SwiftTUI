


import Foundation

#if canImport(OSLog)
import OSLog
#else
import Glibc
#endif



public struct AppContext {

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


public typealias MenuActionExecution = (AppContext, MenuItem) -> Void


public struct MenuAction {
  
  public var execute : MenuActionExecution

  public static func logMessage ( _ body: String ) -> MenuAction {
    MenuAction { context, item in
      context.log("\(item.name): \(body)")
    }
  }

  public static func box (_ element: BoxElement ) -> MenuAction {
    MenuAction { context, item in
      context.overlays.drawBox ( element )
    }
  }
  
  public static func messageBox ( _ message: String, buttonText: String = "OK", activationKey: TerminalInput.ControlKey = .RETURN, buttons: [MessageBoxButton] = [] ) -> MenuAction {
    MenuAction { context, _ in
      context.overlays.drawMessageBox(
        message,
        buttonText   : buttonText,
        activationKey: activationKey,
        buttons      : buttons
      )
    }
  }
  
  public static func selectionList ( items: [SelectionListItem] ) -> MenuAction {
    MenuAction { context, _ in
      context.overlays.drawSelectionList(items)
    }
  }

}


