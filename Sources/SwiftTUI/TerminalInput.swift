/*
  TerminalInput is now a direct alias of TerminalInputController. Existing call
  sites that still refer to TerminalInput.Input or ControlKey will continue to
  compile while the decoding logic lives solely inside TerminalInputController.
*/
public typealias TerminalInput = TerminalInputController
