import Foundation
import Supabase

// Legacy hosted-backend resolver. The local-first app path uses
// LocalCrmRepository and does not require a Connectum Supabase backend.
// Developers who intentionally use HostedSupabaseCrmRepository can point it at
// a backend with env vars or a local config file.
enum SupabaseClientProvider {
    struct Config: Decodable {
        let supabaseUrl: String
        let supabaseKey: String?
        let supabaseAnonKey: String?
        let supabaseOAuthBrokerUrl: String?
        let supabaseOAuthBrokerAnonKey: String?
        // Optional Claude (AI) overrides so the distributed app can set the
        // OAuth client id / scope without a rebuild.
        let claudeClientId: String?
        let claudeScope: String?
        let claudeAuthorizeUrl: String?
        let claudeTokenUrl: String?
        let claudeApiUrl: String?
        let claudeOAuthBeta: String?
        let claudeModel: String?

        var key: String { supabaseKey ?? supabaseAnonKey ?? "" }
    }

    struct ClaudeConfig {
        let clientId: String
        let scope: String
        let authorizeURL: String
        let tokenURL: String
        let apiURL: String
        let oauthBeta: String
        let model: String
    }

    struct SupabaseOAuthBrokerConfig {
        let functionsBaseURL: URL
        let anonKey: String
    }

    static func configFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Connectum/config.json")
    }

    static func resolve() -> (url: String, anon: String) {
        let env = ProcessInfo.processInfo.environment
        if let u = env["SUPABASE_URL"], !u.isEmpty {
            return (u, env["SUPABASE_ANON_KEY"] ?? "")
        }
        if let data = try? Data(contentsOf: configFileURL()),
           let cfg = try? JSONDecoder().decode(Config.self, from: data) {
            return (cfg.supabaseUrl, cfg.key)
        }
        if let url = Bundle.main.url(forResource: "BackendConfig", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let cfg = try? JSONDecoder().decode(Config.self, from: data) {
            return (cfg.supabaseUrl, cfg.key)
        }
        return ("http://127.0.0.1:54321", "")
    }

    static let resolved: (url: String, anon: String) = resolve()

    static let shared: SupabaseClient = {
        return SupabaseClient(supabaseURL: URL(string: resolved.url)!, supabaseKey: resolved.anon)
    }()

    // Direct Edge Function URL (for raw URLSession SSE, which the SDK doesn't stream well).
    static func functionsURL(for name: String) -> URL {
        URL(string: resolved.url)!.appendingPathComponent("functions/v1").appendingPathComponent(name)
    }

    static func supabaseOAuthBrokerConfig() -> SupabaseOAuthBrokerConfig {
        let env = ProcessInfo.processInfo.environment
        let cfg = appConfig() ?? bundledConfig()
        let rawURL = env["CONNECTUM_SUPABASE_OAUTH_BROKER_URL"]
            ?? cfg?.supabaseOAuthBrokerUrl
            ?? resolved.url
        let anonKey = env["CONNECTUM_SUPABASE_OAUTH_BROKER_ANON_KEY"]
            ?? cfg?.supabaseOAuthBrokerAnonKey
            ?? resolved.anon
        let functionsBaseURL = normalizedFunctionsBaseURL(rawURL)
            ?? URL(string: "http://127.0.0.1:54321/functions/v1")!
        return SupabaseOAuthBrokerConfig(functionsBaseURL: functionsBaseURL, anonKey: anonKey)
    }

    // Headers for a direct functions call: anon apikey + the signed-in user's JWT.
    static func authHeaders() async -> [String: String] {
        var h = ["apikey": resolved.anon]
        if let token = try? await shared.auth.session.accessToken {
            h["Authorization"] = "Bearer \(token)"
        }
        return h
    }

    static func claudeConfig() -> ClaudeConfig {
        let env = ProcessInfo.processInfo.environment
        let cfg = appConfig()
        let clientId = env["CLAUDE_OAUTH_CLIENT_ID"] ?? cfg?.claudeClientId ?? "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
        let scope = env["CLAUDE_OAUTH_SCOPE"] ?? cfg?.claudeScope ?? "org:create_api_key user:profile user:inference"
        let authorize = env["CLAUDE_OAUTH_AUTHORIZE_URL"] ?? cfg?.claudeAuthorizeUrl ?? "https://platform.claude.com/oauth/authorize"
        let token = env["CLAUDE_OAUTH_TOKEN_URL"] ?? cfg?.claudeTokenUrl ?? "https://platform.claude.com/v1/oauth/token"
        let api = env["CLAUDE_API_URL"] ?? cfg?.claudeApiUrl ?? "https://api.anthropic.com/v1/messages"
        let beta = env["CLAUDE_OAUTH_BETA"] ?? cfg?.claudeOAuthBeta ?? "oauth-2025-04-20"
        let model = env["CLAUDE_MODEL"] ?? cfg?.claudeModel ?? "claude-sonnet-4-6"
        return ClaudeConfig(
            clientId: clientId,
            scope: scope,
            authorizeURL: authorize,
            tokenURL: token,
            apiURL: api,
            oauthBeta: beta,
            model: model
        )
    }

    private static func appConfig() -> Config? {
        guard let data = try? Data(contentsOf: configFileURL()) else { return nil }
        return try? JSONDecoder().decode(Config.self, from: data)
    }

    private static func bundledConfig() -> Config? {
        guard let url = Bundle.main.url(forResource: "BackendConfig", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Config.self, from: data)
    }

    private static func normalizedFunctionsBaseURL(_ raw: String?) -> URL? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              var url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        let normalizedPath = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !normalizedPath.hasSuffix("functions/v1") {
            url.appendPathComponent("functions/v1")
        }
        return url
    }
}
