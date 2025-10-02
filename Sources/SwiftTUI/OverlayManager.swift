import Foundation


public final class OverlayManager {

  private var overlays             : [Renderable]
  private var interactiveOverlays  : [OverlayInputHandling]
  private var invalidatableOverlays: [OverlayInvalidating]
  // Maintain a short FIFO buffer so overlays can drain bursts over several passes
  // without dropping keystrokes when they are busy repainting.
  private var bufferedInputs       : [TerminalInput.Input]

  private let maximumBufferedInputs = 32
  private let maximumInputsPerPass  = 16

  public var onChange: ((Bool) -> Void)? = nil

  public init ( overlays: [Renderable] = [] ) {
    self.overlays             = overlays
    self.interactiveOverlays  = []
    self.bufferedInputs       = []
    self.invalidatableOverlays = []
  }


  public func drawBox ( _ element: BoxElement ) {

    let bounds = element.bounds

    guard bounds.width  >= 2 else { return }
    guard bounds.height >= 2 else { return }

    // Persist the descriptor so overlay redraws can recover the full bounds and style.
    let box = Box(element: element)

    overlays.append ( box )
    onChange?(false)
  }


  public func drawMessageBox (
    _ message: String,
    context  : AppContext,
    row      : Int?              = nil,
    col      : Int?              = nil,
    style    : ElementStyle      = ElementStyle(),
    buttonText: String           = "OK",
    activationKey: TerminalInput.ControlKey = .RETURN,
    buttons  : [MessageBoxButton] = []
  ) {

    let buttonConfigs: [MessageBoxButton]
    if buttons.isEmpty {
      buttonConfigs = [MessageBoxButton(text: buttonText, activationKey: activationKey)]
    } else {
      buttonConfigs = buttons
    }

    let overlay = MessageBoxOverlay (
      message  : message,
      context  : context,
      row      : row,
      col      : col,
      style    : style,
      buttons  : buttonConfigs,
      onDismiss: { [weak self] in self?.clear() },
      onUpdate : { [weak self] in self?.onChange?(false) }
    )

    overlays.append ( overlay )
    interactiveOverlays.append( overlay )
    invalidatableOverlays.append( overlay )
    onChange?(false)
  }


  public func drawSelectionList (
    _ items: [SelectionListItem],
    context  : AppContext,
    row      : Int?         = nil,
    col      : Int?         = nil,
    style    : ElementStyle = ElementStyle(),
    onSelect : ((SelectionListItem) -> Void)? = nil,
    onDismiss: (() -> Void)? = nil
  ) {

    guard !items.isEmpty else { return }

    let overlay = SelectionListOverlay (
      items    : items,
      context  : context,
      row      : row,
      col      : col,
      style    : style,
      onSelect : onSelect,
      onDismiss: { [weak self] in
        onDismiss?()
        self?.clear()
      },
      onUpdate : { [weak self] in self?.onChange?(false) }
    )

    overlays.append ( overlay )
    interactiveOverlays.append ( overlay )
    invalidatableOverlays.append ( overlay )
    onChange?(false)
  }



  public func activeOverlays() -> [Renderable] {
    overlays
  }

  public func invalidateActiveOverlays() {
    for overlay in invalidatableOverlays {
      overlay.invalidateForFullRedraw()
    }
  }

  public func handle(inputs: [TerminalInput.Input]) -> Bool {

    guard !interactiveOverlays.isEmpty else { return false }

    if !inputs.isEmpty {
      bufferedInputs.append(contentsOf: inputs)

      if bufferedInputs.count > maximumBufferedInputs {
        let overflow = bufferedInputs.count - maximumBufferedInputs
        // Drop the oldest events first so new keystrokes stay responsive.
        bufferedInputs.removeFirst(overflow)
      }
    }

    guard !bufferedInputs.isEmpty else { return false }

    var handledAny     = false
    var processedCount = 0
    // Always chew through the newest batch while bounding the backlog so large
    // bursts can spill into subsequent passes without blocking the UI loop.
    let passQuota      = max(inputs.count, maximumInputsPerPass)
    let limit          = min(bufferedInputs.count, passQuota)

    while processedCount < limit {

      if interactiveOverlays.isEmpty {
        bufferedInputs.removeAll()
        break
      }

      let input    = bufferedInputs[processedCount]
      let handlers = interactiveOverlays

      for overlay in handlers {
        if overlay.handle(input) {
          handledAny = true
        }
      }

      processedCount += 1
    }

    if processedCount > 0 {
      bufferedInputs.removeFirst(processedCount)
    }

    return handledAny
  }

