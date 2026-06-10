import XCTest
@testable import Connectum

final class ServiceBriefTests: XCTestCase {
    func testBriefSectionsDecodePartial() throws {
        let json = """
        {"sections":{"one_liner":"A CRM","icp":"founders","activation":"","signal_glossary":"","business_model":"","current_focus":""},"status":"ready","gaps":["activation"]}
        """.data(using: .utf8)!
        let brief = try JSONDecoder().decode(ServiceBrief.self, from: json)
        XCTAssertEqual(brief.sections.one_liner, "A CRM")
        XCTAssertEqual(brief.sections.icp, "founders")
        XCTAssertEqual(brief.status, "ready")
        XCTAssertEqual(brief.gaps, ["activation"])
        XCTAssertFalse(brief.isEmpty)
    }

    func testBriefSectionsValueLookup() {
        var s = BriefSections()
        s.current_focus = "retention"
        XCTAssertEqual(s.value(for: "current_focus"), "retention")
        XCTAssertEqual(s.value(for: "unknown_key"), "")
        XCTAssertTrue(s.hasAnyContent)
    }

    func testInterviewStepDecodeQuestion() throws {
        let q = try JSONDecoder().decode(InterviewStep.self, from: #"{"question":"Who is the customer?","options":["A","B"]}"#.data(using: .utf8)!)
        if case let .question(text, opts) = q {
            XCTAssertEqual(text, "Who is the customer?")
            XCTAssertEqual(opts, ["A", "B"])
        } else {
            XCTFail("expected .question")
        }
    }

    func testInterviewStepDecodeDone() throws {
        let d = try JSONDecoder().decode(InterviewStep.self, from: #"{"done":true}"#.data(using: .utf8)!)
        if case .done = d {} else { XCTFail("expected .done") }
    }

    func testExtractPlainText() throws {
        let data = "hello world".data(using: .utf8)!
        let text = try DocumentTextExtractor.extract(data: data, ext: "txt")
        XCTAssertEqual(text, "hello world")
    }

    func testExtractEmptyThrows() {
        XCTAssertThrowsError(try DocumentTextExtractor.extract(data: Data(), ext: "txt"))
    }

    func testExtractUnsupportedThrows() {
        XCTAssertThrowsError(try DocumentTextExtractor.extract(data: Data("x".utf8), ext: "docx"))
    }
}
