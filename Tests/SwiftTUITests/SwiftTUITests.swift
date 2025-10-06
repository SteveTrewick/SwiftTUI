import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif
import XCTest
@testable import SwiftTUI

private extension AppContext {

    // Tests spin up the application context without caring about input/output wiring.
    // Provide local shims so the fixtures stay succinct while still satisfying the
    // designated initializer that production code uses.
    convenience init(overlays: OverlayManager) {
        self.init(style: ElementStyle(), overlays: overlays)
    }

    convenience init() {
        self.init(style: ElementStyle())
    }
}

final class CircularBufferTests: XCTestCase {

    func testCircularBufferFullnessTransitions() {
        var buffer = CircularBuffer<Int>(capacity: 3)

        XCTAssertEqual(buffer.filled, 0)
        XCTAssertFalse(buffer.isFull)

        buffer.put(1)
        XCTAssertEqual(buffer.filled, 1)
        XCTAssertFalse(buffer.isFull)

        buffer.put(2)
        XCTAssertEqual(buffer.filled, 2)
        XCTAssertFalse(buffer.isFull)

        buffer.put(3)
        XCTAssertEqual(buffer.filled, 3)
        XCTAssertTrue(buffer.isFull)

        _ = buffer.get()
        XCTAssertEqual(buffer.filled, 2)
        XCTAssertFalse(buffer.isFull)

        buffer.put(4)
        XCTAssertEqual(buffer.filled, 3)
        XCTAssertTrue(buffer.isFull)

        _ = buffer.get()
        XCTAssertEqual(buffer.filled, 2)
        XCTAssertFalse(buffer.isFull)

        _ = buffer.get()
        XCTAssertEqual(buffer.filled, 1)
        XCTAssertFalse(buffer.isFull)

        _ = buffer.get()
        XCTAssertEqual(buffer.filled, 0)
        XCTAssertFalse(buffer.isFull)

        buffer.put(5)
        buffer.put(6)
        buffer.put(7)
        XCTAssertTrue(buffer.isFull)

        buffer.put(8)
        XCTAssertTrue(buffer.isFull)
        XCTAssertEqual(buffer.filled, 3)

        _ = buffer.get()
        XCTAssertEqual(buffer.filled, 2)
        XCTAssertFalse(buffer.isFull)
    }
}

final class LineBufferScrollTests: XCTestCase {

    func testFetchSpanImmediatelyAfterInitializationReturnsEmptyLines() {
        var buffer = LineBuffer(capacity: 4, breakchar: "\n")

        let lines = buffer.fetch(span: 2)

        XCTAssertEqual(lines, ["", ""])
    }

    func testFetchTrimsTrailingBreakCharactersOnCompletedLines() {
        var buffer = LineBuffer(capacity: 4, breakchar: "\n")
        buffer.push(chars: "line1\nline2\npartial")

        let lines = buffer.fetch(span: 3)

        XCTAssertEqual(lines, ["line1", "line2", "partial"])
    }

    func testScrollUpClampsWithinAvailableHistory() {
        var buffer = LineBuffer(capacity: 8, breakchar: "\n")
        buffer.push(chars: "one\ntwo\nthree\nfour\n")

        buffer.scrollUp(span: 2, 10)

        XCTAssertEqual(buffer.offset, 3)
    }

    func testScrollUpClampsToZeroWhenSpanExceedsHistory() {
        var buffer = LineBuffer(capacity: 4, breakchar: "\n")
        buffer.push(chars: "one\ntwo\n")

        buffer.scrollUp(span: 5, 3)

        XCTAssertEqual(buffer.offset, 0)
    }
}

final class TerminalInputPrintableSequenceTests: XCTestCase {

    func testTranslateEscFollowedByLowercaseLetterProducesAsciiInput() {
        let result = TerminalInput.translate(bytes: Data([0x1B, 0x66]))

        switch result {
        case .success(let inputs):
            XCTAssertEqual(inputs.count, 2)

            guard case .key(.ESC) = inputs.first else {
                return XCTFail("Expected ESC key prefix for ESC+f sequence")
            }

            guard case let .ascii(data) = inputs.last else {
                return XCTFail("Expected ascii input for ESC+f sequence")
            }

            XCTAssertEqual(data, Data([0x66]))

        case .failure(let trace):
            XCTFail("Unexpected failure for ESC+f sequence: \(trace)")
        }
    }

