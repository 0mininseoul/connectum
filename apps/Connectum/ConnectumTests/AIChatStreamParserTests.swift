import XCTest
@testable import Connectum

final class AIChatStreamParserTests: XCTestCase {
    func testParsesEventDataPairs() {
        var parser = SSELineParser()
        var events: [SSEEvent] = []
        for line in ["event: status", #"data: {"tool":"search_users"}"#, "",
                     "event: text", #"data: {"text":"hi"}"#, ""] {
            if let e = parser.consume(line: line) { events.append(e) }
        }
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].event, "status")
        XCTAssertTrue(events[0].data.contains("search_users"))
        XCTAssertEqual(events[1].event, "text")
        XCTAssertTrue(events[1].data.contains("hi"))
    }

    func testBlankBeforeAnyFieldYieldsNothing() {
        var parser = SSELineParser()
        XCTAssertNil(parser.consume(line: ""))
    }
}
