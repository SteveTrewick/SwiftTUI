import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

#if canImport(Trace)
import Trace
#endif
#if canImport(PosixInputStream)
import PosixInputStream
#endif

public class TerminalInputController {
  
  private var termios_orig = termios()
  private var termios_curr = termios()
  private var decoder      : TerminalInput.Decoder
  
  // TODO: unpublic this please
  public let stream : PosixInputStream
  
  public var handler : ( (Result<[TerminalInput.Input], Trace>) -> Void  )? = nil
  
  
  public init() {
    
    decoder = TerminalInput.Decoder(input: TerminalInput())

    tcflush(STDIN_FILENO, TCIFLUSH)
    _ = fcntl(STDIN_FILENO, F_SETFL, O_NONBLOCK)
    tcgetattr(STDIN_FILENO, &termios_orig)

    termios_curr   = termios_orig
    stream         = PosixInputStream(descriptor: STDIN_FILENO)
    stream.handler = self.contextualise
  }



  func contextualise (result: Result<Data, Trace> ) {
    switch result {
      case .failure(let trace) :
        emitTrailingInputs()
        handler? ( .failure(trace) )

      case .success(let bytes) :
        guard !bytes.isEmpty else {
          emitTrailingInputs()
          return
        }

        switch decoder.feed ( bytes ) {
          case .failure(let trace) : handler? ( .failure(trace) )
          case .success(let inputs) :
            guard !inputs.isEmpty else { return }
            handler? ( .success(inputs) )
        }
    }
  }
  
  
  public func makeRaw() {
    cfmakeraw(&termios_curr)
    tcsetattr(STDIN_FILENO, TCSANOW, &termios_curr)
  }
  
  
  public func unmakeRaw() {
    // there is no cfmakesane exposed, so er, just do this ...
    tcsetattr(STDIN_FILENO, TCSANOW, &termios_orig)
  }


  private func emitTrailingInputs() {

    // Keep the streaming decoder honest when the pipe closes.  We flush any
    // buffered state so callers see the final keystrokes (or decoding failure)
    // before the UI restores the terminal to cooked mode.
    switch decoder.flush() {

      case .failure(let trace) :
        handler? ( .failure(trace) )

      case .success(let inputs) :
        guard !inputs.isEmpty else { return }
        handler? ( .success(inputs) )
    }
  }
}