    func testTranslateEscFollowedByUppercaseLetterProducesAsciiInput() {
        let result = TerminalInput.translate(bytes: Data([0x1B, 0x41]))

        switch result {
        case .success(let inputs):
            XCTAssertEqual(inputs.count, 2)

            guard case .key(.ESC) = inputs.first else {
                return XCTFail("Expected ESC key prefix for ESC+A sequence")
            }

            guard case let .ascii(data) = inputs.last else {
                return XCTFail("Expected ascii input for ESC+A sequence")
            }

            XCTAssertEqual(data, Data([0x41]))

        case .failure(let trace):
            XCTFail("Unexpected failure for ESC+A sequence: \(trace)")
        }
    }
}

final class TerminalInputTranslateTests: XCTestCase {

    func testTranslateHandlesTruncatedCursorResponse() {
        let context = TerminalInput.ParserContext()
        let decoder = TerminalInput.Decoder(context: context)

        switch decoder.feed(Data([0x1b])) {
        case .failure(let trace):
            XCTFail("Unexpected failure while buffering escape prefix: \(trace)")
        case .success(let outputs):
            XCTAssertTrue(outputs.isEmpty)
        }

        switch decoder.feed(Data("[12;4R".utf8)) {
        case .failure(let trace):
            XCTFail("Expected buffered response to resolve, saw error: \(trace)")
        case .success(let outputs):
            XCTAssertEqual(outputs, [.response(.CURSOR(row: 12, column: 4))])
        }

        switch decoder.flush() {
        case .failure(let trace):
            XCTFail("Decoder should be grounded after response, saw: \(trace)")
        case .success(let trailing):
            XCTAssertTrue(trailing.isEmpty)
        }
    }

    func testDecoderEmitsTokensAcrossChunkBoundaries() {
        let context = TerminalInput.ParserContext()
        let decoder = TerminalInput.Decoder(context: context)
        var collected: [TerminalInput.Input] = []

        func appendChunk(_ bytes: [UInt8], file: StaticString = #filePath, line: UInt = #line) {
            switch decoder.feed(Data(bytes)) {
            case .failure(let trace):
                XCTFail("Unexpected decoder failure for chunk \(bytes): \(trace)", file: file, line: line)
            case .success(let outputs):
                collected.append(contentsOf: outputs)
            }
        }

        // Control byte arrives on its own chunk, immediately producing a key token.
        appendChunk([0x0d])

        // ASCII text accumulates until we explicitly flush the decoder in the ground state.
        appendChunk([0x41])

        switch decoder.flush() {
        case .failure(let trace):
            XCTFail("Flush should release buffered ASCII, saw error: \(trace)")
        case .success(let trailing):
            collected.append(contentsOf: trailing)
        }

        // Cursor response is fragmented across multiple chunks; keep feeding until we see the final byte.
        appendChunk([0x1b])
        appendChunk(Array("[12".utf8))
        appendChunk(Array(";40R".utf8))

        // UTF-8 scalar is sliced into individual bytes to ensure continuation tracking.
        appendChunk([0xe2])
        appendChunk([0x82])
        appendChunk([0xac])

        switch decoder.flush() {
        case .failure(let trace):
            XCTFail("Final flush should succeed after complete sequences: \(trace)")
        case .success(let trailing):
            collected.append(contentsOf: trailing)
        }

        let expected: [TerminalInput.Input] = [
            .key(.RETURN),
            .ascii(Data([0x41])),
            .response(.CURSOR(row: 12, column: 40)),
            .unicode(Data([0xe2, 0x82, 0xac]))
        ]

        XCTAssertEqual(collected, expected)
    }

