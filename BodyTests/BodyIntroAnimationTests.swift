//
//  BodyIntroAnimationTests.swift
//  BodyTests
//

import XCTest
@testable import Body

final class BodyIntroAnimationTests: XCTestCase {

    // MARK: - Layout

    private static let sizes: [CGSize] = [
        CGSize(width: 402, height: 874),
        CGSize(width: 320, height: 568),
        CGSize(width: 1024, height: 1366),
        CGSize(width: 874, height: 402)
    ]

    func testLayoutHasExpectedWordCountAndTextShapeAtEverySize() {
        XCTAssertEqual(BodyIntroWordLayout.wordCount, 60)

        for size in Self.sizes {
            let layout = BodyIntroWordLayout.make(in: size)
            XCTAssertEqual(layout.words.count, BodyIntroWordLayout.wordCount, "\(size)")

            for word in layout.words {
                XCTAssertTrue(matchesWordmarkPattern(word.text), "\(word.text) at \(size)")
            }

            let distinctLengths = Set(layout.words.map(\.text.count))
            XCTAssertGreaterThanOrEqual(distinctLengths.count, 5, "\(size)")
        }
    }

    func testEveryWordRidesOneHorizontalLineFromOffLeftToOffRight() {
        for size in Self.sizes {
            let layout = BodyIntroWordLayout.make(in: size)

            for word in layout.words {
                // Perfectly horizontal: one y for the whole slide.
                XCTAssertEqual(word.origin.y, word.target.y, accuracy: 0.01, "\(size) \(word.id)")
                XCTAssertEqual(word.exit.y, word.target.y, accuracy: 0.01, "\(size) \(word.id)")
                // Fully off screen at both ends, centred in between.
                // Fully hidden at both ends: the centre sits more than half a
                // generous glyph width (0.8 em per character) plus the halo
                // beyond the edge, so no edge of the word peeks in.
                let halfWidth = word.fontSize * 0.8 * CGFloat(word.text.count) / 2 + BodyIntroWordLayout.haloRadius
                XCTAssertLessThan(word.origin.x + halfWidth, 0, "origin \(word.origin) at \(size)")
                XCTAssertGreaterThan(word.exit.x - halfWidth, size.width, "exit \(word.exit) at \(size)")
                XCTAssertTrue(isInside(word.target, size: size), "target \(word.target) at \(size)")
                XCTAssertEqual(word.target.x, size.width / 2, accuracy: 0.01, "\(size) \(word.id)")
            }
        }
    }

    func testLayoutDelaysStayWithinStaggerSpan() {
        for size in Self.sizes {
            let layout = BodyIntroWordLayout.make(in: size)

            for word in layout.words {
                XCTAssertGreaterThanOrEqual(word.delay, 0, "\(size)")
                XCTAssertLessThanOrEqual(word.delay, BodyIntroTimeline.staggerSpan, "\(size)")
            }
        }
    }

    func testLayoutIsDeterministicForTheSameSeedAndDiffersForAnotherSeed() {
        let size = CGSize(width: 402, height: 874)

        let first = BodyIntroWordLayout.make(in: size)
        let second = BodyIntroWordLayout.make(in: size)
        XCTAssertEqual(first, second)

        let differentSeed = BodyIntroWordLayout.make(
            in: size,
            seed: BodyIntroWordLayout.defaultSeed &+ 1
        )
        XCTAssertNotEqual(first, differentSeed)
    }

    func testEveryWordPicksOneOfTheFourPaletteColors() {
        XCTAssertEqual(BodyIntroWordLayout.paletteCount, 4)
        XCTAssertEqual(BodyIntroAnimationView.palette.count, BodyIntroWordLayout.paletteCount)

        let layout = BodyIntroWordLayout.make(in: CGSize(width: 402, height: 874))
        let used = Set(layout.words.map(\.colorIndex))
        for word in layout.words {
            XCTAssertTrue((0..<BodyIntroWordLayout.paletteCount).contains(word.colorIndex), "\(word.id)")
            XCTAssertGreaterThanOrEqual(word.opacity, 0.7, "\(word.id)")
        }
        // All four colors show up in a 60 word field.
        XCTAssertEqual(used.count, BodyIntroWordLayout.paletteCount)
    }

    // MARK: - Timeline

    private static let timelineSize = CGSize(width: 402, height: 874)

    func testTheWaveRunsFromStartDelayToTheEndOfTheLastSlide() {
        XCTAssertEqual(BodyIntroTimeline.start, BodyIntroTimeline.startDelay, accuracy: 0.0001)
        XCTAssertEqual(
            BodyIntroTimeline.end,
            BodyIntroTimeline.start
                + BodyIntroTimeline.staggerSpan
                + BodyIntroTimeline.slideDuration,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            BodyIntroTimeline.revealStart,
            BodyIntroTimeline.end - BodyIntroTimeline.revealLead,
            accuracy: 0.0001
        )
        XCTAssertEqual(BodyIntroTimeline.totalDuration, BodyIntroTimeline.end)
    }

