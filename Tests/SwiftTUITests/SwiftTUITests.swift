import Foundation
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
