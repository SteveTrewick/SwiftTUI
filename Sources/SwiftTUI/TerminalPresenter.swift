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
  private var awaitingAltChord = false

  public let menuBarModel: MenuBarModel

  public init(
    state: TerminalState,
    menuBarModel: MenuBarModel = MenuBarModel(),
    output: OutputDisplaying = OutputController(),
    initialWidth: Int,
    initialHeight: Int
  ) {
    self.state = state
    self.menuBarModel = menuBarModel
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

  public func handle(input: TerminalInput.Input) {

    switch input {

      case .cursor(let direction):
        guard menuBarModel.focusedIndex != nil else { return }
        switch direction {
          case .left:
            menuBarModel.focusPrevious()
          case .right:
            menuBarModel.focusNext()
          default:
            break
        }
        awaitingAltChord = false

      case .key(let control):
        switch control {
          case .RETURN:
            guard menuBarModel.focusedIndex != nil else { return }
            _ = menuBarModel.activateFocused()
            awaitingAltChord = false
          case .ESC:
            awaitingAltChord = true
          default:
            awaitingAltChord = false
        }

      case .ascii(let data), .unicode(let data):
        handleCharacterData(data)

      default:
        awaitingAltChord = false
    }
  }

  private func handleCharacterData(_ data: Data) {

    guard !data.isEmpty else { return }

    if data.first == 0x1b { // ESC prefix, treat as ALT chord start
      if data.count == 1 {
        awaitingAltChord = true
        return
      }

      awaitingAltChord = false
      guard let byte = data.dropFirst().first else { return }
      let scalar = UnicodeScalar(byte)
      _ = menuBarModel.activate(matchingKey: Character(scalar))
      return
    }

    guard awaitingAltChord else { return }
    awaitingAltChord = false
    guard let byte = data.first else { return }
    let scalar = UnicodeScalar(byte)
    _ = menuBarModel.activate(matchingKey: Character(scalar))
  }
}