  public func clear() {
    overlays.removeAll()
    interactiveOverlays.removeAll()
    invalidatableOverlays.removeAll()
    onChange?(true)
  }
}


public struct MessageBoxButton {

  public let text          : String
  public let activationKey : TerminalInput.ControlKey
  public let handler       : ((AppContext) -> Void)?

  public init ( text: String, activationKey: TerminalInput.ControlKey = .RETURN, handler: ((AppContext) -> Void)? = nil ) {
    self.text          = text
    self.activationKey = activationKey
    self.handler       = handler
  }
}

final class MessageBoxOverlay: Renderable, OverlayInputHandling, OverlayInvalidating {

  private let messageBox  : MessageBox
  private let context     : AppContext
  private var buttons     : [Button]
  private var activeIndex : Int
  private let onUpdate    : (() -> Void)?
  private var cachedLayout: MessageBox.Layout?
  private var needsFullRedraw: Bool
  private var dirtyButtonIndices: Set<Int>
  private var didRenderLastPass: Bool

  // Lay out the button box relative to the outer border so we always preserve a
  // blank row above the divider, a row of padding above and below the buttons,
  // and a final gutter before the dialog footer. Expressing these as offsets
  // keeps the maths readable when the bounds shift at runtime.
  private static let bottomGutterOffset    = 1
  private static let buttonRowOffset       = bottomGutterOffset + 1
  private static let buttonTopBorderOffset = buttonRowOffset + 2
  private static let trailingBlankLines    = buttonTopBorderOffset + 1

  // Expose the highlight index for regression tests without widening the public surface.
  var debugActiveButtonIndex: Int { activeIndex }

  init(
    message   : String,
    context   : AppContext,
    row       : Int?,
    col       : Int?,
    style     : ElementStyle,
    buttons   : [MessageBoxButton],
    onDismiss : @escaping () -> Void,
    onUpdate  : (() -> Void)?
  ) {

    var body = message
    if !body.hasSuffix("\n") {
      body += "\n"
    }

    if !buttons.isEmpty {

      // Reserve trailing rows for the button container so we can draw a guttered
      // divider above the controls. Doing this here keeps the geometry stable
      // regardless of the caller's message length.
      var trailingNewlines = 0
      for character in body.reversed() {
        if character == "\n" {
          trailingNewlines += 1
          continue
        }
        break
      }

      if trailingNewlines < MessageBoxOverlay.trailingBlankLines {
        let shortfall = MessageBoxOverlay.trailingBlankLines - trailingNewlines
        body += String(repeating: "\n", count: shortfall)
      }
    }

    let minimumInteriorWidth = MessageBoxOverlay.minimumInteriorWidth(for: buttons)

    // Expand the underlying message box so that the button row is always wide
    // enough for the supplied button labels. Without this, wide button sets get
    // clipped because the default layout only considered the message text.
    self.messageBox  = MessageBox(
      message: body,
      row    : row,
      col    : col,
      style  : style,
      minimumInteriorWidth: minimumInteriorWidth
    )
    self.context     = context
    self.activeIndex = 0
    self.onUpdate    = onUpdate
    self.cachedLayout = nil
    self.needsFullRedraw = true
    self.didRenderLastPass = false

    // Convert the base element style into a highlight palette so buttons stay
    // visually consistent with the rest of the overlay.
    let highlightPalette = MessageBoxOverlay.highlightPalette(for: style)

    self.buttons = buttons.enumerated().map { index, config in
      let action = config.handler
      return Button (
        bounds             : BoxBounds(row: row ?? 1, col: col ?? 1, width: config.text.count + 4, height: 1),
        text               : config.text,
        style              : style,
        activationKey      : config.activationKey,
        onActivate         : {
          // Carry the current application context into button handlers so they can
          // present follow-up UI or interact with I/O pipelines safely.
          action?(context)
          onDismiss()
        },
        highlightForeground: highlightPalette.foreground,
        highlightBackground: highlightPalette.background,
        usesDimHighlight    : true,
        isHighlightActive   : index == 0
      )
    }

    self.dirtyButtonIndices = Set(self.buttons.indices)
  }

