import Foundation

public final class LightweightTestApp {

  public let state: TerminalState
  public let menuBarModel: MenuBarModel

  private let output: OutputDisplaying
  private let presenter: TerminalPresenter
  private var menuRenderer: MenuBarRenderer
  private var terminalWidth: Int
  private var terminalHeight: Int
  private var running = false
  private let inputController: TerminalInputController?

  public init(
    width: Int = 80,
    height: Int = 24,
    statusText: String = "Ready",
    statusForegroundColor: ANSIForecolor = .white,
    statusBackgroundColor: ANSIBackcolor = .bgBlue,
    menuItems: [MenuBarItem]? = nil,
    output: OutputDisplaying = OutputController()
  ) {
    let sanitizedWidth = max(0, width)
    let sanitizedHeight = max(1, height)

    self.state = TerminalState(
      statusText: statusText,
      foregroundColor: statusForegroundColor,
      backgroundColor: statusBackgroundColor
    )

    let resolvedMenuItems = menuItems ?? LightweightTestApp.defaultMenuItems(state: state)
    self.menuBarModel = MenuBarModel(items: resolvedMenuItems)
    if !resolvedMenuItems.isEmpty {
      menuBarModel.focus(at: 0)
    }

    self.output = output
    self.terminalWidth = sanitizedWidth
    self.terminalHeight = sanitizedHeight
    self.menuRenderer = MenuBarRenderer(width: sanitizedWidth, row: 1)
    self.presenter = TerminalPresenter(
      state: state,
      menuBarModel: menuBarModel,
      output: output,
      initialWidth: sanitizedWidth,
      initialHeight: sanitizedHeight
    )

    #if canImport(Darwin)
    self.inputController = TerminalInputController()
    #else
    self.inputController = nil
    #endif
  }

  public func start() {
    guard !running else { return }
    running = true

    output.send(
      .altBuffer,
      .clearScrollBack,
      .cls,
      .hideCursor
    )

    layout(width: terminalWidth, height: terminalHeight)

    inputController?.handler = { [weak self] result in
      guard let self = self else { return }
      switch result {
        case .success(let events):
          for event in events {
            self.presenter.handle(input: event)
          }
          self.redrawMenu()
        case .failure(let trace):
          self.state.statusText = "Input error: \(trace)"
      }
    }

    inputController?.stream.resume()

    inputController?.makeRaw()
  }

  public func run() {
    start()
    RunLoop.current.run()
  }

  public func stop() {
    guard running else { return }
    running = false

    inputController?.unmakeRaw()

    output.send(
      .showCursor,
      .normBuffer
    )
  }

  public func layout(width: Int, height: Int) {
    terminalWidth = max(0, width)
    terminalHeight = max(1, height)
    menuRenderer.update(width: terminalWidth)
    presenter.layout(width: terminalWidth, height: terminalHeight)
    redrawMenu()
  }

  public func refreshMenu() {
    redrawMenu()
  }

  deinit {
    stop()
  }

  private func redrawMenu() {
    guard terminalWidth > 0 else { return }
    output.display(menuRenderer.render(model: menuBarModel))
  }

  private static func defaultMenuItems(state: TerminalState) -> [MenuBarItem] {
    [
      MenuBarItem(title: "File", activationKey: "f") {
        state.statusText = "File menu activated"
      },
      MenuBarItem(title: "Edit", activationKey: "e") {
        state.statusText = "Edit menu activated"
      },
      MenuBarItem(title: "View", activationKey: "v") {
        state.statusText = "View menu activated"
      }
    ]
  }
}

private struct MenuBarRenderer {

  private var width: Int
  private let row: Int
  private let foregroundColor: ANSIForecolor
  private let backgroundColor: ANSIBackcolor

  init(
    width: Int,
    row: Int,
    foregroundColor: ANSIForecolor = .white,
    backgroundColor: ANSIBackcolor = .bgBlack
  ) {
    self.width = max(0, width)
    self.row = max(1, row)
    self.foregroundColor = foregroundColor
    self.backgroundColor = backgroundColor
  }

  mutating func update(width: Int) {
    self.width = max(0, width)
  }

  func render(model: MenuBarModel) -> AnsiSequence {
    guard width > 0 else { return .flatten([]) }

    let content = lineContent(model: model)
    let clipped = String(content.prefix(width))
    let padded = clipped + String(repeating: " ", count: max(0, width - clipped.count))

    return .flatten([
      .moveCursor(row: row, col: 1),
      .backcolor(backgroundColor),
      .forecolor(foregroundColor),
      .text(padded),
      .resetcolor
    ])
  }

  private func lineContent(model: MenuBarModel) -> String {
    guard !model.items.isEmpty else { return "" }

    let segments = model.items.enumerated().map { index, item -> String in
      let key = String(item.activationKey).uppercased()
      let label = "\(item.title) (\(key))"
      if index == model.focusedIndex {
        return "[\(label)]"
      }
      return " \(label) "
    }

    return segments.joined(separator: " ")
  }
}
