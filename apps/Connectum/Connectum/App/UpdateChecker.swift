import Foundation
import Observation

// Checks the app_release table for a newer distributable build and surfaces a
// download link. Manual (button-triggered) — no background polling.
@MainActor
@Observable
final class UpdateChecker {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, url: String, notes: String?)
        case failed(String)
    }

    var state: State = .idle
    private let repo: CrmDataProviding

    init(repo: CrmDataProviding = CrmRepository()) { self.repo = repo }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    func check() async {
        state = .checking
        do {
            guard let release = try await repo.fetchLatestRelease() else {
                state = .upToDate
                return
            }
            if Self.isNewer(release.version, than: currentVersion), URL(string: release.dmgUrl) != nil {
                state = .available(version: release.version, url: release.dmgUrl, notes: release.notes)
            } else {
                state = .upToDate
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // Numeric dotted-version compare ("1.2.0" > "1.1.3").
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0 ..< max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
