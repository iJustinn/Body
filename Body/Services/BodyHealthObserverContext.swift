import Foundation

/// Fetch provenance for durable observer obligations. Dashboard validity also
/// includes today's boundary and compute preferences; those must never enqueue
/// observer history work by themselves. Keep the two contracts type-distinct.
struct BodyHealthObserverContext: Codable, Equatable, Sendable {
    private static let prefix = "observer-v1:"
    let primary: [String: HealthDashboardCacheScope.Source]
    let secondary: [String: HealthDashboardCacheScope.Source]
    let aggregation: String

    init(scope: HealthDashboardCacheScope) {
        primary = scope.primary
        secondary = scope.secondary
        aggregation = scope.aggregation
    }

    var signature: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return Self.prefix + String(decoding: try! encoder.encode(self), as: UTF8.self)
    }

    init?(signature: String) {
        guard signature.hasPrefix(Self.prefix),
              let decoded = try? JSONDecoder().decode(Self.self, from: Data(signature.dropFirst(Self.prefix.count).utf8)) else { return nil }
        self = decoded
    }
}
