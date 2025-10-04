import Foundation


// Overlays that can describe their on-screen footprint expose that through this protocol
// so dismissal can surgically scrub their region without disturbing surrounding UI chrome.
protocol OverlayBoundsReporting {
  var overlayBounds: BoxBounds? { get }
}


public final class OverlayManager {

  private var overlays             : [Renderable]
  private var interactiveOverlays  : [OverlayInputHandling]
  private var invalidatableOverlays: [OverlayInvalidating]
  // Maintain a short FIFO buffer so overlays can drain bursts over several passes
  // without dropping keystrokes when they are busy repainting.
  private var bufferedInputs       : [TerminalInput.Input]
  // Cache the most recent overlay bounds so dismissal clears only the visible region.
  private var pendingClearBounds   : [BoxBounds]

  private let maximumBufferedInputs = 32
  private let maximumInputsPerPass  = 16

  // Propagate overlay lifecycle events so the renderer can adapt its clearing strategy.
  // Flag overlay updates so the renderer can avoid repainting the base chrome when
  // only transient overlay content has changed (for example, selection highlights).
  public enum Change {
    case updated ( needsBaseRedraw: Bool )
    case cleared
  }

  public var onChange: ((Change) -> Void)? = nil

  public init ( overlays: [Renderable] = [] ) {
    self.overlays             = overlays
    self.interactiveOverlays  = []
    self.bufferedInputs       = []
    self.invalidatableOverlays = []
    self.pendingClearBounds   = []
  }


  public func drawBox ( _ element: BoxElement ) {

    let bounds = element.bounds

    guard bounds.width  >= 2 else { return }
    guard bounds.height >= 2 else { return }

    // Persist the descriptor so overlay redraws can recover the full bounds and style.
    let box = Box(element: element)

    overlays.append ( box )
    onChange?( .updated ( needsBaseRedraw: true ) )
  }


  // Centralise overlay registration so every modal hooks into the manager consistently.
  private func registerOverlay <T> ( _ overlay: T, needsBaseRedraw: Bool = true )
    where T: Renderable & OverlayInputHandling & OverlayInvalidating
  {

    overlays.append ( overlay )
    interactiveOverlays.append ( overlay )
    invalidatableOverlays.append ( overlay )
    onChange?( .updated ( needsBaseRedraw: needsBaseRedraw ) )
  }


  public func drawMessageBox (
    _ message    : String,
    context      : AppContext,
    row          : Int?              = nil,
    col          : Int?              = nil,
    style        : ElementStyle?     = nil,
    buttonText   : String           = "OK",
    activationKey: TerminalInput.ControlKey = .RETURN,
    buttons      : [MessageBoxButton] = []
  )
  {

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
      style    : style ?? context.style,
      buttons  : buttonConfigs,
      onDismiss: { [weak self] in self?.clear() },
      onUpdate : { [weak self] needsBaseRedraw in self?.onChange?( .updated ( needsBaseRedraw: needsBaseRedraw ) ) }
    )