    func testAtTimeZeroEveryWordSitsAtItsOrigin() {
        let layout = BodyIntroWordLayout.make(in: Self.timelineSize)

        for word in layout.words {
            let frame = BodyIntroTimeline.frame(for: word, at: 0)
            XCTAssertEqual(frame.position.x, word.origin.x, accuracy: 0.01, "\(word.id)")
            XCTAssertEqual(frame.position.y, word.origin.y, accuracy: 0.01, "\(word.id)")
        }
    }

    func testHalfwayThroughItsSlideEveryWordIsCentredAndAtTheEndItIsGone() {
        let layout = BodyIntroWordLayout.make(in: Self.timelineSize)
        let start = BodyIntroTimeline.start

        for word in layout.words {
            let middle = BodyIntroTimeline.frame(
                for: word,
                at: start + word.delay + BodyIntroTimeline.slideDuration / 2
            )
            XCTAssertEqual(middle.position.x, word.target.x, accuracy: 0.01, "\(word.id)")
            XCTAssertEqual(middle.position.y, word.target.y, accuracy: 0.01, "\(word.id)")

            let done = BodyIntroTimeline.frame(
                for: word,
                at: start + word.delay + BodyIntroTimeline.slideDuration
            )
            XCTAssertEqual(done.position.x, word.exit.x, accuracy: 0.01, "\(word.id)")
            XCTAssertEqual(done.position.y, word.exit.y, accuracy: 0.01, "\(word.id)")
        }
    }

    func testEveryWordSlidesRightAtAConstantSpeedWithNoVerticalMovement() {
        let step: TimeInterval = 0.05
        let layout = BodyIntroWordLayout.make(in: Self.timelineSize)
        let start = BodyIntroTimeline.start

        for word in layout.words {
            let wordStart = start + word.delay
            var previous = BodyIntroTimeline.frame(for: word, at: wordStart).position
            var firstDelta: CGFloat?
            var elapsed = step

            while elapsed <= BodyIntroTimeline.slideDuration - step {
                let position = BodyIntroTimeline.frame(
                    for: word,
                    at: wordStart + elapsed
                ).position

                XCTAssertGreaterThan(position.x, previous.x, "\(word.id) at +\(elapsed)")
                XCTAssertEqual(position.y, word.target.y, accuracy: 0.01, "\(word.id)")

                let delta = position.x - previous.x
                if let firstDelta {
                    XCTAssertEqual(delta, firstDelta, accuracy: 0.01, "\(word.id) at +\(elapsed)")
                } else {
                    firstDelta = delta
                }

                previous = position
                elapsed += step
            }
        }
    }

    func testAtTheWaveEndEveryWordIsPastTheRightEdge() {
        let layout = BodyIntroWordLayout.make(in: Self.timelineSize)

        for word in layout.words {
            let frame = BodyIntroTimeline.frame(for: word, at: BodyIntroTimeline.end)
            XCTAssertGreaterThan(frame.position.x, Self.timelineSize.width, "\(word.id)")
        }
    }

    func testAtTotalDurationTheWholeFieldIsGone() {
        let time = BodyIntroTimeline.totalDuration
        let layout = BodyIntroWordLayout.make(in: Self.timelineSize)

        for word in layout.words {
            let frame = BodyIntroTimeline.frame(for: word, at: time)
            XCTAssertGreaterThan(frame.position.x, Self.timelineSize.width, "\(word.id)")
        }
    }

    func testRevealProgressRampsFromZeroToOneAndIsMonotonic() {
        XCTAssertEqual(BodyIntroTimeline.revealProgress(at: 0), 0)
        XCTAssertEqual(
            BodyIntroTimeline.revealProgress(at: BodyIntroTimeline.revealStart - 0.01),
            0
        )
        XCTAssertEqual(
            BodyIntroTimeline.revealProgress(
                at: BodyIntroTimeline.revealStart + BodyIntroTimeline.revealDuration
            ),
            1,
            accuracy: 0.0001
        )

        var previous = -Double.infinity
        var time: TimeInterval = 0
        while time <= BodyIntroTimeline.totalDuration + 0.5 {
            let progress = BodyIntroTimeline.revealProgress(at: time)
            XCTAssertGreaterThanOrEqual(progress, previous - 0.0001, "at t=\(time)")
            previous = progress
            time += 0.01
        }
    }

    func testIsFinishedFlipsExactlyAtTotalDuration() {
        XCTAssertFalse(BodyIntroTimeline.isFinished(at: BodyIntroTimeline.totalDuration - 0.001))
        XCTAssertTrue(BodyIntroTimeline.isFinished(at: BodyIntroTimeline.totalDuration))
    }

    // MARK: - Helpers

    /// `^o{2,}h$`: "o" repeated at least twice, then a closing "h".
    private func matchesWordmarkPattern(_ text: String) -> Bool {
        text.range(of: "^o{2,}h$", options: .regularExpression) != nil
    }

    private func isInside(_ point: CGPoint, size: CGSize) -> Bool {
        point.x >= 0 && point.x <= size.width && point.y >= 0 && point.y <= size.height
    }
}
