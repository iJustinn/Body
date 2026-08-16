//
//  ReadinessCommentGenerator.swift
//  Body
//
//  On-device Apple Intelligence comment for today's readiness score. iOS app
//  target only: BodyMetricsKit compiles for watchOS, where FoundationModels
//  does not exist, so nothing here may move into that folder.
//

import Foundation
import UIKit

#if canImport(FoundationModels)
import FoundationModels
#endif

/// File-scope so the nonisolated task-group child can read it without hopping
/// back to the main actor.
private let readinessCommentGenerationTimeout: Duration = .seconds(12)

/// Locale-independent rendering of an optional integer field, shared by the
/// prompt and the signature so neither picks up localized digits or separators.
private func readinessIntText(_ value: Int?, fallback: String) -> String {
    guard let value else {
        return fallback
    }
    return String(value)
}

/// Generates a short readiness comment from the structured readiness data using
/// the on-device system language model. The class itself is never
/// `@available`-annotated so iOS 18 views can hold one; only the bodies that
/// touch FoundationModels are gated, and `LanguageModelSession` is created
/// inside the gated scope rather than stored.
@Observable
@MainActor
final class ReadinessCommentGenerator {
    /// The comment to show under the hero, or nil when disabled, unsupported, or
    /// generation has not produced anything usable yet.
    private(set) var comment: String?
    /// True while a generation is in flight for the current readiness state, so
    /// the hero can show a placeholder instead of the authored line it would
    /// otherwise swap away from a moment later.
    private(set) var isGenerating = false

    private var currentSignature: String?
    /// Bumped on every `refresh` entry: a task that resumes after a toggle-off,
    /// a cache clear, or a newer refresh sees a stale epoch and never publishes.
    private var generationEpoch = 0
    private var generationTask: Task<Void, Never>?

    var isSupported: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            // `supportsLocale` matters as much as availability: on an
            // unsupported-language device every request would silently fail,
            // which should read as Unavailable rather than On.
            return model.availability == .available && model.supportsLocale(.current)
        }
        return false
        #else
        return false
        #endif
    }

    func refresh(for readiness: ReadinessSummary, enabled: Bool) {
        generationTask?.cancel()
        generationTask = nil
        generationEpoch += 1
        isGenerating = false

        guard enabled, isSupported, readiness.score != nil else {
            comment = nil
            currentSignature = nil
            return
        }

        let locale = Locale.current
        let signature = ReadinessCommentSignature.signature(for: readiness, locale: locale)
        // The day is part of the signature, so this short-circuit is rollover-safe.
        guard signature != currentSignature || comment == nil else {
            return
        }

        if let cached = ReadinessCommentCache.load(), cached.signature == signature {
            comment = cached.text
            currentSignature = signature
            return
        }

        // A comment written for a different readiness state must not linger while
        // (or if) the replacement generates.
        comment = nil
        currentSignature = nil

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let epoch = generationEpoch
            let instructions = ReadinessCommentPromptBuilder.instructions(locale: locale)
            let prompt = ReadinessCommentPromptBuilder.prompt(for: readiness)
            isGenerating = true
            generationTask = Task { [weak self] in
                let text = await Self.generate(instructions: instructions, prompt: prompt)
                guard !Task.isCancelled, let self, epoch == self.generationEpoch else {
                    return
                }
                // A failed generation clears the placeholder; the hero falls back to
                // the authored line.
                self.isGenerating = false
                guard let text else {
                    return
                }
                self.comment = text
                self.currentSignature = signature
                ReadinessCommentCache.save(
                    ReadinessCommentCache.Record(signature: signature, text: text, generatedAt: Date())
                )
            }
        }
        #endif
    }

    #if canImport(FoundationModels)
    /// Races the response against a timeout. Both children build everything they
    /// need from `Sendable` strings, so the session never crosses an isolation
    /// boundary. Any failure — guardrail refusal, model unloading, timeout,
    /// empty text — resolves to nil and leaves the authored hero copy in place.
    @available(iOS 26.0, *)
    private static func generate(instructions: String, prompt: String) async -> String? {
        let text = await withTaskGroup(of: String?.self) { group in
            group.addTask {
                let session = LanguageModelSession(instructions: instructions)
                // Low temperature: the comment should carry the same key facts for
                // the same readiness state, varying only in wording.
                let options = GenerationOptions(temperature: 0.3, maximumResponseTokens: 90)
                return try? await session.respond(to: prompt, options: options).content
            }
            group.addTask {
                try? await Task.sleep(for: readinessCommentGenerationTimeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }

        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty ?? true) ? nil : trimmed
    }
    #endif
}