    func testDecoderEmitsMetaSequenceAcrossChunks() {
        let context = TerminalInput.ParserContext()
        let decoder = TerminalInput.Decoder(context: context)

        // ESC prefix is delivered first to make sure the decoder buffers it until printable data arrives.
        switch decoder.feed(Data([0x1b])) {
        case .failure(let trace):
            XCTFail("Unexpected failure buffering ESC prefix: \(trace)")
        case .success(let outputs):
            XCTAssertTrue(outputs.isEmpty)
        }

        switch decoder.feed(Data([0x66])) {
        case .failure(let trace):
            XCTFail("Meta sequence should resolve when printable suffix arrives: \(trace)")
        case .success(let outputs):
            XCTAssertEqual(outputs, [.key(.ESC), .ascii(Data([0x66]))])
        }

        switch decoder.flush() {
        case .failure(let trace):
            XCTFail("Meta sequence should leave decoder grounded, saw: \(trace)")
        case .success(let trailing):
            XCTAssertTrue(trailing.isEmpty)
        }
    }

    func testDecoderSurfacesMalformedUTF8WithoutDroppingBuffer() {
        let context = TerminalInput.ParserContext()
        let decoder = TerminalInput.Decoder(context: context)

        // Start a UTF-8 scalar with a valid lead byte so the decoder tracks the expected length.
        switch decoder.feed(Data([0xe2])) {
        case .failure(let trace):
            XCTFail("Unexpected failure receiving lead byte: \(trace)")
        case .success(let outputs):
            XCTAssertTrue(outputs.isEmpty)
        }

        switch decoder.feed(Data([0x20])) {
        case .success(let outputs):
            XCTFail("Invalid continuation byte should not succeed, got: \(outputs)")
        case .failure(let trace):
            // Retain the buffered lead byte so diagnostics can recover context.
            XCTAssertEqual(decoder.unicodeBuffer, Data([0xe2]))
            XCTAssertTrue(String(describing: trace).contains("invalid utf8 continuation"))
        }
    }

    func testDecoderReportsUnterminatedOSCWithoutLosingBufferedText() {
        let context = TerminalInput.ParserContext()
        let decoder = TerminalInput.Decoder(context: context)

        // Accumulate printable text so we can ensure it gets emitted before the OSC failure.
        switch decoder.feed(Data("hi".utf8)) {
        case .failure(let trace):
            XCTFail("Unexpected failure buffering text: \(trace)")
        case .success(let outputs):
            XCTAssertEqual(outputs, [.unicode(Data("hi".utf8))])
        }

        switch decoder.feed(Data([0x1b, 0x5d, 0x30])) {
        case .failure(let trace):
            XCTFail("OSC prologue should keep streaming, saw: \(trace)")
        case .success(let outputs):
            // Subsequent chunk should not emit anything until the OSC terminator arrives.
            XCTAssertTrue(outputs.isEmpty)
        }

        switch decoder.flush() {
        case .success(let outputs):
            XCTFail("Expected unterminated OSC to fail, saw trailing outputs: \(outputs)")
        case .failure(let trace):
            XCTAssertTrue(String(describing: trace).contains("unterminated control sequence"))
            XCTAssertEqual(decoder.escapeBuffer, Data([0x1b, 0x5d, 0x30]))
        }
    }
}

final class MessageBoxOverlayRenderingTests: XCTestCase {

    func testMessageBoxButtonsRenderWhenSpacingCollapses() {
        let manager = OverlayManager()
        let context = AppContext(overlays: manager)
        let buttons = [
            MessageBoxButton(text: "YOK"),
            MessageBoxButton(text: "NOK"),
            MessageBoxButton(text: "WTF")
        ]

        manager.drawMessageBox(
          "Tight\nDialog",
          context     : context,
          row         : 2,
          col         : 2,
          style       : ElementStyle(),
          buttonText  : "OK",
          activationKey: .RETURN,
          buttons      : buttons
        )

        guard let overlay = manager.activeOverlays().last else {
            return XCTFail("Expected message box overlay")
        }

        let size = winsize(ws_row: 24, ws_col: 25, ws_xpixel: 0, ws_ypixel: 0)

        guard let sequences = overlay.render(in: size) else {
            return XCTFail("Expected render output for message box overlay")
        }

        // Collapse the render output down to the string payloads so the assertions
        // read naturally and focus on the buttons we expect to see.
        let buttonStrings = sequences.compactMap { sequence -> String? in
            switch sequence {
            case .text(let text):
                return text
            case .dim(let text):
                return text
            default:
                return nil
            }
        }

        ["[ YOK ]", "[ NOK ]", "[ WTF ]"].forEach { label in
            XCTAssertTrue(
                buttonStrings.contains(label),
                "Missing \(label) in rendered output"
            )
        }
    }

