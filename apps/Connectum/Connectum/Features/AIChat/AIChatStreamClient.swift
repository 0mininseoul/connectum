import Foundation

struct SSEEvent { let event: String; let data: String }

// Incremental SSE line parser: feed it lines, get an SSEEvent on each blank line.
struct SSELineParser {
    private var event = ""
    private var data = ""

    mutating func consume(line: String) -> SSEEvent? {
        if line.isEmpty {
            guard !data.isEmpty || !event.isEmpty else { return nil }
            let e = SSEEvent(event: event.isEmpty ? "message" : event, data: data)
            event = ""; data = ""
            return e
        }
        if line.hasPrefix("event:") {
            event = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        } else if line.hasPrefix("data:") {
            data += String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }
}

enum AIChatStreamError: LocalizedError {
    case reauthRequired
    case server(String)

    var errorDescription: String? {
        switch self {
        case .reauthRequired:
            return "Claude 연결이 만료됐습니다. 다시 연결하세요."
        case .server(let message):
            return message
        }
    }
}

@MainActor
struct AIChatStreamClient {
    enum Chunk { case status(String); case text(String); case done }

    private struct SystemBlock: Encodable {
        let type = "text"
        let text: String
    }

    private struct WireMessage: Encodable {
        let role: String
        let content: String
    }

    private struct RequestBody: Encodable {
        let model: String
        let maxTokens: Int
        let system: [SystemBlock]
        let messages: [WireMessage]

        enum CodingKeys: String, CodingKey {
            case model
            case maxTokens = "max_tokens"
            case system
            case messages
        }
    }

    private struct ResponseBody: Decodable {
        struct ContentBlock: Decodable {
            let type: String
            let text: String?
        }

        let content: [ContentBlock]
    }

    private struct UserContext: Encodable {
        let sourceUserId: String
        let email: String?
        let displayName: String?
        let contactStatus: String
        let createdAt: String?
        let aiSummary: String?

        enum CodingKeys: String, CodingKey {
            case sourceUserId = "source_user_id"
            case email
            case displayName = "display_name"
            case contactStatus = "contact_status"
            case createdAt = "created_at"
            case aiSummary = "ai_summary"
        }
    }

    private struct ServiceContext: Encodable {
        let serviceName: String
        let metrics: DashboardMetrics?
        let usersSampleCount: Int
        let users: [UserContext]
        let brief: ServiceBrief?

        enum CodingKeys: String, CodingKey {
            case serviceName = "service_name"
            case metrics
            case usersSampleCount = "users_sample_count"
            case users
            case brief
        }
    }

    private let repo: CrmDataProviding
    private let tokenProvider: LocalClaudeOAuthTokenProvider

    init(
        repo: CrmDataProviding = CrmRepository(),
        tokenProvider: LocalClaudeOAuthTokenProvider = LocalClaudeOAuthTokenProvider()
    ) {
        self.repo = repo
        self.tokenProvider = tokenProvider
    }

    func stream(serviceId: String, messages: [[String: Any]],
                onChunk: @escaping (Chunk) -> Void) async throws {
        onChunk(.status("get_service_overview"))
        let token: String
        do {
            token = try await tokenProvider.validAccessToken()
        } catch {
            throw AIChatStreamError.reauthRequired
        }
        let config = SupabaseClientProvider.claudeConfig()
        guard let url = URL(string: config.apiURL) else {
            throw AIChatStreamError.server("Claude API URL이 올바르지 않습니다.")
        }
        let body = RequestBody(
            model: config.model,
            maxTokens: 4096,
            system: try await systemBlocks(serviceId: serviceId),
            messages: wireMessages(from: messages)
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue(config.oauthBeta, forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIChatStreamError.server("Claude API 응답을 읽을 수 없습니다.")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw AIChatStreamError.reauthRequired
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AIChatStreamError.server("Claude API HTTP \(http.statusCode): \(String(data: data, encoding: .utf8) ?? "")")
        }

        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        let text = decoded.content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw AIChatStreamError.server("Claude 응답이 비어 있습니다.")
        }
        onChunk(.text(text))
        onChunk(.done)
    }

    private func wireMessages(from messages: [[String: Any]]) -> [WireMessage] {
        messages.compactMap { raw in
            guard let role = raw["role"] as? String,
                  role == "user" || role == "assistant",
                  let content = raw["content"] as? String,
                  !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return WireMessage(role: role, content: content)
        }
    }

    private func systemBlocks(serviceId: String) async throws -> [SystemBlock] {
        let context = try await serviceContext(serviceId: serviceId)
        return [
            SystemBlock(text: "You are Claude Code, Anthropic's official CLI for Claude."),
            SystemBlock(text: """
            You are Connectum's embedded CRM analyst. Answer questions about the user's customers using only the local service context below and the conversation history. Prefer concrete numbers and cite user emails or display names when relevant. Reply in the user's language. If the local context is insufficient, say what needs to be synced or configured instead of inventing data.
            """),
            SystemBlock(text: "Selected service local context:\n\(context)")
        ]
    }

    private func serviceContext(serviceId: String) async throws -> String {
        let services = (try? await repo.fetchServices()) ?? []
        let serviceName = services.first { $0.id == serviceId }?.name ?? "Unknown service"
        let metrics = try? await repo.fetchMetrics(serviceId: serviceId)
        let users = ((try? await repo.fetchUsers(serviceId: serviceId)) ?? [])
            .prefix(80)
            .map {
                UserContext(
                    sourceUserId: $0.sourceUserId,
                    email: $0.email,
                    displayName: $0.displayName,
                    contactStatus: $0.contactStatus,
                    createdAt: $0.createdAt,
                    aiSummary: $0.aiSummary
                )
            }
        let brief = try? await repo.fetchServiceBrief(serviceId: serviceId)
        let context = ServiceContext(
            serviceName: serviceName,
            metrics: metrics,
            usersSampleCount: users.count,
            users: Array(users),
            brief: brief
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(context)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