  func invalidateForFullRedraw() {
    cachedLayout     = nil
    needsFullRedraw  = true
    didRenderLastPass = false
    markAllButtonsDirty()
  }

  func render ( in size: winsize ) -> [AnsiSequence]? {

    guard let layout = messageBox.layout(in: size) else {
      cachedLayout      = nil
      didRenderLastPass = false
      needsFullRedraw   = true
      markAllButtonsDirty()
      return nil
    }

    if !didRenderLastPass {
      needsFullRedraw = true
    }

    // Cache the most recent layout so we can spot geometry changes without
    // forcing a full redraw on every highlight update. The renderer throttles
    // its output with `usleep`, so avoiding redundant work keeps navigation
    // responsive.
    if !MessageBoxOverlay.layout(layout, matches: cachedLayout) {
      cachedLayout    = layout
      needsFullRedraw = true
    }

    var sequences: [AnsiSequence] = []

    if needsFullRedraw {
      guard let boxSequences = messageBox.render(in: size) else {
        cachedLayout      = nil
        didRenderLastPass = false
        needsFullRedraw   = true
        markAllButtonsDirty()
        return nil
      }
      sequences += boxSequences

      if !buttons.isEmpty, let divider = MessageBoxOverlay.buttonDividerSequences(
        in    : layout.bounds,
        style : messageBox.element.style
      ) {
        sequences += divider
      }
      // The dialog body just repainted, so refresh every button to keep their
      // alignment anchored to the new bounds.
      markAllButtonsDirty()
      needsFullRedraw = false
    }

    guard !buttons.isEmpty else {
      didRenderLastPass = true
      return sequences
    }

    let bounds        = layout.bounds
    let interiorWidth = bounds.width - 2

    let minimumButtonWidths = buttons.reduce(0) { $0 + $1.minimumWidth }
    let gapCount            = max(buttons.count - 1, 0)


    guard minimumButtonWidths <= interiorWidth else {
      // Logging the refusal makes it obvious why callers lose their buttons; the guard only fires when
      // the dialog itself is narrower than the combined button labels so nothing could render safely.
      log("MessageBoxOverlay: skipping buttons, minimum width \(minimumButtonWidths) exceeds interior width \(interiorWidth)")
      didRenderLastPass = true
      return sequences
    }


    let availableGap = max(0, interiorWidth - minimumButtonWidths)
    // Prefer to preserve the existing two-column gutter, but collapse it evenly
    // across the row when space runs tight so every button can still render.
    let spacing      = gapCount > 0 ? min(2, availableGap / gapCount) : 0
    let totalWidth   = minimumButtonWidths + spacing * gapCount
    let outerBottomRow = bounds.row + bounds.height - 1
    let buttonRow      = outerBottomRow - MessageBoxOverlay.buttonRowOffset
    let startCol       = bounds.col + 1 + max(0, (interiorWidth - totalWidth) / 2)

    var currentCol = startCol
    
    //MARK: debug change
    // dropped first button to see if one of the dim buttons would render in place,
    // which they did, so their attribs appear to be sane
    // this is going to be width or position computation, which sucks, because codex wrote them
    // and its code is all fugly
    //for (index, button) in buttons.dropFirst().enumerated() {
    for (index, button) in buttons.enumerated() {
      button.isHighlightActive = (index == activeIndex)
      
      //DEBUG: observing these, they look sane but buttons dissapear when the height increses, wtf?
//      log("button row   \(buttonRow)")
//      log("button col   \(currentCol)")
//      log("button width \(button.minimumWidth)")
     
      button.bounds = BoxBounds(
        row   : buttonRow,
        col   : currentCol,
        width : button.minimumWidth,
        height: 1
      )

      if dirtyButtonIndices.contains(index), let buttonSequences = button.render(in: size) {
        sequences += buttonSequences
      }

      currentCol += button.minimumWidth + spacing
      //log("current col \(currentCol)") // it won't be this
    }

    dirtyButtonIndices.removeAll()

    didRenderLastPass = true

    return sequences
  }

