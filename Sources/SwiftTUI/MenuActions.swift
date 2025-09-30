


import Foundation

struct MenuActionContext {
  
}

struct MenuAction {
  
  var context : MenuActionContext
  var action  : ((MenuActionContext) -> Void)? = nil
  
  // we may want to return a value here, lets here how it goes
  func execute() {
      action?(context)
  }
  
}
