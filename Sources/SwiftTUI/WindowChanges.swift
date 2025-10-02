/*
  small set of routines to track changes to the size of the window
  containing the terminal
*/

import Foundation

public class WindowChanges {
  
  
  private let queue           : DispatchQueue
  private let source          : DispatchSourceSignal
  private var pendingCallback : DispatchWorkItem?
  private let debounceDelay   : DispatchTimeInterval = .milliseconds(50)
  
  public var size     = winsize()
  public var onChange : ( (winsize) -> Void )? = nil
  
  
  public init() {
    
    self.queue  = DispatchQueue(label: "SIGWINCH")
    self.source = DispatchSource.makeSignalSource(signal: SIGWINCH, queue: queue)
    
    // get initial window frame
    if ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &size) != 0 {
      log("IOCTL fail, could not dermine initial windows size")
    }
    
    source.setEventHandler { [self] in
      /*
        macOS dispatches SIGWINCH in rapid bursts while a user drags the window
        edges. Without throttling this stream the renderer can be interrupted
        mid-frame which leaves the screen in a corrupted state. Buffer the
        changes and only react once the sequence settles.
      */
      var newsize = winsize()
      if ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &newsize) == 0 {
        size = newsize

        pendingCallback?.cancel()

        let work = DispatchWorkItem { [weak self] in
          guard let strongSelf = self else { return }
          guard let handler    = strongSelf.onChange else { return }

          DispatchQueue.main.async {
            // Ensure the resize render runs on the main/render queue with the rest of the UI work.
            handler(strongSelf.size)
          }
        }

        pendingCallback = work
        queue.asyncAfter(deadline: .now() + debounceDelay, execute: work)
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