  func handle(_ input: TerminalInput.Input) -> Bool {

    guard !buttons.isEmpty else { return false }

    // The overlay owns left/right navigation so only the focused button sees the
    // activation key. This keeps keyboard handling predictable for callers.
    switch input {

      case .cursor(let key):
        let previousIndex = activeIndex

        switch key {
          case .left  : activeIndex = max(0, activeIndex - 1)
          case .right : activeIndex = min(buttons.count - 1, activeIndex + 1)
          default     : break
        }

        if activeIndex != previousIndex {
          markButtonsDirty([previousIndex, activeIndex])
          onUpdate?()
          return true
        }

        return activeIndex != previousIndex

      default:
        return buttons[activeIndex].handle(input)
    }
  }

  private static func buttonDividerSequences ( in bounds: BoxBounds, style: ElementStyle ) -> [AnsiSequence]? {

    let interiorWidth = bounds.width - 2
    guard interiorWidth > 0 else { return nil }

    let dividerRow = bounds.row + bounds.height - 1 - buttonTopBorderOffset
    guard dividerRow > bounds.row else { return nil }

    let startCol = bounds.col + 1

    // Repaint the divider with a simple horizontal rule so the existing side
    // borders continue to frame the controls. Reusing the current colours keeps
    // the button well visually tied to the parent dialog.
    return [
      .hideCursor,
      .moveCursor ( row: dividerRow, col: startCol ),
      .backcolor  ( style.background ),
      .forecolor  ( style.foreground ),
      .box        ( .horiz(interiorWidth) ),
    ]
  }

  private static func highlightPalette(for style: ElementStyle) -> (foreground: ANSIForecolor, background: ANSIBackcolor) {

    let highlightBackground = MessageBoxOverlay.backcolor(for: style.foreground)
    let fallbackForeground  = MessageBoxOverlay.forecolor(for: style.background)

    if highlightBackground == style.background {
      // If the highlight would match the surrounding box fall back to white so
      // the selected button remains visible against darker themes.
      return (fallbackForeground, .white)
    }

    return (fallbackForeground, highlightBackground)
  }

  private static func minimumInteriorWidth(for buttons: [MessageBoxButton]) -> Int {

    guard !buttons.isEmpty else { return 0 }

    let labelWidth = buttons.reduce(0) { width, config in
      width + MessageBoxOverlay.buttonWidth(for: config.text)
    }

    // The message body can wrap but the controls cannot vanish, so favour the
    // button row when reserving space for the overlay.
    return labelWidth
  }

  private static func buttonWidth(for text: String) -> Int {
    // Button labels are rendered as "[ text ]" so we add four characters to the
    // raw label length to account for the brackets and surrounding spaces.
    return text.count + 4
  }

  private static func backcolor(for forecolor: ANSIForecolor) -> ANSIBackcolor {
    switch forecolor {
      case .black  : return .black
      case .red    : return .red
      case .green  : return .green
      case .yellow : return .yellow
      case .blue   : return .blue
      case .magenta: return .magenta
      case .cyan   : return .vyan
      case .white  : return .white
    }
  }

  private static func forecolor(for backcolor: ANSIBackcolor) -> ANSIForecolor {
    switch backcolor {
      case .black  : return .black
      case .red    : return .red
      case .green  : return .green
      case .yellow : return .yellow
      case .blue   : return .blue
      case .magenta: return .magenta
      case .vyan   : return .cyan
      case .white  : return .white
      case .grey   : return .white
    }
  }

  private func markButtonsDirty(_ indexes: [Int]) {
    for index in indexes where buttons.indices.contains(index) {
      dirtyButtonIndices.insert(index)
    }
  }

  private func markAllButtonsDirty() {
    dirtyButtonIndices = Set(buttons.indices)
  }

  private static func layout(_ layout: MessageBox.Layout, matches cached: MessageBox.Layout?) -> Bool {
    guard let cached = cached else { return false }

    let boundsMatch = cached.bounds.row    == layout.bounds.row
                   && cached.bounds.col    == layout.bounds.col
                   && cached.bounds.width  == layout.bounds.width
                   && cached.bounds.height == layout.bounds.height

    guard boundsMatch else { return false }

    return cached.lines == layout.lines
  }
}


public struct SelectionListItem {

  public let text    : String
  public let handler : ((AppContext) -> Void)?

  public init ( text: String, handler: ((AppContext) -> Void)? = nil ) {
    self.text    = text
    self.handler = handler
  }
}

