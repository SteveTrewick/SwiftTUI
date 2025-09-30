


import Foundation

public struct AppContext {
  
  var input : TerminalInputController
  var output : OutputController
  
  public init (
    input : TerminalInputController = TerminalInputController(),
    output: OutputController        = OutputController()
  ) {
    self.input  = input
    self.output = output
  }
}

public struct MenuActionContext {
  
  public var app : AppContext
  
  public init (app: AppContext ) {
    self.app = app
  }
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
