
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
  private let input        = TerminalInput()
  
  // TODO: unpublic this please
  public let stream : PosixInputStream
  
  public var handler : ( (Result<[TerminalInput.Input], Trace>) -> Void  )? = nil
  
  
  public init() {
    
    tcflush(STDIN_FILENO, TCIFLUSH)
    _ = fcntl(STDIN_FILENO, F_SETFL, O_NONBLOCK)
    tcgetattr(STDIN_FILENO, &termios_orig)
    
    termios_curr   = termios_orig
    stream         = PosixInputStream(descriptor: STDIN_FILENO)
    stream.handler = self.contextualise
  }
  
  
  
  func contextualise (result: Result<Data, Trace> ) {
    switch result {
      case .failure(let trace) : handler? ( .failure(trace) )
      case .success(let bytes) : handler? ( input.translate(bytes: bytes) )
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
}
