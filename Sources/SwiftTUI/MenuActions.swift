


import Foundation

public struct MenuActionContext {
  public init() {}
}

public typealias MenuActionExecution = (MenuActionContext, MenuItem) -> Void

public struct MenuAction {
  
  var context : MenuActionContext
  var action  : MenuActionExecution
  
  public init (context: MenuActionContext, action: @escaping MenuActionExecution ) {
    self.context = context
    self.action  = action
  }
  
  // we may want to return a value here, lets here how it goes
  func execute( _ item: MenuItem) {
      action(context, item)
  }
  
}
