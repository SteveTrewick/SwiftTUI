import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif
import XCTest
@testable import SwiftTUI

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
        let terminalInput = TerminalInput()
        let result = terminalInput.translate(bytes: Data([0x1B, 0x66]))

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
        let terminalInput = TerminalInput()
        let result = terminalInput.translate(bytes: Data([0x1B, 0x41]))

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
        let input = TerminalInput()
        var bytes = Data([0x1b])
        bytes.append(contentsOf: "[12R".utf8)

        let result = input.translate(bytes: bytes)

        switch result {
        case .failure:
            break
        case .success(let inputs):
            XCTFail("Expected failure for truncated response, got \(inputs)")
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

        [" One", " Two"].forEach { label in
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
