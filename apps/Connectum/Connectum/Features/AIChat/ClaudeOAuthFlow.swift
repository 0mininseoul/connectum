import Foundation
import CryptoKit
import Security

// PKCE pair for the Claude (Anthropic) public OAuth client. No client secret.
struct ClaudePKCE {
    let verifier: String
    let challenge: String

    static func generate() -> ClaudePKCE {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = base64URL(Data(bytes))
        return ClaudePKCE(verifier: verifier, challenge: challenge(for: verifier))
    }

    static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URL(Data(digest))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

enum ClaudeOAuthFlow {
    // Reuse the existing fixed-port loopback (Claude's client allow-lists a fixed
    // redirect; a dynamic port would not match). 127.0.0.1:53682/callback.
    static var redirectURI: String { SupabaseOAuthFlow.redirectURI }

    static func authorizeURL(authorizeURL: String, clientId: String, redirectURI: String,
                             scope: String, state: String, codeChallenge: String) -> URL {
        var c = URLComponents(string: authorizeURL)!
        c.queryItems = [
            .init(name: "code", value: "true"),
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: clientId),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "scope", value: scope),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: codeChallenge),
            .init(name: "code_challenge_method", value: "S256"),
        ]
        return c.url!
    }
}