    func testMessageBoxAdvancesHighlightForBatchedCursorInputs() {
        let manager = OverlayManager()
        let context = AppContext(overlays: manager)
        let buttons = [
            MessageBoxButton(text: "Left"),
            MessageBoxButton(text: "Middle"),
            MessageBoxButton(text: "Right")
        ]

        manager.drawMessageBox(
          "Cursor Walk",
          context     : context,
          row         : 1,
          col         : 1,
          style       : ElementStyle(),
          buttonText  : "OK",
          activationKey: .RETURN,
          buttons     : buttons
        )

        guard let overlay = manager.activeOverlays().last as? MessageBoxOverlay else {
            return XCTFail("Expected message box overlay")
        }

        // Batch cursor events to reproduce the regression that skipped later inputs.
        let handled = manager.handle(inputs: [.cursor(.right), .cursor(.right)])

        XCTAssertTrue(handled, "Expected overlay to handle cursor input batch")
        XCTAssertEqual(overlay.debugActiveButtonIndex, 2, "Highlight should advance for each cursor event")
    }

    func testMessageBoxSwallowsUnhandledInputWhileActive() {
        let manager = OverlayManager()
        let context = AppContext(overlays: manager)

        manager.drawMessageBox(
          "Modal",
          context     : context
        )

        // Use a control key the default button ignores so we can assert that the
        // overlay still consumes the keystroke instead of letting it bubble into
        // background UI such as menus.
        let handled = manager.handle(inputs: [.key(.TAB)])

        XCTAssertTrue(handled, "Focused overlays should swallow unhandled input")
    }

    func testMessageBoxRedrawsButtonsOnlyWhenHighlightChanges() {
        let manager = OverlayManager()
        let context = AppContext(overlays: manager)

        manager.drawMessageBox(
          "Smooth",
          context     : context,
          row         : 1,
          col         : 1,
          style       : ElementStyle(),
          buttonText  : "OK",
          activationKey: .RETURN,
          buttons     : [
            MessageBoxButton(text: "First"),
            MessageBoxButton(text: "Second")
          ]
        )

        guard let overlay = manager.activeOverlays().last as? MessageBoxOverlay else {
            return XCTFail("Expected message box overlay")
        }

        let size = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)

        // Prime the overlay so the initial draw caches the full message box.
        guard let initialSequences = overlay.render(in: size) else {
            return XCTFail("Expected initial render output")
        }

        XCTAssertTrue(initialSequences.contains(where: { sequence in
            if case .text(let text) = sequence { return text.contains("Smooth") }
            return false
        }), "Initial render should include the message body")

        XCTAssertTrue(overlay.handle(.cursor(.right)), "Cursor input should move the highlight")

        guard let updateSequences = overlay.render(in: size) else {
            return XCTFail("Expected button update output")
        }

        XCTAssertFalse(updateSequences.contains(where: { sequence in
            if case .text(let text) = sequence { return text.contains("Smooth") }
            return false
        }), "Highlight updates should not repaint the message body")

        let buttonStrings = updateSequences.compactMap { sequence -> String? in
            switch sequence {
            case .text(let text):
                return text
            case .dim(let text):
                return text
            default:
                return nil
            }
        }

