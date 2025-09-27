import Foundation

public protocol OutputDisplaying {
  func display(_ sequences: AnsiSequence...)
}

extension OutputController: OutputDisplaying {}

public final class TerminalState {

  public var statusText: String {
    didSet {
      statusBarModel.content = statusText
    }
  }

  public let statusBarModel: StatusBarModel

  public init(
    statusText: String = "",
    foregroundColor: ANSIForecolor = .white,
    backgroundColor: ANSIBackcolor = .bgBlue
  ) {
    self.statusText = statusText
    self.statusBarModel = StatusBarModel(
      content: statusText,
      foregroundColor: foregroundColor,
      backgroundColor: backgroundColor
    )
  }
}

public final class TerminalPresenter {

  private var terminalWidth: Int
  private var terminalHeight: Int
  private let output: OutputDisplaying
  private let state: TerminalState
  private var statusBar: StatusBar

  public init(
    state: TerminalState,
    output: OutputDisplaying = OutputController(),
    initialWidth: Int,
    initialHeight: Int
  ) {
    self.state = state
    self.output = output
    self.terminalWidth = max(0, initialWidth)
    self.terminalHeight = max(1, initialHeight)
    self.statusBar = StatusBar(width: terminalWidth, row: terminalHeight)

    state.statusBarModel.bind { [weak self] _ in
      self?.redrawStatusBar()
    }
  }

  public func layout(width: Int, height: Int) {
    terminalWidth = max(0, width)
    terminalHeight = max(1, height)
    statusBar.updateSize(width: terminalWidth, row: terminalHeight)
    redrawStatusBar()
  }

  private func redrawStatusBar() {
    guard terminalWidth > 0 else { return }
    output.display(statusBar.render(model: state.statusBarModel))
  }
}
