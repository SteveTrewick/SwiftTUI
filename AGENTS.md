
RULES:
  No swift 6, no async/await
  Use Swift 5
  Conditional bindings especially look like this :
    if let path = path else {}
    guard let path = path else { return }
  macos 11 native
  always use swift-tools-version:5.5
  you may stub out parts if needed to enable linux compilation for testing but do not break compatibility
                              
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
    

                              