final class SelectionListOverlay: Renderable, OverlayInputHandling, OverlayInvalidating {

  private let items             : [SelectionListItem]
  private let context           : AppContext
  private let row               : Int?
  private let col               : Int?
  private let style             : ElementStyle
  private let onSelect          : ((SelectionListItem) -> Void)?
  private let onDismiss         : () -> Void
  private let onUpdate          : (() -> Void)?
  private let highlightPalette  : (foreground: ANSIForecolor, background: ANSIBackcolor)

  private var activeIndex       : Int
  private var cachedBounds      : BoxBounds?
  private var needsFullRedraw   : Bool
  private var dirtyItemIndices  : Set<Int>
  private var didRenderLastPass : Bool
  private var isDismissed       : Bool

  var debugActiveIndex : Int { activeIndex }

  init (
    items    : [SelectionListItem],
    context  : AppContext,
    row      : Int?,
    col      : Int?,
    style    : ElementStyle,
    onSelect : ((SelectionListItem) -> Void)?,
    onDismiss: @escaping () -> Void,
    onUpdate : (() -> Void)?
  ) {

    self.items             = items
    self.context           = context
    self.row               = row
    self.col               = col
    self.style             = style
    self.onSelect          = onSelect
    self.onDismiss         = onDismiss
    self.onUpdate          = onUpdate
    self.activeIndex       = 0
    self.needsFullRedraw   = true
    self.dirtyItemIndices  = Set(items.indices)
    self.cachedBounds      = nil
    self.didRenderLastPass = false
    self.isDismissed       = false

    // Reuse the same palette rules as the message box buttons so every overlay
    // stays visually coherent even when callers customise the base style.
    self.highlightPalette   = SelectionListOverlay.highlightPalette ( for: style )
  }

  func invalidateForFullRedraw () {
    cachedBounds      = nil
    needsFullRedraw   = true
    didRenderLastPass = false
    markAllItemsDirty()
  }

  func render ( in size: winsize ) -> [AnsiSequence]? {

    guard !items.isEmpty else { return nil }

    guard let bounds = layout ( in: size ) else {
      cachedBounds      = nil
      needsFullRedraw   = true
      didRenderLastPass = false
      markAllItemsDirty()
      return nil
    }

    if !didRenderLastPass {
      needsFullRedraw = true
    }

    if SelectionListOverlay.bounds ( bounds, matches: cachedBounds ) == false {
      cachedBounds    = bounds
      needsFullRedraw = true
    }

    var sequences: [AnsiSequence] = []

    if needsFullRedraw {

      let element = BoxElement ( bounds: bounds, style: style )

      guard let boxSequences = Box ( element: element ).render ( in: size ) else {
        cachedBounds      = nil
        needsFullRedraw   = true
        didRenderLastPass = false
        markAllItemsDirty()
        return nil
      }

      sequences += boxSequences
      needsFullRedraw = false
      markAllItemsDirty()
    }

    guard !dirtyItemIndices.isEmpty else {
      didRenderLastPass = true
      return sequences
    }

    let interiorWidth = bounds.width - 2
    let textStartRow  = bounds.row + 1
    let textStartCol  = bounds.col + 1

    let baseBackground = style.background
    let baseForeground = style.foreground
    let highlightBackground = highlightPalette.background
    let highlightForeground = highlightPalette.foreground

    for index in dirtyItemIndices.sorted() {

      guard items.indices.contains ( index ) else { continue }

      let label = items[index].text
      let clampedWidth = max(0, interiorWidth)
      let paddedLabel  = " " + label
      let paddingCount = max(0, clampedWidth - paddedLabel.count)
      let padded = paddedLabel + String(repeating: " ", count: paddingCount)

      let background = index == activeIndex ? highlightBackground : baseBackground
      let foreground = index == activeIndex ? highlightForeground : baseForeground

      sequences += [
        .moveCursor(row: textStartRow + index, col: textStartCol),
        .backcolor(background),
        .forecolor(foreground),
        .text(padded)
      ]
    }

    dirtyItemIndices.removeAll()
    didRenderLastPass = true

    return sequences
  }

