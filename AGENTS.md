  Follow the coding style rules as laid out below, they are marked with //STYLERULE: and there are examples of correct style below them
 
  ```swift
      //STYLERULE: ignore 80 character limit, you may write lines as long as necessary, monitors are large
      public struct MessageBoxButton {
      
      //STYLERULE: variable declarations aligned like this, the colons all align, they are one space after the longest variable name
      public let text          : String
      public let activationKey : TerminalInput.ControlKey
      public let handler       : (() -> Void)?

      // STYLERULE: Never split init params, init and function parameters all on one line regardless of length
      public init ( text: String, activationKey: TerminalInput.ControlKey = .RETURN, handler: (() -> Void)? = nil ) {
        self.text          = text
        self.activationKey = activationKey
        self.handler       = handler
      }
      
      //
    }
  //STYLERULE : when initialising types or calling functions with long parameter lists, split over multiplt lines, align the colons with the longest parameter name, no space
        return Button (
        bounds             : BoxBounds(row: row ?? 1, col: col ?? 1, width: config.text.count + 4, height: 1),
        text               : config.text,
        style              : style,
        activationKey      : config.activationKey,
        onActivate         : { action?(); onDismiss() },
        highlightForeground: highlightPalette.foreground,
        highlightBackground: highlightPalette.background,
        usesDimHighlight   : true,
        isHighlightActive  : index == 0
      )
      
  //STYLERULE: function parameters, space after the name and after the list, like this
    func render ( in size: winsize ) -> [AnsiSequence]? { ... }
    
  //STYLERULE: multiple assignments, alineed with the = of the longest variable like this
      guard let layout    = messageBox.layout(in: size) else { return nil }
      guard var sequences = messageBox.render(in: size) else { return nil }
      
  //STYLERULE: switch statements, where the code is a single statement, place it after the case, like this, align colons with the longest case with a space either side
    switch key {
      case .left  : activeIndex = max(0, activeIndex - 1)
      case .right : activeIndex = min(buttons.count - 1, activeIndex + 1)
      default     : break
    }
    
  //STYLERULE: assignment aligment, again
      let text          = ""
      let activationKey = TerminalInput
      let handler       = (() -> Void)?
  ```
RULES:
  No swift 6, no async/await.
  Use Swift 5 compatible syntax at all times
  Conditional bindings especially look like this :
    if let path = path else {}
    guard let path = path else { return }

  always use swift-tools-version:5.5.
  Never, ever, commit Package.resolved. Always honour .gitignore.
  the user prefers terse code, try not to be chatty.
  when adding new code add some comments, particulalrly explaining why you have selected a particular implmentaton patter, the user finds some of your architectural choices confusing.
  try to build new features in a similar style as the existing codebase where this is posible, explain if you are unable to do this becuse of the structure
  the default background color is black, it is never, ever blue
  long lines are OK, especially init functions, user has a big screen and likes long init lines
  comments may be verbose                



CONTEXT:
    we are building terminal code for xterm on macos, xterm uses extensive inband signalling
    using ANSI escape codes, you will need to take macos xterm quirks into account
    

    
    

    

                              

