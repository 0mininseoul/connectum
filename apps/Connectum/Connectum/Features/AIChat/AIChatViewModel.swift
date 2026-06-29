import Foundation
import Observation

@MainActor
@Observable
final class AIChatViewModel {
    var messages: [ChatMessage] = []
    var inputText = ""
    var isStreaming = false
    var statusText: String?
    var connected = false
    var errorText: String?
    var serviceId: String?

    private let repo: CrmDataProviding
    private let client = AIChatStreamClient()
    private var loadedServiceId: String?

    init(repo: CrmDataProviding = CrmRepository()) { self.repo = repo }

    func refreshConnection() async {
        connected = (try? await repo.fetchAIAccount()).flatMap { $0 } != nil
    }

    // Bind the panel to the selected service: refresh connection and load that
    // service's persisted chat thread (each service has its own history).
    func bind(serviceId: String?) async {
        self.serviceId = serviceId
        await refreshConnection()
        guard let serviceId, serviceId != loadedServiceId else { return }
        loadedServiceId = serviceId
        messages = (try? await repo.fetchChatMessages(serviceId: serviceId)) ?? []
    }

    func send() async {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }
        guard let serviceId else {
            errorText = "Supabase 원본을 연결하고 서비스를 만든 뒤 AI 채팅을 사용할 수 있습니다."
            return
        }
        inputText = ""
        errorText = nil
        messages.append(ChatMessage(role: .user, text: trimmed))
        messages.append(ChatMessage(role: .assistant, text: "", isStreaming: true))
        let idx = messages.count - 1
        isStreaming = true
        defer { isStreaming = false; statusText = nil }

        // Send prior history (everything before the in-flight assistant turn).
        let wire: [[String: Any]] = messages.dropLast().map { m in
            ["role": m.role == .user ? "user" : "assistant", "content": m.text]
        }

        // Accumulate the full answer, then reveal it character by character.
        var fullText = ""
        do {
            try await client.stream(serviceId: serviceId, messages: wire) { [weak self] chunk in
                guard let self else { return }
                switch chunk {
                case .status(let tool): self.statusText = self.statusLabel(tool)
                case .text(let t): fullText += t
                case .done: self.statusText = nil
                }
            }
        } catch AIChatStreamError.reauthRequired {
            connected = false
            errorText = "AI 연결이 만료됐습니다."
        } catch {
            errorText = "오류: \(error.localizedDescription)"
        }
        statusText = nil

        if fullText.isEmpty {
            if idx < messages.count { messages[idx].isStreaming = false }
            if errorText == nil { errorText = "응답이 비어 있습니다." }
            return
        }
        await typeOut(fullText, idx: idx)
        // Persist the turn so the thread survives app restarts. (serviceId is the
        // non-optional value unwrapped by the guard at the top of send().)
        try? await repo.saveChatMessage(serviceId: serviceId, role: "user", content: trimmed)
        try? await repo.saveChatMessage(serviceId: serviceId, role: "assistant", content: fullText)
    }

    // Typewriter reveal of the received answer.
    private func typeOut(_ text: String, idx: Int) async {
        let chars = Array(text)
        let perTick = max(1, chars.count / 120)   // ~120 ticks max, regardless of length
        var shown = ""
        var i = 0
        while i < chars.count {
            guard idx < messages.count else { return }
            let end = min(i + perTick, chars.count)
            shown += String(chars[i..<end])
            messages[idx].text = shown
            messages[idx].isStreaming = true
            i = end
            try? await Task.sleep(nanoseconds: 14_000_000) // ~14ms per tick
        }
        if idx < messages.count { messages[idx].isStreaming = false }
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
