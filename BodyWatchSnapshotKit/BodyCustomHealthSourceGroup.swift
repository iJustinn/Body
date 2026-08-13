//
//  BodyCustomHealthSourceGroup.swift
//  BodyWatchSnapshotKit
//
//  A user-created source: several discovered Apple Health sources merged into
//  one selectable option (`custom:<uuid>`), the hand-picked counterpart of the
//  automatic `combined-name:` grouping. Lives in the shared folder for the same
//  reason `BodyHealthDataSourceSelection` does — the phone ships the group
//  definitions in the compute seed and the watch has to rebuild the identical
//  ID → sources bucket, or a synced selection would resolve to a different (or
//  no) source there.
//
//  Foundation-only (no SwiftUI): this folder is compiled into the watch app.
//  That is also why `name` carries no localized fallback — a literal default
//  here would ship untranslated on the watch, so the display default is applied
//  at the iOS UI layer.
//

import Foundation

struct BodyCustomHealthSourceGroup: Codable, Equatable, Identifiable {
    let id: String
    var name: String
    /// `BodyHealthDataSourceOption.individualSourceIdentityKey` strings, kept
    /// sorted + deduped by every entry point (init and decode) so
    /// `canonicalSignature(for:)` can't shift with the order the membership UI
    /// happened to hand them over in.
    var memberIdentityKeys: [String]
    /// SF Symbol picked by the user, or `nil` for the default icon — which, like
    /// `name`'s fallback, is applied at the iOS UI layer. Encoding stays
    /// synthesized so a `nil` icon simply omits the key and groups saved before
    /// this field keep their exact JSON.
    var iconSystemName: String?

    init(id: String, name: String, memberIdentityKeys: [String], iconSystemName: String? = nil) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.memberIdentityKeys = Array(Set(memberIdentityKeys)).sorted()
        let trimmedIconSystemName = iconSystemName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.iconSystemName = (trimmedIconSystemName?.isEmpty ?? true) ? nil : trimmedIconSystemName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            name: try container.decodeIfPresent(String.self, forKey: .name) ?? "",
            memberIdentityKeys: try container.decodeIfPresent([String].self, forKey: .memberIdentityKeys) ?? [],
            iconSystemName: try container.decodeIfPresent(String.self, forKey: .iconSystemName)
        )
    }

    var option: BodyHealthDataSourceOption {
        BodyHealthDataSourceOption(id: id, name: name)
    }

    static func custom(
        name: String,
        memberIdentityKeys: [String],
        iconSystemName: String? = nil
    ) -> BodyCustomHealthSourceGroup {
        BodyCustomHealthSourceGroup(
            id: BodyHealthDataSourceOption.customSourceID(for: UUID()),
            name: name,
            memberIdentityKeys: memberIdentityKeys,
            iconSystemName: iconSystemName
        )
    }
}

enum BodyCustomHealthSourceGroupStore {
    static let maximumGroupCount = 5
    /// A group merging fewer than two sources is just the source itself.
    static let minimumMemberCount = 2

    static func groups(from rawValue: String) -> [BodyCustomHealthSourceGroup] {
        guard
            let data = rawValue.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([BodyCustomHealthSourceGroup].self, from: data)
        else {
            return []
        }

        return Array(decoded.filter { $0.option.isCustomSource }.prefix(maximumGroupCount))
    }

    static func rawValue(from groups: [BodyCustomHealthSourceGroup]) -> String {
        let groups = Array(groups.filter { $0.option.isCustomSource }.prefix(maximumGroupCount))

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard
            let data = try? encoder.encode(groups),
            let rawValue = String(data: data, encoding: .utf8)
        else {
            return ""
        }
        return rawValue
    }

    /// Deterministic digest of what the groups RESOLVE to — ids and membership,
    /// never names or icons. Signing `rawValue` instead would churn every cache
    /// and re-seed the watch on a pure rename or icon change, which changes no
    /// query and no math.
    static func canonicalSignature(for groups: [BodyCustomHealthSourceGroup]) -> String {
        groups
            .sorted { $0.id < $1.id }
            .map { "\($0.id)=\($0.memberIdentityKeys.sorted().joined(separator: "+"))" }
            .joined(separator: ",")
    }
}
