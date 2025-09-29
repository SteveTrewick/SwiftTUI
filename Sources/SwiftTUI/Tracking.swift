import Foundation

public final class WindowSizeTracking {

  private let windowChanges: WindowChanges
  private let statusBar: StatusBar

  public init(
    windowChanges: WindowChanges = WindowChanges(),
    output: OutputController = OutputController(),
    foreground: ANSIForecolor = .black,
    background: ANSIBackcolor = .bgWhite
  ) {
    self.windowChanges = windowChanges
    self.statusBar = StatusBar(
      output: output,
      foreground: foreground,
      background: background
    )

    self.windowChanges.onChange = { [weak self] size in
      self?.renderStatus(for: size)
    }
  }

  public func start() {
    renderStatus(for: windowChanges.size)
    windowChanges.track()
  }

  public func stop() {
    windowChanges.untrack()
  }

  private func renderStatus(for size: winsize) {
    let columns = Int(size.ws_col)
    let rows = Int(size.ws_row)
    let text = "Window size: \(columns) x \(rows)"
    statusBar.draw(text: text, in: size)
  }

  deinit {
    windowChanges.untrack()
  }
}
