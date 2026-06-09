import Foundation
import Observation

@MainActor
@Observable
final class AIChatViewModel {
    var messages: [ChatMessage] = []
    var inputText = ""
    var isStreaming = false
    var statusText: String?
    var connected = true
    var errorText: String?
    var serviceId: String?

    private let repo: CrmDataProviding
    private let client = AIChatStreamClient()

    init(repo: CrmDataProviding = CrmRepository()) { self.repo = repo }

    func refreshConnection() async {
        connected = (try? await repo.fetchAIAccount()).flatMap { $0 } != nil
    }

    func send() async {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let serviceId, !trimmed.isEmpty, !isStreaming else { return }
        inputText = ""
        errorText = nil
        messages.append(ChatMessage(role: .user, text: trimmed))
        var assistant = ChatMessage(role: .assistant, text: "", isStreaming: true)
        messages.append(assistant)
        let idx = messages.count - 1
        isStreaming = true
        defer { isStreaming = false; statusText = nil }

        // Send prior history (everything before the in-flight assistant turn).
        let wire: [[String: Any]] = messages.dropLast().map { m in
            ["role": m.role == .user ? "user" : "assistant", "content": m.text]
        }

        do {
            try await client.stream(serviceId: serviceId, messages: wire) { [weak self] chunk in
                guard let self else { return }
                switch chunk {
                case .status(let tool):
                    self.statusText = self.statusLabel(tool)
                case .text(let t):
                    assistant.text += t
                    assistant.isStreaming = true
                    self.messages[idx] = assistant
                case .done:
                    assistant.isStreaming = false
                    self.messages[idx] = assistant
                    self.statusText = nil
                }
            }
        } catch AIChatStreamError.reauthRequired {
            connected = false
            errorText = "Claude 연결이 만료됐습니다. 연동 탭에서 다시 연결하세요."
        } catch {
            errorText = "오류: \(error.localizedDescription)"
        }
        assistant.isStreaming = false
        if idx < messages.count { messages[idx] = assistant }
    }

    private func statusLabel(_ tool: String) -> String {
        switch tool {
        case "search_users": return "유저 검색 중…"
        case "get_user_detail": return "유저 상세 조회 중…"
        case "get_user_events": return "이벤트 조회 중…"
        case "get_metrics", "get_service_overview": return "지표 계산 중…"
        default: return "조회 중…"
        }
    }
}
