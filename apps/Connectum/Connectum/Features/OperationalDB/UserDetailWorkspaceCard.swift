import Foundation

enum UserDetailWorkspaceCard: String, CaseIterable, Codable, Identifiable, Sendable {
    case aiSummary
    case contactRecords
    case notes
    case profile
    case recentEvents

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aiSummary: return "AI 총평"
        case .contactRecords: return "컨택 기록"
        case .notes: return "노트"
        case .profile: return "프로필"
        case .recentEvents: return "최근 이벤트"
        }
    }

    var subtitle: String {
        switch self {
        case .aiSummary: return "AI가 정리한 유저 요약"
        case .contactRecords: return "컨택 내역과 메모"
        case .notes: return "유저 메모"
        case .profile: return "식별 정보와 원본 필드"
        case .recentEvents: return "최근 활동 이벤트"
        }
    }

    static let defaultOrder: [UserDetailWorkspaceCard] = [
        .aiSummary,
        .contactRecords,
        .notes,
        .profile,
        .recentEvents
    ]

    static func decodedOrder(from rawValue: String) -> [UserDetailWorkspaceCard] {
        guard
            let data = rawValue.data(using: .utf8),
            let rawOrder = try? JSONDecoder().decode([String].self, from: data)
        else {
            return defaultOrder
        }

        return normalized(rawOrder.compactMap(UserDetailWorkspaceCard.init(rawValue:)))
    }

    static func encoded(_ order: [UserDetailWorkspaceCard]) -> String {
        let rawOrder = normalized(order).map(\.rawValue)
        guard
            let data = try? JSONEncoder().encode(rawOrder),
            let value = String(data: data, encoding: .utf8)
        else {
            return ""
        }
        return value
    }

    static func normalized(_ order: [UserDetailWorkspaceCard]) -> [UserDetailWorkspaceCard] {
        var seen = Set<UserDetailWorkspaceCard>()
        var result: [UserDetailWorkspaceCard] = []

        for card in order where !seen.contains(card) {
            seen.insert(card)
            result.append(card)
        }

        for card in defaultOrder where !seen.contains(card) {
            result.append(card)
        }

        return result
    }

    static func reordered(
        _ order: [UserDetailWorkspaceCard],
        moving source: UserDetailWorkspaceCard,
        to target: UserDetailWorkspaceCard
    ) -> [UserDetailWorkspaceCard] {
        var nextOrder = normalized(order)
        guard
            source != target,
            let sourceIndex = nextOrder.firstIndex(of: source),
            let targetIndex = nextOrder.firstIndex(of: target)
        else {
            return nextOrder
        }

        let movedCard = nextOrder.remove(at: sourceIndex)
        let insertionIndex = max(0, min(nextOrder.count, targetIndex))
        nextOrder.insert(movedCard, at: insertionIndex)
        return normalized(nextOrder)
    }

    static func move(_ order: inout [UserDetailWorkspaceCard], from source: IndexSet, to destination: Int) {
        let normalizedOrder = normalized(order)
        let sourceIndexes = source.filter { normalizedOrder.indices.contains($0) }.sorted()
        guard !sourceIndexes.isEmpty else {
            order = normalizedOrder
            return
        }

        let movingCards = sourceIndexes.map { normalizedOrder[$0] }
        var nextOrder = normalizedOrder
        for index in sourceIndexes.reversed() {
            nextOrder.remove(at: index)
        }

        let removedBeforeDestination = sourceIndexes.filter { $0 < destination }.count
        let insertionIndex = max(0, min(nextOrder.count, destination - removedBeforeDestination))
        nextOrder.insert(contentsOf: movingCards, at: insertionIndex)
        order = normalized(nextOrder)
    }
}
