import Foundation
#if canImport(OSLog)
import OSLog
#endif

public func log(_ string: String) {
#if canImport(OSLog)
  os_log(.debug, "%{public}s", "\(string)")
#else
  print(string)
#endif
}

public protocol Renderable {
  func render ( in size: winsize ) -> [AnsiSequence]?
}
