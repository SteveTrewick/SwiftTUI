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

final class StatusBarRenderingTests: XCTestCase {

    func testStatusBarRenderPadsAndPositionsContent() {
        let model = StatusBarModel(
            content: "Ready",
            foregroundColor: .white,
            backgroundColor: .bgBlue
        )

        var statusBar = StatusBar(width: 20, row: 5)
        let sequence = statusBar.render(model: model)
        let rendered = sequence.description

        XCTAssertTrue(rendered.contains("\u{001B}[5;1H"))
        let expectedContent = model.text(maxWidth: 20)
        let expectedPadding = expectedContent + String(repeating: " ", count: 20 - expectedContent.count)
        XCTAssertTrue(rendered.contains(expectedPadding))
        XCTAssertTrue(rendered.hasSuffix("\u{001B}[0m"))

        statusBar.updateSize(width: 8, row: 3)
        let truncated = statusBar.render(model: model).description
        XCTAssertTrue(truncated.contains("\u{001B}[3;1H"))
        XCTAssertTrue(truncated.contains(model.text(maxWidth: 8)))
    }
}

private final class MockOutputController: OutputDisplaying {

    var callCount = 0
    private(set) var lastSequences: [AnsiSequence] = []

    func display(_ sequences: AnsiSequence...) {
        callCount += 1
        lastSequences = sequences
    }

    var lastRendered: String? {
        guard !lastSequences.isEmpty else { return nil }
        return lastSequences.map { $0.description }.joined()
    }
}

final class TerminalPresenterTests: XCTestCase {

    func testPresenterRecalculatesWidthAfterLayout() {
        let mockOutput = MockOutputController()
        let state = TerminalState(statusText: "Ready")
        let presenter = TerminalPresenter(
            state: state,
            output: mockOutput,
            initialWidth: 12,
            initialHeight: 4
        )

        XCTAssertEqual(mockOutput.callCount, 1)
        XCTAssertEqual(mockOutput.lastRendered?.contains(state.statusBarModel.text(maxWidth: 12)), true)

        presenter.layout(width: 6, height: 2)
        XCTAssertEqual(mockOutput.callCount, 2)
        XCTAssertTrue(mockOutput.lastRendered?.contains("\u{001B}[2;1H") ?? false)
        XCTAssertTrue(mockOutput.lastRendered?.contains(state.statusBarModel.text(maxWidth: 6)) ?? false)

        state.statusText = "Editing file.swift"
        XCTAssertEqual(mockOutput.callCount, 3)
        XCTAssertTrue(mockOutput.lastRendered?.contains(state.statusBarModel.text(maxWidth: 6)) ?? false)
    }
}
