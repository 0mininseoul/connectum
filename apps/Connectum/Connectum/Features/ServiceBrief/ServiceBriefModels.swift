import Foundation

// One service's qualitative context, authored/maintained by Claude. Mirrors the
// `service_brief.sections` jsonb and the service-brief edge function payloads.
struct BriefSections: Codable, Equatable, Sendable {
    var one_liner: String = ""
    var icp: String = ""
    var activation: String = ""
    var signal_glossary: String = ""
    var business_model: String = ""
    var current_focus: String = ""

    static let displayOrder: [(key: String, label: String)] = [
        ("one_liner", "한 줄 소개"),
        ("icp", "타깃 고객 (ICP)"),
        ("activation", "핵심 활성화·성공 기준"),
        ("signal_glossary", "핵심 행동·상태 신호의 의미"),
        ("business_model", "비즈니스 모델"),
        ("current_focus", "현재 집중 목표"),
    ]

    func value(for key: String) -> String {
        switch key {
        case "one_liner": return one_liner
        case "icp": return icp
        case "activation": return activation
        case "signal_glossary": return signal_glossary
        case "business_model": return business_model
        case "current_focus": return current_focus
        default: return ""
        }
    }

    var hasAnyContent: Bool {
        BriefSections.displayOrder.contains { !value(for: $0.key).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

struct ServiceBrief: Codable, Sendable {
    let sections: BriefSections
    let status: String
    let gaps: [String]?

    var isEmpty: Bool { status != "ready" }
}

// One turn of the service-brief interview: either the next question (optionally
// multiple-choice) or a signal that enough has been gathered.
enum InterviewStep: Decodable, Sendable {
    case question(String, [String])
    case done

    private enum Keys: String, CodingKey { case question, options, done }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        if (try? c.decode(Bool.self, forKey: .done)) == true {
            self = .done
            return
        }
        let q = (try? c.decode(String.self, forKey: .question)) ?? ""
        let opts = (try? c.decode([String].self, forKey: .options)) ?? []
        self = .question(q, opts)
    }
}
