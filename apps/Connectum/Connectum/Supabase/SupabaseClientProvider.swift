import Foundation
import Supabase

// Reads the Connectum project URL + anon key from the environment (injected at run).
// For local dev, set SUPABASE_URL/SUPABASE_ANON_KEY in the scheme env.
enum SupabaseClientProvider {
    static let shared: SupabaseClient = {
        let url = ProcessInfo.processInfo.environment["SUPABASE_URL"]
            ?? "http://127.0.0.1:54321"
        let anon = ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"] ?? ""
        return SupabaseClient(supabaseURL: URL(string: url)!, supabaseKey: anon)
    }()
}
