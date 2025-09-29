/*
  small set of routines to track changes to the size of the window
  containing the terminal
*/

import Foundation

public class WindowChangeTracker {
  
  
  private let queue   : DispatchQueue
  private let source  : DispatchSourceSignal
  
  public var size     = winsize()
  public var onChange : ( (winsize) -> Void )? = nil
  
  
  public init() {
    
    self.queue  = DispatchQueue(label: "SIGWINCH")
    self.source = DispatchSource.makeSignalSource(signal: SIGWINCH, queue: queue)
    
    // get initial window frame
    if ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) != 0 {
      log("IOCTL fail, could not dermine initial windows size")
    }
    
    source.setEventHandler { [self] in
      var newsize = winsize()
      if ioctl(STDOUT_FILENO, TIOCGWINSZ, &newsize) == 0 {
        size = newsize
        onChange?(newsize)
      }
    }
  
  }
  
  
  public func track() {
    source.resume()
  }
  
  
  public func untrack() {
    source.cancel()
  }
  
}
