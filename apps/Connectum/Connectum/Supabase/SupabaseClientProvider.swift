import Foundation
import Supabase

// Resolves the Connectum backend connection. Priority:
//   1. Env vars SUPABASE_URL / SUPABASE_ANON_KEY  (Xcode run / dev)
//   2. ~/Library/Application Support/Connectum/config.json  {"supabaseUrl","supabaseAnonKey"}
//      (lets the distributed app point at a hosted backend without a rebuild)
//   3. localhost default (a local `supabase start` stack)
enum SupabaseClientProvider {
    struct Config: Decodable { let supabaseUrl: String; let supabaseAnonKey: String }

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
            return (cfg.supabaseUrl, cfg.supabaseAnonKey)
        }
        return ("http://127.0.0.1:54321", "")
    }

    static let shared: SupabaseClient = {
        let (url, anon) = resolve()
        return SupabaseClient(supabaseURL: URL(string: url)!, supabaseKey: anon)
    }()
}
