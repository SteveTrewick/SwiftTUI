import Foundation

public final class StatusBar {

  public var foreground: ANSIForecolor
  public var background: ANSIBackcolor

  private let output: OutputController

  public init(
    output: OutputController = OutputController(),
    foreground: ANSIForecolor = .black,
    background: ANSIBackcolor = .bgWhite
  ) {
    self.output = output
    self.foreground = foreground
    self.background = background
  }

  public func draw(text: String, in size: winsize) {
    let row = Int(size.ws_row)
    let columns = Int(size.ws_col)
    guard row > 0 && columns > 0 else { return }

    let visibleText = String(text.prefix(columns))
    let paddingCount = max(0, columns - visibleText.count)
    let paddedText = visibleText + String(repeating: " ", count: paddingCount)

    output.display(
      .moveCursor(row: row, col: 1),
      .backcolor(background),
      .forecolor(foreground),
      .text(paddedText),
      .resetcolor
    )
  }
}
