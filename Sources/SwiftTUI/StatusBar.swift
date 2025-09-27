import Foundation

public struct StatusBar {

  public private(set) var width: Int
  public private(set) var row: Int

  public init(width: Int, row: Int) {
    self.width = max(0, width)
    self.row = max(1, row)
  }

  public mutating func updateSize(width: Int, row: Int) {
    self.width = max(0, width)
    self.row = max(1, row)
  }

  public func render(model: StatusBarModel) -> AnsiSequence {

    guard width > 0 else { return .flatten([]) }

    let content = model.text(maxWidth: width)
    let padded = content + String(repeating: " ", count: max(0, width - content.count))

    return .flatten([
      .moveCursor(row: row, col: 1),
      .backcolor(model.backgroundColor),
      .forecolor(model.foregroundColor),
      .text(padded),
      .resetcolor,
    ])
  }
}

public final class StatusBarModel {

  public var content: String { didSet { notifyChange() } }
  public var foregroundColor: ANSIForecolor { didSet { notifyChange() } }
  public var backgroundColor: ANSIBackcolor { didSet { notifyChange() } }

  private var changeHandler: ((StatusBarModel) -> Void)?

  public init(
    content: String = "",
    foregroundColor: ANSIForecolor = .white,
    backgroundColor: ANSIBackcolor = .bgBlue
  ) {
    self.content = content
    self.foregroundColor = foregroundColor
    self.backgroundColor = backgroundColor
  }

  public func bind(_ handler: @escaping (StatusBarModel) -> Void) {
    changeHandler = handler
    handler(self)
  }

  public func text(maxWidth: Int) -> String {

    guard maxWidth > 0 else { return "" }

    if content.count <= maxWidth { return content }

    if maxWidth == 1 { return "…" }

    let visibleCount = maxWidth - 1
    let prefix = content.prefix(visibleCount)
    return String(prefix) + "…"
  }

  private func notifyChange() {
    changeHandler?(self)
  }
}
