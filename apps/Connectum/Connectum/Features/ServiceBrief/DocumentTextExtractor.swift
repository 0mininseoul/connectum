import Foundation
import PDFKit

enum DocumentExtractError: LocalizedError {
    case empty
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .empty:
            return "문서에서 텍스트를 찾지 못했습니다 (스캔 PDF일 수 있어요). 붙여넣기나 인터뷰를 이용하세요."
        case .unsupported(let ext):
            return "지원하지 않는 형식입니다: .\(ext)"
        }
    }
}

enum DocumentTextExtractor {
    // Supported attachment formats for the service brief (paste covers the rest).
    static let supportedExtensions = ["txt", "md", "markdown", "text", "pdf"]

    static func extract(data: Data, ext: String) throws -> String {
        let text: String
        switch ext.lowercased() {
        case "txt", "md", "markdown", "text":
            text = String(data: data, encoding: .utf8) ?? ""
        case "pdf":
            guard let doc = PDFDocument(data: data) else { throw DocumentExtractError.empty }
            text = (0..<doc.pageCount).compactMap { doc.page(at: $0)?.string }.joined(separator: "\n")
        default:
            throw DocumentExtractError.unsupported(ext)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw DocumentExtractError.empty }
        return trimmed
    }
}
