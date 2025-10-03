


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

  public static func anchoredSelectionList ( items: [SelectionListItem], rowOffset: Int = 1, colOffset: Int = 0, row: Int? = nil, col: Int? = nil ) -> MenuAction {
    MenuAction { context, item in

      guard !items.isEmpty else { return }

      // Derive overlay coordinates from the menu item's stored origin so the
      // submenu appears adjacent to its trigger. Offsets keep the overlay a
      // predictable distance away (defaulting to the row beneath the menu bar)
      // and clamping guards against wandering into column or row zero.

      let anchor      = item.anchor
      let anchoredRow = max(1, anchor.row + rowOffset)
      let anchoredCol = max(1, anchor.col + colOffset)

      // Highlight the owning menu entry while its submenu is visible so the
      // user can immediately see which heading spawned the overlay.
      item.setHighlightActive(true)

      // Allow overriding coordinates explicitly so centred or bespoke layouts
      // remain possible while the default anchored offsets stay predictable.
      context.overlays.drawSelectionList(
        items,
        context: context,
        row    : row ?? anchoredRow,
        col    : col ?? anchoredCol,
        onDismiss: {
          // Once the submenu is dismissed restore the original palette so the
          // menu bar returns to its idle state.
          item.setHighlightActive(false)
        }
      )
    }
  }

}


