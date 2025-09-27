import Foundation
import OSLog

public func log(_ string: String) {
  os_log(.debug, "%{public}s", "\(string)")
}