        ["[ First ]", "[ Second ]"].forEach { label in
            XCTAssertTrue(
                buttonStrings.contains(label),
                "Expected button redraw for \(label)"
            )
        }
    }

    func testMessageBoxButtonsAdoptHighlightPalette() {
        let manager = OverlayManager()
        let context = AppContext(overlays: manager)
        let style = ElementStyle(foreground: .white, background: .black)
        let highlightPalette = ElementStyle.highlightPalette(for: style)

        manager.drawMessageBox(
          "Palette",
          context     : context,
          row         : 1,
          col         : 1,
          style       : style,
          buttonText  : "OK",
          activationKey: .RETURN,
          buttons     : [
            MessageBoxButton(text: "First"),
            MessageBoxButton(text: "Second")
          ]
        )

        guard let overlay = manager.activeOverlays().last as? MessageBoxOverlay else {
            return XCTFail("Expected message box overlay")
        }

        let size = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)

        guard let initialSequences = overlay.render(in: size) else {
            return XCTFail("Expected initial render output")
        }

        // The first button is highlighted on registration, so it should use the
        // highlight palette while the second button retains the base style.
        let firstInitialColors = buttonPalettes(for: "[ First ]", in: initialSequences)
        XCTAssertFalse(firstInitialColors.isEmpty, "Expected render output for the first button")
        XCTAssertTrue(
            firstInitialColors.allSatisfy { palette in
                palette.foreground == highlightPalette.foreground && palette.background == highlightPalette.background
            },
            "Highlighted button should render with the highlight palette"
        )

        let secondInitialColors = buttonPalettes(for: "[ Second ]", in: initialSequences)
        XCTAssertFalse(secondInitialColors.isEmpty, "Expected render output for the second button")
        XCTAssertTrue(
            secondInitialColors.allSatisfy { palette in
                palette.foreground == style.foreground && palette.background == style.background
            },
            "Inactive button should render with the base palette"
        )

        XCTAssertTrue(overlay.handle(.cursor(.right)), "Cursor input should move the highlight")

        guard let updateSequences = overlay.render(in: size) else {
            return XCTFail("Expected highlight update output")
        }

        // After the highlight moves the palettes should swap so the updated row
        // continues to render with the highlight colours.
        let firstUpdateColors = buttonPalettes(for: "[ First ]", in: updateSequences)
        XCTAssertFalse(firstUpdateColors.isEmpty, "Expected update output for the first button")
        XCTAssertTrue(
            firstUpdateColors.allSatisfy { palette in
                palette.foreground == style.foreground && palette.background == style.background
            },
            "First button should revert to the base palette after losing the highlight"
        )

        let secondUpdateColors = buttonPalettes(for: "[ Second ]", in: updateSequences)
        XCTAssertFalse(secondUpdateColors.isEmpty, "Expected update output for the second button")
        XCTAssertTrue(
            secondUpdateColors.allSatisfy { palette in
                palette.foreground == highlightPalette.foreground && palette.background == highlightPalette.background
            },
            "Second button should adopt the highlight palette when selected"
        )
    }

    private func buttonPalettes(for label: String, in sequences: [AnsiSequence]) -> [(foreground: ANSIForecolor, background: ANSIBackcolor)] {
        var palettes: [(foreground: ANSIForecolor, background: ANSIBackcolor)] = []

        for (index, sequence) in sequences.enumerated() {
            guard case .text(let text) = sequence, text == label else { continue }
            guard index >= 2 else { continue }

            guard case let .forecolor(foreground) = sequences[index - 1] else { continue }
            guard case let .backcolor(background) = sequences[index - 2] else { continue }

            palettes.append((foreground, background))
        }

        return palettes
    }

    func testMessageBoxRegistrationEmitsUpdateChange() {
        let manager = OverlayManager()
        let context = AppContext(overlays: manager)
        var capturedChanges: [OverlayManager.Change] = []

        // Capture the overlay lifecycle so the helper can be validated end-to-end.
        manager.onChange = { change in
            capturedChanges.append(change)
        }

        manager.drawMessageBox(
          "Lifecycle",
          context     : context
        )

        XCTAssertEqual(manager.activeOverlays().count, 1, "Message box should register an overlay")

        guard let change = capturedChanges.last else {
            return XCTFail("Expected registration change notification")
        }

        if case .updated(let needsBaseRedraw) = change {
            XCTAssertTrue(needsBaseRedraw, "Message box should default to a full redraw")
        } else {
            XCTFail("Expected updated change for message box registration")
        }
    }

    func testSelectionListRendersItemsWithHighlight () {
        let manager = OverlayManager()
        let context = AppContext(overlays: manager)

        manager.drawSelectionList (
          [
            SelectionListItem ( text: "One" ),
            SelectionListItem ( text: "Two" )
          ],
          context  : context,
          row      : 2,
          col      : 2,
          style    : ElementStyle ( foreground: .white, background: .black ),
          onSelect : nil,
          onDismiss: nil
        )

        guard let overlay = manager.activeOverlays().last as? SelectionListOverlay else {
            return XCTFail("Expected selection list overlay")
        }

        let size = winsize ( ws_row: 12, ws_col: 40, ws_xpixel: 0, ws_ypixel: 0 )

        guard let sequences = overlay.render ( in: size ) else {
            return XCTFail("Expected render output for selection list overlay")
        }

        XCTAssertTrue(
            sequences.contains ( where: { sequence in
                if case .backcolor(let color) = sequence { return color == .white }
                return false
            }),
            "Active row should use highlight background"
        )

        let rowStrings = sequences.compactMap { sequence -> String? in
            if case .text(let text) = sequence { return text }
            return nil
        }

        [" One ", " Two "].forEach { label in
            XCTAssertTrue(rowStrings.contains ( label ), "Expected rendered row for \(label)")
        }
    }

    func testSelectionListMovesHighlightWithArrowKeys () {
        let context = AppContext()
        let overlay = SelectionListOverlay (
            items    : [
                SelectionListItem ( text: "First" ),
                SelectionListItem ( text: "Second" ),
                SelectionListItem ( text: "Third" )
            ],
            context  : context,
            row      : 1,
            col      : 1,
            style    : ElementStyle(),
            onSelect : nil,
            onDismiss: {},
            onUpdate : nil
        )

        let size = winsize ( ws_row: 10, ws_col: 40, ws_xpixel: 0, ws_ypixel: 0 )
        XCTAssertNotNil(overlay.render ( in: size ), "Initial render should succeed")

        XCTAssertTrue(overlay.handle ( .cursor ( .down ) ), "Down arrow should move highlight")
        XCTAssertEqual(overlay.debugActiveIndex, 1, "Highlight should advance to the next row")

        XCTAssertTrue(overlay.handle ( .cursor ( .up ) ), "Up arrow should move highlight")
        XCTAssertEqual(overlay.debugActiveIndex, 0, "Highlight should move back to the first row")
    }

    func testSelectionListDismissalEmitsClearChange () {
        let manager = OverlayManager()
        let context = AppContext(overlays: manager)
        var capturedChanges: [OverlayManager.Change] = []

        manager.onChange = { change in
            capturedChanges.append(change)
        }

        manager.drawSelectionList (
          [SelectionListItem ( text: "Single" )],
          context  : context
        )

        XCTAssertEqual(manager.activeOverlays().count, 1, "Selection list should register an overlay")

        guard let overlay = manager.activeOverlays().last as? SelectionListOverlay else {
            return XCTFail("Expected selection list overlay instance")
        }

        XCTAssertTrue(overlay.handle ( .key ( .ESC ) ), "ESC should dismiss selection list")
        XCTAssertTrue(manager.activeOverlays().isEmpty, "Dismissed selection list should clear overlays")

        XCTAssertEqual(capturedChanges.count, 2, "Registration and dismissal should emit change notifications")

        if capturedChanges.count >= 2 {
            if case .updated(let needsBaseRedraw) = capturedChanges[0] {
                XCTAssertTrue(needsBaseRedraw, "Selection list registration should request full redraw")
            } else {
                XCTFail("Expected registration to emit updated change")
            }

            if case .cleared = capturedChanges[1] {
                // Success.
            } else {
                XCTFail("Expected dismissal to emit cleared change")
            }
        }
    }

    func testSelectionListDismissesOnEscape () {
        var dismissCount = 0
        let context = AppContext()
        let overlay = SelectionListOverlay (
            items    : [SelectionListItem ( text: "Only" )],
            context  : context,
            row      : 1,
            col      : 1,
            style    : ElementStyle(),
            onSelect : nil,
            onDismiss: { dismissCount += 1 },
            onUpdate : nil
        )

        XCTAssertTrue(overlay.handle ( .key ( .ESC ) ), "ESC should dismiss the overlay")
        XCTAssertEqual(dismissCount, 1, "Dismiss handler should run once")

        XCTAssertTrue(overlay.handle ( .key ( .ESC ) ), "Further ESC presses are absorbed")
        XCTAssertEqual(dismissCount, 1, "Dismiss handler should not fire again")
    }
}

