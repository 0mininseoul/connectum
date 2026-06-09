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

enum AIChatStreamError: Error { case reauthRequired, server(String) }

@MainActor
struct AIChatStreamClient {
    enum Chunk { case status(String); case text(String); case done }

    // Streams ai-chat over SSE via raw URLSession (the Supabase SDK doesn't stream well).
    func stream(serviceId: String, messages: [[String: Any]],
                onChunk: @escaping (Chunk) -> Void) async throws {
        let url = SupabaseClientProvider.functionsURL(for: "ai-chat")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        for (k, v) in await SupabaseClientProvider.authHeaders() {
            req.setValue(v, forHTTPHeaderField: k)
        }
        req.httpBody = try JSONSerialization.data(
            withJSONObject: ["service_id": serviceId, "messages": messages])

        let (bytes, response) = try await URLSession.shared.bytes(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw AIChatStreamError.server("status \(code)")
        }

        var parser = SSELineParser()
        for try await line in bytes.lines {
            guard let ev = parser.consume(line: line) else { continue }
            let json = (try? JSONSerialization.jsonObject(with: Data(ev.data.utf8))) as? [String: Any] ?? [:]
            switch ev.event {
            case "status": onChunk(.status(json["tool"] as? String ?? ""))
            case "text": onChunk(.text(json["text"] as? String ?? ""))
            case "done": onChunk(.done)
            case "error":
                if (json["code"] as? String) == "ai_reauth_required" {
                    throw AIChatStreamError.reauthRequired
                }
                throw AIChatStreamError.server(json["message"] as? String ?? "error")
            default: break
            }
        }
    }
}
