import Foundation

struct OperationalDBCacheSnapshot: Codable, Equatable {
    let serviceId: String
    let cachedAt: Date
    let users: [CrmUser]
    let savedViews: [SavedView]
    let displayColumns: [String]
}

struct DashboardMetricsCacheSnapshot: Codable, Equatable {
    let serviceId: String
    let cachedAt: Date
    let metrics: DashboardMetrics
}

protocol CrmCacheProviding: Sendable {
    func loadOperationalDB(serviceId: String) throws -> OperationalDBCacheSnapshot?
    func saveOperationalDB(_ snapshot: OperationalDBCacheSnapshot) throws
    func loadDashboardMetrics(serviceId: String) throws -> DashboardMetricsCacheSnapshot?
    func saveDashboardMetrics(_ snapshot: DashboardMetricsCacheSnapshot) throws
    func removeService(serviceId: String) throws
}

struct CrmCacheStore: CrmCacheProviding {
    let rootURL: URL

    init(rootURL: URL? = nil) {
        self.rootURL = rootURL ?? Self.defaultRootURL()
    }

    func loadOperationalDB(serviceId: String) throws -> OperationalDBCacheSnapshot? {
        try load(OperationalDBCacheSnapshot.self, from: operationalDBURL(serviceId: serviceId))
    }

    func saveOperationalDB(_ snapshot: OperationalDBCacheSnapshot) throws {
        try save(snapshot, to: operationalDBURL(serviceId: snapshot.serviceId))
    }

    func loadDashboardMetrics(serviceId: String) throws -> DashboardMetricsCacheSnapshot? {
        try load(DashboardMetricsCacheSnapshot.self, from: dashboardURL(serviceId: serviceId))
    }

    func saveDashboardMetrics(_ snapshot: DashboardMetricsCacheSnapshot) throws {
        try save(snapshot, to: dashboardURL(serviceId: snapshot.serviceId))
    }

    func removeService(serviceId: String) throws {
        let urls = [
            operationalDBURL(serviceId: serviceId),
            dashboardURL(serviceId: serviceId)
        ]
        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func load<T: Decodable>(_ type: T.Type, from url: URL) throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(value)
        try data.write(to: url, options: [.atomic])
    }

    private func operationalDBURL(serviceId: String) -> URL {
        rootURL
            .appendingPathComponent("operational-db", isDirectory: true)
            .appendingPathComponent("\(Self.cacheKey(for: serviceId)).json")
    }

    private func dashboardURL(serviceId: String) -> URL {
        rootURL
            .appendingPathComponent("dashboard", isDirectory: true)
            .appendingPathComponent("\(Self.cacheKey(for: serviceId)).json")
    }

    private static func defaultRootURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Connectum", isDirectory: true)
            .appendingPathComponent("Cache", isDirectory: true)
    }

    private static func cacheKey(for serviceId: String) -> String {
        Data(serviceId.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
