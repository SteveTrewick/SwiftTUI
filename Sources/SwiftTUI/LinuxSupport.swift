#if os(Linux)
import Foundation

public struct Trace: Error, CustomStringConvertible {
  public let origin: Any
  public let tag: String

  public init(_ origin: Any, tag: String) {
    self.origin = origin
    self.tag = tag
  }

  public var description: String {
    "Trace(origin: \(String(describing: origin)), tag: \(tag))"
  }
}

public final class PosixInputStream {
  public typealias Handler = (Result<Data, Trace>) -> Void

  public var handler: Handler?

  public init(descriptor: Int32) {
    _ = descriptor
  }

  public func resume() {}
}
#endif
