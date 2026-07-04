//
//  BodyHealthSourceIcon.swift
//  Body
//

import Foundation

enum BodyHealthSourceIcon {
    private struct Rule {
        let symbolName: String
        let nameKeywords: [String]
        let bundleKeywords: [String]
    }

    private static let rules: [Rule] = [
        Rule(
            symbolName: "applewatch",
            nameKeywords: ["apple watch", "watchos", "iwatch", "iwatchx", "iwatch x"],
            bundleKeywords: []
        ),
        Rule(
            symbolName: "ipad",
            nameKeywords: ["ipad"],
            bundleKeywords: []
        ),
        Rule(
            symbolName: "iphone.gen3",
            nameKeywords: ["iphone"],
            bundleKeywords: ["com.apple.health"]
        ),
        Rule(
            symbolName: "circle",
            nameKeywords: ["oura", "ultrahuman", "ringconn", "galaxy ring"],
            bundleKeywords: ["ouraring", "ultrahuman", "ringconn"]
        ),
        Rule(
            symbolName: "applewatch.side.right",
            nameKeywords: ["whoop"],
            bundleKeywords: ["com.whoop"]
        ),
        Rule(
            symbolName: "watch.analog",
            nameKeywords: [
                "garmin", "fitbit", "polar", "suunto", "coros", "amazfit", "zepp",
                "huawei", "mi fitness", "samsung health"
            ],
            bundleKeywords: [
                "com.garmin", "com.fitbit", "fi.polar", "suunto", "coros", "com.huami",
                "com.huawei", "com.sec.shealth", "com.xiaomi"
            ]
        ),
        Rule(
            symbolName: "scalemass",
            nameKeywords: ["withings", "health mate", "renpho", "eufylife", "eufy life", "qardio"],
            bundleKeywords: ["com.withings", "renpho", "eufylife", "qardio"]
        ),
        Rule(
            symbolName: "sensor",
            nameKeywords: ["dexcom", "libre", "librelink", "levels"],
            bundleKeywords: ["com.dexcom", "com.abbott"]
        ),
        Rule(
            symbolName: "bed.double",
            nameKeywords: ["eight sleep"],
            bundleKeywords: ["eightsleep"]
        ),
        Rule(
            symbolName: "figure.run",
            nameKeywords: ["strava", "peloton", "runkeeper", "workoutdoors", "nike run club"],
            bundleKeywords: ["strava", "onepeloton"]
        ),
        Rule(
            symbolName: "fork.knife",
            nameKeywords: ["myfitnesspal", "cronometer", "lose it", "foodnoms", "yazio"],
            bundleKeywords: ["myfitnesspal", "cronometer"]
        )
    ]

    static func systemImageName(name: String, bundleIdentifier: String?, fallback: String) -> String {
        let normalizedName = BodyHealthDataSourceOption.normalizedSourceName(name)
        let nameTokens = normalizedName.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        let normalizedBundle = bundleIdentifier?.lowercased()

        for rule in rules {
            if rule.nameKeywords.contains(where: { nameTokens.containsTokenSequence(for: $0) }) {
                return rule.symbolName
            }

            if let normalizedBundle, rule.bundleKeywords.contains(where: { normalizedBundle.contains($0) }) {
                return rule.symbolName
            }
        }

        return fallback
    }
}

private extension Array where Element == String {
    func containsTokenSequence(for keyword: String) -> Bool {
        let keywordTokens = keyword.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        guard !keywordTokens.isEmpty, keywordTokens.count <= count else { return false }

        for startIndex in 0...(count - keywordTokens.count) {
            if Array(self[startIndex..<(startIndex + keywordTokens.count)]) == keywordTokens {
                return true
            }
        }

        return false
    }
}