  func handle ( _ input: TerminalInput.Input ) -> Bool {

    guard !items.isEmpty else { return false }

    switch input {

      case .cursor(let key) :
        let previousIndex = activeIndex

        switch key {
          case .up   :
            activeIndex = max(0, activeIndex - 1)
          case .down :
            activeIndex = min(items.count - 1, activeIndex + 1)
          default    :
            return false
        }

        guard activeIndex != previousIndex else { return false }

        markItemsDirty ( [previousIndex, activeIndex] )
        onUpdate?()
        return true

      case .key(let key) :
        switch key {
          case .RETURN :
            activateSelection()
            return true
          case .ESC    :
            dismiss()
            return true
          default      :
            return false
        }

      case .ascii(let data) :
        if data.contains ( 0x0d ) {
          activateSelection()
          return true
        }
        return false

      default     :
        return false
    }
  }

  private func layout ( in size: winsize ) -> BoxBounds? {

    let rows    = Int(size.ws_row)
    let columns = Int(size.ws_col)

    guard rows > 0 && columns > 0 else { return nil }

    let interiorWidth = SelectionListOverlay.minimumInteriorWidth ( for: items )
    let width  = interiorWidth + 2
    let height = items.count + 2

    guard width  <= columns else { return nil }
    guard height <= rows    else { return nil }

    let top  = row ?? max(1, ((rows    - height) / 2) + 1)
    let left = col ?? max(1, ((columns - width ) / 2) + 1)

    let bottom = top  + height - 1
    let right  = left + width  - 1

    guard top    >= 1 else { return nil }
    guard left   >= 1 else { return nil }
    guard bottom <= rows else { return nil }
    guard right  <= columns else { return nil }

    return BoxBounds ( row: top, col: left, width: width, height: height )
  }

  private func activateSelection () {
    guard items.indices.contains ( activeIndex ) else { return }

    let item = items[activeIndex]
    onSelect? ( item )
    // Pass through the broader application context so selection handlers can
    // trigger follow-up overlays or logging without reaching back into global state.
    item.handler? ( context )
    dismiss()
  }

  private func dismiss () {
    guard !isDismissed else { return }
    isDismissed = true
    onDismiss()
    onUpdate?()
  }

  private func markItemsDirty ( _ indexes: [Int] ) {
    for index in indexes where items.indices.contains ( index ) {
      dirtyItemIndices.insert(index)
    }
  }

  private func markAllItemsDirty () {
    dirtyItemIndices = Set(items.indices)
  }

  private static func minimumInteriorWidth ( for items: [SelectionListItem] ) -> Int {
    let widest = items.map { $0.text.count }.max() ?? 0
    // Provide a trailing space so highlighted rows never touch the right border.
    // This matches the visual balance of the left padding and keeps the cursor
    // well clear of the frame when the overlay is repainted.
    return max(widest + 2, 2)
  }

  private static func highlightPalette ( for style: ElementStyle ) -> (foreground: ANSIForecolor, background: ANSIBackcolor) {

    let highlightBackground = SelectionListOverlay.backcolor ( for: style.foreground )
    let fallbackForeground  = SelectionListOverlay.forecolor ( for: style.background )

    if highlightBackground == style.background {
      // When the highlight would blend into the background fall back to white so
      // the focused row stays visible against darker palettes.
      return (fallbackForeground, .white)
    }

    return (fallbackForeground, highlightBackground)
  }

  private static func backcolor ( for forecolor: ANSIForecolor ) -> ANSIBackcolor {
    switch forecolor {
      case .black  : return .black
      case .red    : return .red
      case .green  : return .green
      case .yellow : return .yellow
      case .blue   : return .blue
      case .magenta: return .magenta
      case .cyan   : return .vyan
      case .white  : return .white
    }
  }

  private static func forecolor ( for backcolor: ANSIBackcolor ) -> ANSIForecolor {
    switch backcolor {
      case .black  : return .black
      case .red    : return .red
      case .green  : return .green
      case .yellow : return .yellow
      case .blue   : return .blue
      case .magenta: return .magenta
      case .vyan   : return .cyan
      case .white  : return .white
      case .grey   : return .white
    }
  }

  private static func bounds ( _ bounds: BoxBounds, matches cached: BoxBounds? ) -> Bool {
    guard let cached = cached else { return false }

    return cached.row    == bounds.row
        && cached.col    == bounds.col
        && cached.width  == bounds.width
        && cached.height == bounds.height
  }
}