final class RendererRenderFrameTests: XCTestCase {

    func testRenderFrameInvokesOverlayInvalidationOnClear() {
        let renderer = Renderer()
        let size = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
        let expectation = expectation(description: "Expected overlay invalidation on clear")

        renderer.renderFrame(
            base        : [],
            overlay     : [],
            in          : size,
            defaultStyle: ElementStyle(),
            clearMode   : .full,
            onFullClear : { expectation.fulfill() }
        )

        waitForExpectations(timeout: 1.0)
    }

    func testRenderFrameRendersBaseAndOverlayElements() {
        let renderer = Renderer()
        let size = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
        let expectation = expectation(description: "Expected both base and overlay renders")
        expectation.expectedFulfillmentCount = 2

        let baseElement = RecordingRenderable {
            expectation.fulfill()
        }

        let overlayElement = RecordingRenderable {
            expectation.fulfill()
        }

        renderer.renderFrame(
            base        : [baseElement],
            overlay     : [overlayElement],
            in          : size,
            defaultStyle: ElementStyle(),
            clearMode   : .full,
            onFullClear : nil
        )

        waitForExpectations(timeout: 1.0)
    }

    func testOverlayDismissalSkipsFullClear() {
        let renderer = Renderer()
        let size = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)

        let baseExpectation = expectation(description: "Base should rerender on overlay clear")

