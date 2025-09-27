import Foundation

public struct MenuBarItem {

  public let title: String
  public let activationKey: Character
  public let action: () -> Void

  public init(title: String, activationKey: Character, action: @escaping () -> Void = {}) {
    self.title = title
    self.activationKey = activationKey
    self.action = action
  }

  func matches(_ key: Character) -> Bool {
    let lhs = String(activationKey).lowercased()
    let rhs = String(key).lowercased()
    return lhs == rhs
  }
}

public final class MenuBarModel {

  public var items: [MenuBarItem] {
    didSet {
      guard !items.isEmpty else {
        focusedIndex = nil
        return
      }
      guard let index = focusedIndex else { return }
      if index < 0 || index >= items.count {
        focusedIndex = nil
      }
    }
  }

  public private(set) var focusedIndex: Int?

  public init(items: [MenuBarItem] = []) {
    self.items = items
    focusedIndex = nil
  }

  public func focus(at index: Int) {
    guard index >= 0 else { return }
    guard index < items.count else { return }
    focusedIndex = index
  }

  public func clearFocus() {
    focusedIndex = nil
  }

  public func focusNext() {
    guard let current = focusedIndex else { return }
    guard !items.isEmpty else { return }
    let next = (current + 1) % items.count
    focusedIndex = next
  }

  public func focusPrevious() {
    guard let current = focusedIndex else { return }
    guard !items.isEmpty else { return }
    let previous = (current - 1 + items.count) % items.count
    focusedIndex = previous
  }

  @discardableResult
  public func activateFocused() -> Bool {
    guard let index = focusedIndex else { return false }
    guard index >= 0 && index < items.count else { return false }
    items[index].action()
    return true
  }

  @discardableResult
  public func activate(matchingKey key: Character) -> Bool {
    guard let index = items.firstIndex(where: { $0.matches(key) }) else { return false }
    focus(at: index)
    items[index].action()
    return true
  }
}
