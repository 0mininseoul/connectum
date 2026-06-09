import Foundation
import Darwin
import Network

struct SupabaseOAuthCallback: Equatable {
    let code: String
    let state: String
}

enum SupabaseOAuthFlow {
    static let port: UInt16 = 53682
    static let callbackPath = "/callback"
    static let redirectURI = "http://127.0.0.1:\(port)\(callbackPath)"

    static func redirectURI(port: UInt16) -> URL {
        URL(string: "http://127.0.0.1:\(port)\(callbackPath)")!
    }
}

enum SupabaseOAuthState {
    private struct Payload: Codable {
        let v: Int
        let nonce: String
        let loopback: String
    }

    static func generate(byteCount: Int = 24, loopbackURL: URL? = nil) -> String {
        let nonce = randomToken(byteCount: byteCount)
        guard let loopbackURL,
              let data = try? JSONEncoder().encode(Payload(v: 1, nonce: nonce, loopback: loopbackURL.absoluteString)) else {
            return nonce
        }
        return "connectum.\(base64URLEncoded(data))"
    }

    private static func randomToken(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URLEncoded(Data(bytes))
    }

    private static func base64URLEncoded(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

enum SupabaseOAuthCallbackParser {
    enum ParseError: LocalizedError {
        case malformedRequest
        case unexpectedPath(String)
        case missingCode
        case missingState

        var errorDescription: String? {
            switch self {
            case .malformedRequest: return "OAuth 콜백 요청을 읽을 수 없습니다."
            case .unexpectedPath: return "OAuth 콜백 경로가 올바르지 않습니다."
            case .missingCode: return "OAuth 인증 코드가 없습니다."
            case .missingState: return "OAuth state 값이 없습니다."
            }
        }
    }

    static func parse(_ request: String) throws -> SupabaseOAuthCallback {
        guard let firstLine = request.components(separatedBy: "\r\n").first else {
            throw ParseError.malformedRequest
        }
        let parts = firstLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else { throw ParseError.malformedRequest }
        guard let components = URLComponents(string: "http://127.0.0.1\(parts[1])") else {
            throw ParseError.malformedRequest
        }
        guard components.path == SupabaseOAuthFlow.callbackPath else {
            throw ParseError.unexpectedPath(components.path)
        }
        let query = components.queryItems ?? []
        guard let code = query.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw ParseError.missingCode
        }
        guard let state = query.first(where: { $0.name == "state" })?.value, !state.isEmpty else {
            throw ParseError.missingState
        }
        return SupabaseOAuthCallback(code: code, state: state)
    }
}

enum SupabaseOAuthLoopbackError: LocalizedError {
    case cannotCreatePort
    case listenerFailed(String)
    case timeout
    case stateMismatch

    var errorDescription: String? {
        switch self {
        case .cannotCreatePort: return "OAuth 콜백 포트를 열 수 없습니다."
        case .listenerFailed(let message): return "OAuth 콜백 수신에 실패했습니다: \(message)"
        case .timeout: return "OAuth 인증 시간이 초과되었습니다."
        case .stateMismatch: return "OAuth state 값이 일치하지 않습니다."
        }
    }
}

final class SupabaseOAuthLoopbackReceiver: @unchecked Sendable {
    private let queue = DispatchQueue(label: "connectum.supabase-oauth-loopback")
    private var listener: NWListener?
    private var continuation: CheckedContinuation<SupabaseOAuthCallback, Error>?
    private var didResume = false

    static func availablePort() throws -> UInt16 {
        let socketFd = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFd >= 0 else { throw SupabaseOAuthLoopbackError.cannotCreatePort }
        defer { close(socketFd) }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { throw SupabaseOAuthLoopbackError.cannotCreatePort }

        var boundAddr = sockaddr_in()
        var boundLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(socketFd, $0, &boundLength)
            }
        }
        guard nameResult == 0 else { throw SupabaseOAuthLoopbackError.cannotCreatePort }
        return UInt16(bigEndian: boundAddr.sin_port)
    }

    func waitForCallback(
        expectedState: String,
        port rawPort: UInt16 = SupabaseOAuthFlow.port,
        timeout: TimeInterval = 180
    ) async throws -> SupabaseOAuthCallback {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    self.continuation = continuation
                    self.didResume = false
                    do {
                        guard let port = NWEndpoint.Port(rawValue: rawPort) else {
                            throw SupabaseOAuthLoopbackError.cannotCreatePort
                        }
                        let listener = try NWListener(using: .tcp, on: port)
                        listener.newConnectionHandler = { [weak self] connection in
                            self?.handle(connection, expectedState: expectedState)
                        }
                        listener.stateUpdateHandler = { [weak self] state in
                            if case .failed(let error) = state {
                                self?.resume(throwing: SupabaseOAuthLoopbackError.listenerFailed(error.localizedDescription))
                            }
                        }
                        self.listener = listener
                        listener.start(queue: self.queue)
                        self.queue.asyncAfter(deadline: .now() + timeout) {
                            self.resume(throwing: SupabaseOAuthLoopbackError.timeout)
                        }
                    } catch {
                        self.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            cancel()
        }
    }

    func cancel() {
        queue.async {
            self.resume(throwing: CancellationError())
        }
    }

    private func handle(_ connection: NWConnection, expectedState: String) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, error in
            guard let self else { return }
            if let error {
                self.sendResponse(to: connection, success: false)
                self.resume(throwing: SupabaseOAuthLoopbackError.listenerFailed(error.localizedDescription))
                return
            }
            guard let data, let request = String(data: data, encoding: .utf8) else {
                self.sendResponse(to: connection, success: false)
                self.resume(throwing: SupabaseOAuthCallbackParser.ParseError.malformedRequest)
                return
            }
            do {
                let callback = try SupabaseOAuthCallbackParser.parse(request)
                guard callback.state == expectedState else {
                    throw SupabaseOAuthLoopbackError.stateMismatch
                }
                self.sendResponse(to: connection, success: true)
                self.resume(returning: callback)
            } catch {
                self.sendResponse(to: connection, success: false)
                self.resume(throwing: error)
            }
        }
    }

    private func sendResponse(to connection: NWConnection, success: Bool) {
        let title = success ? "Connectum 연결 완료" : "Connectum 연결 실패"
        let body = success ? "이 창을 닫고 Connectum으로 돌아가세요." : "Connectum으로 돌아가 다시 시도하세요."
        let html = "<!doctype html><meta charset=\"utf-8\"><title>\(title)</title><body style=\"font-family:-apple-system;padding:32px\"><h1>\(title)</h1><p>\(body)</p></body>"
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(html.utf8.count)\r
        Connection: close\r
        \r
        \(html)
        """
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func resume(returning callback: SupabaseOAuthCallback) {
        guard !didResume else { return }
        didResume = true
        listener?.cancel()
        listener = nil
        continuation?.resume(returning: callback)
        continuation = nil
    }

    private func resume(throwing error: Error) {
        guard !didResume else { return }
        didResume = true
        listener?.cancel()
        listener = nil
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
