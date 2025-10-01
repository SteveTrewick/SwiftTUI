
RULES:
  No swift 6, no async/await.
  Use Swift 5.
  Conditional bindings especially look like this :
    if let path = path else {}
    guard let path = path else { return }
  macos 11 native.
  always use swift-tools-version:5.5.
  Never, ever, commit Package.resolved. Always honour .gitignore.
  you may stub out parts if needed to enable linux compilation for testing but do not break compatibility.
  the user prefers terse code, try not to be chatty.
  when adding new code add some comments, particulalrly explaining why you have selected a particular implmentaton patter, the user finds some of your architectural choices confusing.
  try to build new featires in a similar style as the existing codebase where this is posible, explain if you are unable to do this becuse of the structure
  the default background color is black, .bgBlack, it is never, ever blue
  long lines are OK, especially init functions, user has a big screen and likes long init lines
  comments may be verbose                

CODING STYLE :
  Please read and follow the coding style rules in STYLERULES.md



CONTEXT:
    we are building terminal code for xterm on macos, xterm uses extensive inband signalling
    using ANSI escape codes, you will need to take macos xterm quirks into account
    
Existing Code :

    ANSI.swift: contains definitions of ANSI escape codes
    Box.swift : shows how to use these as a DSL to construct a box
    TerminalInput.swift: shows how the input from the xterm stream is handled and parsed
    TerminalInputController.swift : sets up the posix input source and stream and hands bytes to TerminalInput
    ViewBuffer.swift : defines a scrollable text buffer
    OutputController.swift : defines methods to send and display ANSI sequences
    
Packages:
    Included in the package dependencies is SerialPort, if you are asked to write any serial code
    later, use this API
    

                              