        let invalidationExpectation = expectation(description: "Overlay invalidation should not run for overlay-only clear")
        invalidationExpectation.isInverted = true

        let baseElement = RecordingRenderable {
            baseExpectation.fulfill()
        }

        renderer.renderFrame(
            base        : [baseElement],
            overlay     : [],
            in          : size,
            defaultStyle: ElementStyle(),
            clearMode   : .overlayDismissal,
            onFullClear : { invalidationExpectation.fulfill() }
        )

        waitForExpectations(timeout: 0.5)
    }

    func testOverlayDismissalClearIncludesBottomRow() {
        let renderer = Renderer()
        let size = winsize(ws_row: 6, ws_col: 5, ws_xpixel: 0, ws_ypixel: 0)

        let pipe = Pipe()
        let originalStdout = dup(STDOUT_FILENO)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)

        renderer.renderFrame(
            base        : [],
            overlay     : [],
            in          : size,
            defaultStyle: ElementStyle(),
            clearMode   : .overlayDismissal,
            onFullClear : nil
        )

        let drainExpectation = expectation(description: "Wait for renderer output")
        DispatchQueue.main.async {
            drainExpectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        fflush(stdout)
        pipe.fileHandleForWriting.closeFile()

        dup2(originalStdout, STDOUT_FILENO)
        close(originalStdout)

        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""

        XCTAssertTrue(output.contains("\u{001B}[s"), "Clear should preserve the caller cursor with save")
        XCTAssertTrue(output.contains("\u{001B}[u"), "Clear should restore the caller cursor after scrubbing")
        XCTAssertTrue(output.contains("\u{001B}[5;1H\u{001B}[0K"), "Overlay dismissal should blank the final row in the overlay region")
    }

    func testOverlayDismissalClearsSpecificBounds() {
        let renderer = Renderer()
        let size = winsize(ws_row: 10, ws_col: 20, ws_xpixel: 0, ws_ypixel: 0)
        let pipe = Pipe()
        let originalStdout = dup(STDOUT_FILENO)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)

        let overlayBounds = BoxBounds(row: 3, col: 5, width: 6, height: 2)

        renderer.renderFrame(
            base              : [],
            overlay           : [],
            in                : size,
            defaultStyle      : ElementStyle(),
            clearMode         : .overlayDismissal,
            onFullClear       : nil,
            overlayClearBounds: [overlayBounds]
        )

        let drainExpectation = expectation(description: "Wait for renderer output")
        DispatchQueue.main.async {
            drainExpectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        fflush(stdout)
        pipe.fileHandleForWriting.closeFile()

        dup2(originalStdout, STDOUT_FILENO)
        close(originalStdout)

        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""

        XCTAssertTrue(output.contains("\u{001B}[3;5H"), "Overlay dismissal should target the overlay top row")
        XCTAssertTrue(output.contains("\u{001B}[4;5H"), "Overlay dismissal should scrub each row inside the overlay bounds")
        XCTAssertFalse(output.contains("\u{001B}[2;1H"), "Overlay dismissal should avoid clearing the chrome when bounds are provided")
    }
}

private final class RecordingRenderable: Renderable {

    private let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    func render ( in size: winsize ) -> [AnsiSequence]? {
        handler()
        return []
    }
}