    registerOverlay ( overlay )
  }


  public func drawSelectionList (
    _ items: [SelectionListItem],
    context  : AppContext,
    row      : Int?         = nil,
    col      : Int?         = nil,
    style    : ElementStyle? = nil,
    onSelect : ((SelectionListItem) -> Void)? = nil,
    onDismiss: (() -> Void)? = nil
  ) {

    guard !items.isEmpty else { return }

    let overlay = SelectionListOverlay (
      items    : items,
      context  : context,
      row      : row,
      col      : col,
      style    : style ?? context.style,
      onSelect : onSelect,
      onDismiss: { [weak self] in
        onDismiss?()
        self?.clear()
      },
      onUpdate : { [weak self] needsBaseRedraw in self?.onChange?( .updated ( needsBaseRedraw: needsBaseRedraw ) ) }
    )

    registerOverlay ( overlay )
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

    var handledAny           = false
    var processedCount       = 0
    var sawInteractiveOverlay = false
    // Always chew through the newest batch while bounding the backlog so large
    // bursts can spill into subsequent passes without blocking the UI loop.
    let passQuota      = max(inputs.count, maximumInputsPerPass)
    let limit          = min(bufferedInputs.count, passQuota)

    while processedCount < limit {

      guard let focusedOverlay = interactiveOverlays.last else {
        bufferedInputs.removeAll()
        break
      }

      // When an overlay is on-screen it owns the keyboard focus. This keeps modal
      // flows predictable and ensures stray keystrokes cannot reach background UI.
      sawInteractiveOverlay = true

      let input      = bufferedInputs[processedCount]
      let keyHandler = focusedOverlay.keyHandler

      if case .key(let key) = input, key == .ESC, keyHandler.shouldSwallowPrintableAfterEscape {
        let nextIndex    = processedCount + 1
        let hasLookahead = nextIndex < limit

        if hasLookahead {
          let lookaheadInput = bufferedInputs[nextIndex]

          switch lookaheadInput {
            case .ascii, .unicode:
              // Option-key menu accelerators surface as ESC followed by a
              // printable character. When the overlay claims ESC we swallow the
              // printable payload so option-key chords stay local to the menu
              // bar instead of leaking to the application.
              processedCount += 2
              handledAny      = true
              continue
            default:
              break
          }
        }
      }

      if keyHandler.handle ( input ) {
        handledAny = true
      }

      processedCount += 1
    }

    if processedCount > 0 {
      // Clearing an overlay during dispatch can empty the buffer via the guard
      // above. Guard the removal so we never walk past the shrunken array while
      // draining events delivered to an overlay that dismissed itself.
      if bufferedInputs.count >= processedCount {
        bufferedInputs.removeFirst(processedCount)
      } else {
        bufferedInputs.removeAll()
      }
    }

    return handledAny || sawInteractiveOverlay
  }

  public func clear() {
    // Pull stacked handlers before tearing down overlays so any follow-up UI can
    // push its own entry without waiting for deinitialisation.
    for overlay in interactiveOverlays {
      overlay.keyHandler.popHandler()
    }
    pendingClearBounds = overlays.compactMap { overlay in
      guard let reporting = overlay as? OverlayBoundsReporting else { return nil }
      return reporting.overlayBounds
    }
    overlays.removeAll()
    interactiveOverlays.removeAll()
    invalidatableOverlays.removeAll()
    onChange?( .cleared )
  }

  public func consumeClearedOverlayBounds() -> [BoxBounds] {
    defer { pendingClearBounds.removeAll() }
    return pendingClearBounds
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

final class MessageBoxOverlay: Renderable, OverlayInputHandling, OverlayInvalidating, OverlayBoundsReporting {

  // Button interactions are routed through a small helper so we can reuse the
  // lightweight renderer while keeping keystroke handling close to the overlay.
  // This avoids teaching `Button` about highlight state or activation flows and
  // keeps it focused on painting a labelled control.
  final class ButtonController {

    private let configuration    : MessageBoxButton
    private let style            : ElementStyle
    private let highlightPalette : (foreground: ANSIForecolor, background: ANSIBackcolor)
    private let context          : AppContext
    private let onDismiss        : () -> Void
    private let button           : Button
    private var isArmed          : Bool

    init(
      configuration    : MessageBoxButton,
      style            : ElementStyle,
      highlightPalette : (foreground: ANSIForecolor, background: ANSIBackcolor),
      context          : AppContext,
      onDismiss        : @escaping () -> Void
    ) {

      self.configuration    = configuration
      self.style            = style
      self.highlightPalette = highlightPalette
      self.context          = context
      self.onDismiss        = onDismiss
      self.button           = Button (
        bounds: BoxBounds ( row: 1, col: 1, width: MessageBoxOverlay.buttonWidth(for: configuration.text), height: 1 ),
        text  : configuration.text,
        style : style
      )
      self.isArmed          = true
    }

    var minimumWidth: Int { button.minimumWidth }
    var activationKey: TerminalInput.ControlKey { configuration.activationKey }

    func render ( in size: winsize, bounds: BoxBounds, isHighlighted: Bool ) -> [AnsiSequence]? {

      button.bounds = bounds

      let foreground = isHighlighted ? highlightPalette.foreground : style.foreground
      let background = isHighlighted ? highlightPalette.background : style.background

      return button.render ( in: size, foreground: foreground, background: background )
    }

    func dismiss() {
      isArmed = false
    }

    func activate() -> Bool {

      guard isArmed else { return false }
      dismiss()
      onDismiss()
      configuration.handler?(context)
      return true
    }
  }

  // Cache MessageBox layout results so the overlay can cheaply detect
  // geometry changes and only repaint the expensive body when needed.
  final class LayoutCache {

    private var cachedLayout      : MessageBox.Layout?
    private var needsFullRedraw   : Bool
    private var didRenderLastPass : Bool

    init() {
      cachedLayout      = nil
      needsFullRedraw   = true
      didRenderLastPass = false
    }

    var layout : MessageBox.Layout? { cachedLayout }
    var bounds : BoxBounds?        { cachedLayout?.bounds }

    func invalidate() {
      cachedLayout      = nil
      needsFullRedraw   = true
      didRenderLastPass = false
    }

    func refresh ( for messageBox: MessageBox, in size: winsize ) -> MessageBox.Layout? {

      guard let layout = messageBox.layout(in: size) else {
        invalidate()
        return nil
      }

      if !didRenderLastPass {
        needsFullRedraw = true
      }

      if let cached = cachedLayout {
        if MessageBoxOverlay.layout(layout, matches: cached) == false {
          needsFullRedraw = true
        }
      } else {
        needsFullRedraw = true
      }

      cachedLayout = layout
      return layout
    }

    func consumeNeedsFullRedraw() -> Bool {
      let shouldRedraw = needsFullRedraw
      needsFullRedraw  = false
      return shouldRedraw
    }

    func markDidRender() {
      didRenderLastPass = true
    }

    func markRenderFailed() {
      didRenderLastPass = false
      needsFullRedraw   = true
    }
  }

  // Isolate footer layout, rendering, and input handling so the overlay can
  // orchestrate the message body without micromanaging button geometry.
  final class Footer {

    private var buttonControllers  : [ButtonController]
    private var dirtyButtonIndices : Set<Int>
    private var activeIndex        : Int
    private let baseStyle          : ElementStyle
    private let dismissHandler     : () -> Void
    private let onUpdate           : ((Bool) -> Void)?
    private let minimumButtonWidth : Int
    let keyHandler                 : KeyHandler
    private var didPopKeyHandler   : Bool

    init(
      buttons          : [MessageBoxButton],
      style            : ElementStyle,
      highlightPalette : (foreground: ANSIForecolor, background: ANSIBackcolor),
      context          : AppContext,
      onDismiss        : @escaping () -> Void,
      onUpdate         : ((Bool) -> Void)?
    ) {

      let computedMinimumWidth = buttons.reduce(0) { width, config in
        width + MessageBoxOverlay.buttonWidth(for: config.text)
      }

      self.buttonControllers = []
      self.dirtyButtonIndices = Set<Int>()
      self.activeIndex        = 0
      self.baseStyle          = style
      self.dismissHandler     = onDismiss
      self.onUpdate           = onUpdate
      self.minimumButtonWidth = computedMinimumWidth
      self.keyHandler         = KeyHandler()
      self.didPopKeyHandler   = false

      self.buttonControllers = buttons.map { config in
        ButtonController(
          configuration    : config,
          style            : style,
          highlightPalette : highlightPalette,
          context          : context,
          onDismiss        : { [weak self] in self?.dismiss() }
        )
      }
      self.dirtyButtonIndices = Set(self.buttonControllers.indices)

      configureKeyHandler()
    }

    static func minimumInteriorWidth ( for buttons: [MessageBoxButton] ) -> Int {

      guard !buttons.isEmpty else { return 0 }

      let labelWidth = buttons.reduce(0) { width, config in
        width + MessageBoxOverlay.buttonWidth(for: config.text)
      }

      // The message body can wrap but the controls cannot vanish, so favour the
      // button row when reserving space for the overlay. With buttons now drawn
      // directly within the dialog interior we only need to reserve the raw
      // button widths.
      return labelWidth
    }

    var debugActiveIndex: Int { activeIndex }

    func invalidate() {
      dirtyButtonIndices = Set(buttonControllers.indices)
    }

    func render ( in size: winsize, layout: MessageBox.Layout, isFullRedraw: Bool ) -> [TUIElement] {

      guard !buttonControllers.isEmpty else { return [] }

      let bounds        = layout.bounds
      let interiorWidth = bounds.width - 2

      guard minimumButtonWidth <= interiorWidth else {
        // Logging the refusal makes it obvious why callers lose their buttons; the guard only fires when
        // the dialog itself is narrower than the button row so nothing could render safely.
        log("MessageBoxOverlay: skipping buttons, minimum width \(minimumButtonWidth) exceeds interior width \(interiorWidth)")
        return []
      }

      let gapCount     = max(buttonControllers.count - 1, 0)
      let availableGap = max(0, interiorWidth - minimumButtonWidth)
      // Prefer to preserve the existing two-column gutter, but collapse it evenly
      // across the row when space runs tight so every button can still render.
      let spacing      = gapCount > 0 ? min(2, availableGap / gapCount) : 0
      let buttonRow    = bounds.row + bounds.height - 2

      // Centre the button row while keeping the controls on the same baseline as the
      // rule above. Any slack that remains after spacing is split across the leading
      // and trailing gutters so the row stays visually balanced without introducing
      // extra vertical padding. The trailing side may end up one column wider when
      // the slack is odd, which matches how most text UIs centre short lines.
      let occupiedWidth = minimumButtonWidth + spacing * gapCount
      let slack         = max(0, interiorWidth - occupiedWidth)
      let startCol      = bounds.col + 1 + slack / 2

      var elements: [TUIElement] = []

      if isFullRedraw {
        // Paint a horizontal rule so the footer reads as a distinct control row without
        // reinstating the nested frame. We reuse the dialog palette to keep the rule in
        // lock-step with theme changes.
        let ruleRow     = buttonRow - 1
        let ruleStartCol = bounds.col + 1
        let ruleBounds  = BoxBounds ( row: ruleRow, col: ruleStartCol, width: interiorWidth, height: 1 )
        let ruleSequences: [AnsiSequence] = [
          .hideCursor,
          .moveCursor ( row: ruleRow, col: ruleStartCol ),
          .backcolor  ( baseStyle.background ),
          .forecolor  ( baseStyle.foreground ),
          .box        ( .horiz(interiorWidth) ),
        ]
        elements.append ( TUIElement ( bounds: ruleBounds, sequences: ruleSequences ) )
        // The dialog body just repainted, so refresh every button to keep their
        // alignment anchored to the new bounds.
        markAllButtonsDirty()
      }

      var currentCol = startCol

      for (index, controller) in buttonControllers.enumerated() {

        let buttonBounds = BoxBounds(
          row   : buttonRow,
          col   : currentCol,
          width : controller.minimumWidth,
          height: 1
        )

        if dirtyButtonIndices.contains(index), let buttonSequences = controller.render ( in: size, bounds: buttonBounds, isHighlighted: index == activeIndex ) {
          elements.append ( TUIElement ( bounds: buttonBounds, sequences: buttonSequences ) )
        }

        currentCol += controller.minimumWidth + spacing
      }

      dirtyButtonIndices.removeAll()

      return elements
    }

    func handle ( _ input: TerminalInput.Input ) -> Bool {
      keyHandler.handle ( input )
    }

    private func markButtonsDirty ( _ indexes: [Int] ) {
      for index in indexes where buttonControllers.indices.contains(index) {
        dirtyButtonIndices.insert(index)
      }
    }

    private func markAllButtonsDirty() {
      dirtyButtonIndices = Set(buttonControllers.indices)
    }

    private func configureKeyHandler() {

      let controlHandlers: KeyHandler.ControlInputHandler = [
        .cursor ( .left  ) : { [weak self] in
          self?.moveActiveIndex ( by: -1 ) ?? false
        },
        .cursor ( .right ) : { [weak self] in
          self?.moveActiveIndex ( by: 1 ) ?? false
        },
        .key    ( .ESC   ) : { [weak self] in
          self?.dismiss()
          return true
        }
      ]

      var globalHandlers: KeyHandler.ControlInputHandler = [:]

      for controller in buttonControllers {
        let key = controller.activationKey
        let keyInput = TerminalInput.Input.key ( key )

        globalHandlers[keyInput] = { [weak self] in
          self?.activateSelectedButton ( for: key ) ?? false
        }
      }

      // Installing everything as a single entry keeps overlay stack management
      // straightforward; the footer simply pushes once when it becomes active.
      keyHandler.pushHandler ( KeyHandler.HandlerTableEntry (
        control                     : controlHandlers,
        global                      : globalHandlers,
        swallowPrintableAfterEscape : true
      ) )
    }

    private func activateSelectedButton ( for key: TerminalInput.ControlKey ) -> Bool {

      guard buttonControllers.indices.contains ( activeIndex ) else { return false }

      let controller = buttonControllers[activeIndex]

      guard controller.activationKey == key else { return false }

      return controller.activate()
    }

    private func dismiss() {

      guard !didPopKeyHandler else { return }

      didPopKeyHandler = true

      // Clear every nested controller first so button-specific handlers disappear
      // before the overlay asks the manager to tear itself down.
      for controller in buttonControllers {
        controller.dismiss()
      }

      keyHandler.popHandler()
      dismissHandler()
    }

    deinit {
      if !didPopKeyHandler {
        keyHandler.popHandler()
      }
    }

    private func moveActiveIndex ( by offset: Int ) -> Bool {

      guard !buttonControllers.isEmpty else { return false }

      let previousIndex = activeIndex
      let candidate     = activeIndex + offset
      let clampedIndex  = min(max(candidate, 0), buttonControllers.count - 1)

      guard clampedIndex != previousIndex else { return false }

      activeIndex = clampedIndex
      markButtonsDirty ( [previousIndex, activeIndex] )
      onUpdate?( false )

      return true
    }
  }

  private let messageBox  : MessageBox
  private let layoutCache : LayoutCache
  private let footer      : Footer?
  let keyHandler          : KeyHandler

  // Reserve a blank row for the horizontal rule and another for the button row so
  // the divider never overlaps the message body.
  private static let trailingBlankLines = 2

  // Expose the highlight index for regression tests without widening the public surface.
  var debugActiveButtonIndex: Int { footer?.debugActiveIndex ?? 0 }

  var overlayBounds: BoxBounds? {
    layoutCache.bounds
  }

  init(
    message   : String,
    context   : AppContext,
    row       : Int?,
    col       : Int?,
    style     : ElementStyle,
    buttons   : [MessageBoxButton],
    onDismiss : @escaping () -> Void,
    onUpdate  : ((Bool) -> Void)?
  ) {

    var body = message
    if !body.hasSuffix("\n") {
      body += "\n"
    }

    if !buttons.isEmpty {

      // Reserve trailing rows for the divider and button strip so the labels can render
      // directly against the footer without leaking blank padding. Baking this into the
      // message string keeps the geometry stable regardless of the caller's copy length
      // while letting us paint the buttons as overlays.
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

    let minimumInteriorWidth = Footer.minimumInteriorWidth ( for: buttons )

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
    self.layoutCache = LayoutCache()

    if buttons.isEmpty {
      self.footer     = nil
      self.keyHandler = KeyHandler()
    } else {
      // Convert the base element style into a highlight palette so buttons stay
      // visually consistent with the rest of the overlay.
      let highlightPalette = ElementStyle.highlightPalette ( for: style )
      let footer = Footer(
        buttons          : buttons,
        style            : style,
        highlightPalette : highlightPalette,
        context          : context,
        onDismiss        : onDismiss,
        onUpdate         : onUpdate
      )
      self.footer     = footer
      self.keyHandler = footer.keyHandler
    }
  }

  func invalidateForFullRedraw() {
    layoutCache.invalidate()
    footer?.invalidate()
  }

  func render ( in size: winsize ) -> [AnsiSequence]? {

    guard let layout = layoutCache.refresh ( for: messageBox, in: size ) else {
      footer?.invalidate()
      return nil
    }

    var elements: [TUIElement] = []

    let isFullRedraw = layoutCache.consumeNeedsFullRedraw()

    if isFullRedraw {
      guard let boxSequences = messageBox.render(in: size) else {
        layoutCache.markRenderFailed()
        footer?.invalidate()
        return nil
      }
      elements.append ( TUIElement ( bounds: layout.bounds, sequences: boxSequences ) )
    }

    if let footer = footer {
      let footerElements = footer.render ( in: size, layout: layout, isFullRedraw: isFullRedraw )
      elements.append(contentsOf: footerElements)
    }

    guard let sequences = TUIElement.render ( elements, in: size ) else {
      layoutCache.markRenderFailed()
      footer?.invalidate()
      return nil
    }

    layoutCache.markDidRender()

    return sequences
  }

  func handle ( _ input: TerminalInput.Input ) -> Bool {
    keyHandler.handle ( input )
  }

  private static func buttonWidth(for text: String) -> Int {
    // Button labels are rendered as "[ text ]" so we add four characters to the
    // raw label length to account for the brackets and surrounding spaces.
    return text.count + 4
  }

  private static func layout(_ layout: MessageBox.Layout, matches cached: MessageBox.Layout) -> Bool {
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

final class SelectionListOverlay: Renderable, OverlayInputHandling, OverlayInvalidating, OverlayBoundsReporting {

  private let items             : [SelectionListItem]
  private let context           : AppContext
  private let row               : Int?
  private let col               : Int?
  private let style             : ElementStyle
  private let onSelect          : ((SelectionListItem) -> Void)?
  private let onDismiss         : () -> Void
  private let onUpdate          : ((Bool) -> Void)?
  private let highlightPalette  : (foreground: ANSIForecolor, background: ANSIBackcolor)

  private var activeIndex       : Int
  private var cachedBounds      : BoxBounds?
  private var needsFullRedraw   : Bool
  private var dirtyItemIndices  : Set<Int>
  private var didRenderLastPass : Bool
  private var isDismissed       : Bool
  let keyHandler                : KeyHandler

  var debugActiveIndex : Int { activeIndex }

  var overlayBounds       : BoxBounds? {
    cachedBounds
  }

  init (
    items    : [SelectionListItem],
    context  : AppContext,
    row      : Int?,
    col      : Int?,
    style    : ElementStyle,
    onSelect : ((SelectionListItem) -> Void)?,
    onDismiss: @escaping () -> Void,
    onUpdate : ((Bool) -> Void)?
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
    self.highlightPalette   = ElementStyle.highlightPalette ( for: style )
    self.keyHandler         = KeyHandler()

    configureKeyHandler()
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

    // Build a list of row elements that the renderer can flatten into ANSI output.
    var elements: [TUIElement] = []

    if needsFullRedraw {

      let element = BoxElement ( bounds: bounds, style: style )

      guard let boxSequences = Box ( element: element ).render ( in: size ) else {
        cachedBounds      = nil
        needsFullRedraw   = true
        didRenderLastPass = false
        markAllItemsDirty()
        return nil
      }

      elements.append ( TUIElement ( bounds: bounds, sequences: boxSequences ) )
      needsFullRedraw = false
      markAllItemsDirty()
    }

    guard !dirtyItemIndices.isEmpty else {
      didRenderLastPass = true
      return TUIElement.render ( elements, in: size )
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

      let rowBounds = BoxBounds ( row: textStartRow + index, col: textStartCol, width: clampedWidth, height: 1 )
      let rowStyle  = ElementStyle ( foreground: foreground, background: background )
      let element   = TUIElement.textRow ( bounds: rowBounds, style: rowStyle, text: padded, includeHideCursor: false )
      elements.append ( element )
    }

    dirtyItemIndices.removeAll()
    didRenderLastPass = true

    return TUIElement.render ( elements, in: size )
  }

  private func layout ( in size: winsize ) -> BoxBounds? {

    let rows    = Int(size.ws_row)
    let columns = Int(size.ws_col)

    guard rows > 0 && columns > 0 else { return nil }

    let interiorWidth = SelectionListOverlay.minimumInteriorWidth ( for: items )
    let width         = interiorWidth + 2
    let height        = items.count + 2

    guard width  <= columns else { return nil }
    guard height <= rows    else { return nil }

    let centeredTop  = max(1, ((rows    - height) / 2) + 1)
    let centeredLeft = max(1, ((columns - width ) / 2) + 1)
    let maxTop       = max(1, rows    - height + 1)
    let maxLeft      = max(1, columns - width  + 1)

    let top  : Int
    let left : Int

    if let anchorRow = row {
      // Anchor requests are clamped so overlays slide on-screen instead of failing layout outright.
      top = min(max(anchorRow, 1), maxTop)
    } else {
      top = centeredTop
    }

    if let anchorCol = col {
      // Horizontal anchors are clamped for the same reason so the overlay stays fully visible.
      left = min(max(anchorCol, 1), maxLeft)
    } else {
      left = centeredLeft
    }

    let bottom = top  + height - 1
    let right  = left + width  - 1

    guard top    >= 1       else { return nil }
    guard left   >= 1       else { return nil }
    guard bottom <= rows    else { return nil }
    guard right  <= columns else { return nil }

    return BoxBounds ( row: top, col: left, width: width, height: height )
  }

  func handle ( _ input: TerminalInput.Input ) -> Bool {

    if isDismissed {
      // Tests expect ESC to keep reading as handled even after dismissal so the
      // overlay stack continues to swallow option-key chords that arrive in the
      // same burst as the exit key.
      if case .key ( let key ) = input, key == .ESC {
        return true
      }
      return false
    }

    return keyHandler.handle ( input )
  }

  private func configureKeyHandler() {
    let controlHandlers: KeyHandler.ControlInputHandler = [
      .cursor ( .up    ) : { [weak self] in
        self?.moveSelection ( by: -1 ) ?? false
      },
      .cursor ( .down  ) : { [weak self] in
        self?.moveSelection ( by: 1 ) ?? false
      },
      .key    ( .RETURN ) : { [weak self] in
        self?.activateSelection() ?? false
      },
      .key    ( .ESC   ) : { [weak self] in
        self?.dismiss()
        return true
      }
    ]

    let bytesHandler: KeyHandler.BytesInputHandler = { [weak self] bytes in
      guard let overlay = self else { return false }

      switch bytes {
        case .ascii   ( let data ),
             .unicode ( let data ) :
          guard data.contains ( 0x0d ) else { return false }
          return overlay.activateSelection()
      }
    }

    keyHandler.pushHandler ( KeyHandler.HandlerTableEntry (
      control                     : controlHandlers,
      bytes                       : bytesHandler,
      swallowPrintableAfterEscape : true
    ) )
  }

  private func moveSelection ( by offset: Int ) -> Bool {

    guard !items.isEmpty else { return false }

    let previousIndex = activeIndex
    let candidate     = activeIndex + offset
    let clampedIndex  = min(max(candidate, 0), items.count - 1)

    guard clampedIndex != previousIndex else { return false }

    activeIndex = clampedIndex
    markItemsDirty ( [previousIndex, activeIndex] )
    onUpdate?( false )

    return true
  }

  private func activateSelection () -> Bool {
    guard items.indices.contains ( activeIndex ) else { return false }
    guard !isDismissed else { return false }

    let item = items[activeIndex]
    onSelect? ( item )
    // Pass through the broader application context so selection handlers can
    // trigger follow-up overlays or logging without reaching back into global state.
    item.handler? ( context )
    return dismiss()
  }

  @discardableResult
  private func dismiss () -> Bool {
    guard !isDismissed else { return false }
    isDismissed = true
    keyHandler.popHandler()
    onDismiss()
    return true
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

  private static func bounds ( _ bounds: BoxBounds, matches cached: BoxBounds? ) -> Bool {
    guard let cached = cached else { return false }

    return cached.row    == bounds.row
        && cached.col    == bounds.col
        && cached.width  == bounds.width
        && cached.height == bounds.height
  }
}