/// Builds the model instructions and prompt from readiness data. Plain type with
/// no FoundationModels dependency so it is unit-testable on any simulator.
enum ReadinessCommentPromptBuilder {
    static func instructions(locale: Locale = .current) -> String {
        """
        You rewrite the one short comment shown beneath a person's readiness level in a health app. The level and its number are already on screen above the comment.
        The prompt gives you a "Reference comment" — the app's own correct wording for today — plus the facts behind it. Your job is to reword the reference, not to write something new: keep exactly its meaning, its cause, and its advice, and change only the phrasing.
        Rules:
        - One or two sentences, no more than 30 words.
        - Keep every signal the reference names (for example "HRV is below baseline", "sleep was short", "today's workout"); the "Below usual" list confirms them. Never add a cause it does not name — no guessing at yesterday's workout, stress, illness, or morning movement — and never list what is fine.
        - Keep the reference's advice. It must agree with the "Training verdict" exactly: a "yes" verdict must encourage training, and only a "no" verdict may suggest rest. Never tell someone whose verdict is "yes" to rest, take it easy, or be careful.
        - No opening cheer or filler ("You're ready to train today!"): go straight to the signal, then the advice.
        - Speak about readiness only. Never mention any number, score, percentage, or points — none, not even the readiness score.
        - Address the reader as "you". Warm and direct, never clinical, in the same tone as the reference.
        - Never mention the app, Apple Health, data, components, the brief, the reference, or these instructions.
        - Reword naturally rather than repeating the reference verbatim.
        - Plain prose only: no emoji, no markdown, no lists, no headings.
        - Write the comment in \(languageName(for: locale)).
        """
    }

    /// The prompt is a rewrite brief, not raw data: the authored `heroExplanation`
    /// is handed over as the reference (it already encodes the right cause and
    /// advice for this band, driver, and drain), backed by the facts behind it and
    /// Body's training verdict, so the model only rewords. What is fine is
    /// deliberately not listed — area names ("autonomic", "training") mean nothing
    /// to the reader and only padded the comment. Every number (score, component
    /// scores, weights, impacts, drain points) is deliberately withheld — whatever
    /// the prompt contains tends to be quoted back, and the hero already shows the
    /// score.
    static func prompt(for readiness: ReadinessSummary) -> String {
        var lines: [String] = []
        lines.append("Reference comment: \(readiness.heroExplanation)")
        lines.append("Readiness level: \(readiness.status.title).")

        let flagged = readiness.drivers.filter { $0.kind != .mostlyTypical && $0.kind != .needsMoreData }
        let drain = readiness.activityDrainPoints ?? readiness.activityDrainMorningScore.map { $0 - (readiness.score ?? $0) } ?? 0
        let meaningfulDrain = drain >= ReadinessStatus.meaningfulActivityDrain

        var belowUsual = flagged.map(\.message)
        if drain > 0 {
            belowUsual.append(
                meaningfulDrain
                    ? "Today's workout has noticeably lowered readiness since the morning. That is training load, not poor recovery."
                    : "Light activity today has slightly lowered readiness since the morning."
            )
        }
        lines.append(belowUsual.isEmpty
            ? "Below usual: none."
            : "Below usual (most important first; name each one): " + belowUsual.joined(separator: " "))

        let verdict = trainingVerdict(for: readiness.status, meaningfulDrain: meaningfulDrain)
        lines.append("Training verdict: \(verdict.trains ? "yes" : "no").")
        lines.append("Advice: \(verdict.advice)")

        lines.append("Reword the reference comment now.")
        return lines.joined(separator: "\n")
    }

