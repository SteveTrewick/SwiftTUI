/*
  small set of routines to track changes to the size of the window
  containing the terminal
*/

import Foundation

#if os(Linux)
private func ioctlWindowSize(_ winsizePointer: UnsafeMutablePointer<winsize>) -> Int32 {
  ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), winsizePointer)
}
#else
private func ioctlWindowSize(_ winsizePointer: UnsafeMutablePointer<winsize>) -> Int32 {
  ioctl(STDOUT_FILENO, TIOCGWINSZ, winsizePointer)
}
#endif

public class WindowChanges {


  private let queue   : DispatchQueue
  private let source  : DispatchSourceSignal

  public var size     = winsize()
  public var onChange : ( (winsize) -> Void )? = nil


  public init() {

    self.queue  = DispatchQueue(label: "SIGWINCH")
    self.source = DispatchSource.makeSignalSource(signal: SIGWINCH, queue: queue)

    // get initial window frame
    if ioctlWindowSize(&size) != 0 {
      log("IOCTL fail, could not dermine initial windows size")
    }

    source.setEventHandler { [self] in
      var newsize = winsize()
      if ioctlWindowSize(&newsize) == 0 {
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
