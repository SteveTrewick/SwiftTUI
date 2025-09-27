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