    /// Body's own verdict per readiness band, matching the authored hero copy:
    /// prime and high train, moderate trains with control, low favors easy work,
    /// poor rests. A meaningful same-day workout drain reframes moderate/low as
    /// earned training load — the day's work is done, so recover from here.
    static func trainingVerdict(
        for status: ReadinessStatus,
        meaningfulDrain: Bool
    ) -> (trains: Bool, advice: String) {
        switch status {
        case .prime:
            return (true, "Go ahead with your hardest training — you're primed for it.")
        case .high:
            return (true, "Train as planned; a normal session should feel good.")
        case .moderate:
            return meaningfulDrain
                ? (false, "You've done your work for today; focus on resting for the rest of the day.")
                : (true, "Training is fine, but keep the intensity controlled.")
        case .low:
            return meaningfulDrain
                ? (false, "That was a demanding session; rest and recover fully for the rest of the day.")
                : (false, "Favor easy work or a light day; recovery is still catching up.")
        case .poor:
            return (false, "Rest today, or keep it very light.")
        case .unavailable:
            return (false, "Not enough data yet to say; go by how you feel.")
        }
    }

    /// English name of the reader's language, for the "write in X" instruction.
    /// The script is only appended for Chinese (Simplified vs Traditional).
    /// Appending it in general is actively harmful: most Latin-script locales
    /// resolve to names like "English (Latin)", which the model reads as an
    /// instruction to write in Latin.
    private static func languageName(for locale: Locale) -> String {
        let english = Locale(identifier: "en_US_POSIX")
        guard let code = locale.language.languageCode?.identifier else {
            return "English"
        }
        if code == "zh", let script = locale.language.script?.identifier,
           let name = english.localizedString(forIdentifier: "\(code)-\(script)") {
            return name
        }
        return english.localizedString(forLanguageCode: code) ?? "English"
    }
}

/// Canonical joined string identifying the readiness state a comment was written
/// for. Deliberately not `Hasher`-based: `Hasher` is seeded per process, so a
/// hash cached on disk would never match after a relaunch.
enum ReadinessCommentSignature {
    static func signature(
        for readiness: ReadinessSummary,
        day: Date = Date(),
        locale: Locale = .current
    ) -> String {
        let calendar = Calendar.bodyGregorian
        let dayFormatter = BodyDateFormatterCache.formatter(
            dateFormat: "yyyy-MM-dd",
            calendar: calendar,
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: calendar.timeZone
        )
        let drivers = readiness.drivers
            .map { "\($0.kind.rawValue):\(String(format: "%.2f", $0.impact))" }
            .joined(separator: ",")
        let components = readiness.components
            .map { "\($0.kind.rawValue):\(readinessIntText($0.score, fallback: "-"))" }
            .joined(separator: ",")

        return [
            // Prompt-format version: bumping it invalidates every cached comment
            // written by an older prompt, forcing a regeneration.
            "v7",
            dayFormatter.string(from: day),
            readinessIntText(readiness.score, fallback: "-"),
            readiness.status.rawValue,
            readinessIntText(readiness.activityDrainPoints, fallback: "-"),
            readinessIntText(readiness.activityDrainMorningScore, fallback: "-"),
            drivers,
            components,
            locale.identifier
        ].joined(separator: "|")
    }
}

/// Persists the last generated comment so a relaunch shows it immediately
/// instead of waiting on (or re-paying for) a generation.
enum ReadinessCommentCache {
    static let defaultsKey = "readinessAICommentCache"

    struct Record: Codable, Equatable {
        var signature: String
        var text: String
        var generatedAt: Date
    }

    static func load() -> Record? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else {
            return nil
        }
        return try? JSONDecoder().decode(Record.self, from: data)
    }

    static func save(_ record: Record) {
        guard let data = try? JSONEncoder().encode(record) else {
            return
        }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}

/// The Apple Intelligence glyph, falling back to `sparkles` where the symbol
/// isn't in the running OS's SF Symbols catalog.
enum BodyAppleIntelligenceGlyph {
    static var symbolName: String {
        UIImage(systemName: "apple.intelligence") != nil ? "apple.intelligence" : "sparkles"
    }
}
