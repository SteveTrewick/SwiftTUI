


import Foundation



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
        context      : context,
        buttonText   : buttonText,
        activationKey: activationKey,
        buttons      : buttons
      )
    }
  }

  public static func selectionList ( items: [SelectionListItem] ) -> MenuAction {
    MenuAction { context, _ in
      context.overlays.drawSelectionList(
        items,
        context: context
      )
    }
  }

}


