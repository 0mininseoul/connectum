import Foundation
import Supabase

// Resolves the Connectum backend connection. Priority:
//   1. Env vars SUPABASE_URL / SUPABASE_ANON_KEY  (Xcode run / dev)
//   2. ~/Library/Application Support/Connectum/config.json  {"supabaseUrl","supabaseAnonKey"}
//      (lets the distributed app point at a hosted backend without a rebuild)
//   3. Bundled BackendConfig.json default for first installs
//   4. localhost default (a local `supabase start` stack)
enum SupabaseClientProvider {
    struct Config: Decodable {
        let supabaseUrl: String
        let supabaseKey: String?
        let supabaseAnonKey: String?
        // Optional Claude (AI) overrides so the distributed app can set the
        // OAuth client id / scope without a rebuild.
        let claudeClientId: String?
        let claudeScope: String?
        let claudeAuthorizeUrl: String?

        var key: String { supabaseKey ?? supabaseAnonKey ?? "" }
    }

    struct ClaudeConfig {
        let clientId: String
        let scope: String
        let authorizeURL: String
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
        let cfg: Config? = {
            guard let data = try? Data(contentsOf: configFileURL()) else { return nil }
            return try? JSONDecoder().decode(Config.self, from: data)
        }()
        let clientId = env["CLAUDE_OAUTH_CLIENT_ID"] ?? cfg?.claudeClientId ?? ""
        let scope = env["CLAUDE_OAUTH_SCOPE"] ?? cfg?.claudeScope ?? "org:create_api_key user:profile user:inference"
        let authorize = env["CLAUDE_OAUTH_AUTHORIZE_URL"] ?? cfg?.claudeAuthorizeUrl ?? "https://claude.ai/oauth/authorize"
        return ClaudeConfig(clientId: clientId, scope: scope, authorizeURL: authorize)
    }
}
