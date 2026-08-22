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

        for wave in BodyIntroWordLayout.Wave.allCases {
            for size in Self.sizes {
                let layout = BodyIntroWordLayout.make(in: size, wave: wave)
                XCTAssertEqual(layout.words.count, BodyIntroWordLayout.wordCount, "\(wave) \(size)")

                for word in layout.words {
                    XCTAssertTrue(matchesWordmarkPattern(word.text, wave: wave), "\(word.text) at \(wave) \(size)")
                }

                let distinctLengths = Set(layout.words.map(\.text.count))
                let expected = wave == .oh ? 5 : 3
                XCTAssertGreaterThanOrEqual(distinctLengths.count, expected, "\(wave) \(size)")
            }
        }
    }

    func testEveryWordRidesOneHorizontalLineFromOffLeftToOffRight() {
        for wave in BodyIntroWordLayout.Wave.allCases {
            for size in Self.sizes {
                let layout = BodyIntroWordLayout.make(in: size, wave: wave)

                for word in layout.words {
                    // Perfectly horizontal: one y for the whole slide.
                    XCTAssertEqual(word.origin.y, word.target.y, accuracy: 0.01, "\(wave) \(size) \(word.id)")
                    XCTAssertEqual(word.exit.y, word.target.y, accuracy: 0.01, "\(wave) \(size) \(word.id)")
                    // Fully off screen at both ends, centred in between.
                    // Fully hidden at both ends: the centre sits more than half a
                    // generous glyph width (0.8 em per character) plus the halo
                    // beyond the edge, so no edge of the word peeks in.
                    let halfWidth = word.fontSize * 0.8 * CGFloat(word.text.count) / 2 + BodyIntroWordLayout.haloRadius
                    XCTAssertLessThan(word.origin.x + halfWidth, 0, "origin \(word.origin) at \(wave) \(size)")
                    XCTAssertGreaterThan(word.exit.x - halfWidth, size.width, "exit \(word.exit) at \(wave) \(size)")
                    XCTAssertTrue(isInside(word.target, size: size), "target \(word.target) at \(wave) \(size)")
                    XCTAssertEqual(word.target.x, size.width / 2, accuracy: 0.01, "\(wave) \(size) \(word.id)")
                }
            }
        }
    }

    func testLayoutDelaysStayWithinStaggerSpan() {
        for wave in BodyIntroWordLayout.Wave.allCases {
            for size in Self.sizes {
                let layout = BodyIntroWordLayout.make(in: size, wave: wave)

                for word in layout.words {
                    XCTAssertGreaterThanOrEqual(word.delay, 0, "\(wave) \(size)")
                    XCTAssertLessThanOrEqual(word.delay, BodyIntroTimeline.staggerSpan, "\(wave) \(size)")
                }
            }
        }
    }

    func testLayoutIsDeterministicForTheSameSeedAndDiffersForAnotherSeed() {
        let size = CGSize(width: 402, height: 874)

        for wave in BodyIntroWordLayout.Wave.allCases {
            let first = BodyIntroWordLayout.make(in: size, wave: wave)
            let second = BodyIntroWordLayout.make(in: size, wave: wave)
            XCTAssertEqual(first, second, "\(wave)")

            let differentSeed = BodyIntroWordLayout.make(
                in: size,
                wave: wave,
                seed: wave.defaultSeed &+ 1
            )
            XCTAssertNotEqual(first, differentSeed, "\(wave)")
        }
    }

    func testTheTwoWavesDoNotShareGeometry() {
        let size = CGSize(width: 402, height: 874)
        let oh = BodyIntroWordLayout.make(in: size, wave: .oh)
        let my = BodyIntroWordLayout.make(in: size, wave: .my)

        XCTAssertNotEqual(oh.words.map(\.target), my.words.map(\.target))
        XCTAssertNotEqual(BodyIntroWordLayout.Wave.oh.defaultSeed, BodyIntroWordLayout.Wave.my.defaultSeed)
    }

    // MARK: - Timeline

    private static let timelineSize = CGSize(width: 402, height: 874)

    func testTheSecondWaveStartsWhileTheFirstIsStillCrossing() {
        XCTAssertEqual(BodyIntroTimeline.start(of: .oh), BodyIntroTimeline.startDelay, accuracy: 0.0001)
        XCTAssertEqual(
            BodyIntroTimeline.start(of: .my),
            BodyIntroTimeline.start(of: .oh) + BodyIntroTimeline.waveLead,
            accuracy: 0.0001
        )
        // The two fields overlap: the second is streaming in before the first
        // has finished leaving, so the background never shows through.
        XCTAssertGreaterThan(BodyIntroTimeline.start(of: .my), BodyIntroTimeline.start(of: .oh))
        XCTAssertLessThan(BodyIntroTimeline.start(of: .my), BodyIntroTimeline.end(of: .oh))

        for wave in BodyIntroWordLayout.Wave.allCases {
            XCTAssertEqual(
                BodyIntroTimeline.end(of: wave),
                BodyIntroTimeline.start(of: wave)
                    + BodyIntroTimeline.staggerSpan
                    + BodyIntroTimeline.slideDuration,
                accuracy: 0.0001,
                "\(wave)"
            )
        }

        XCTAssertEqual(
            BodyIntroTimeline.revealStart,
            BodyIntroTimeline.end(of: .my) - BodyIntroTimeline.revealLead,
            accuracy: 0.0001
        )
        XCTAssertEqual(BodyIntroTimeline.totalDuration, BodyIntroTimeline.end(of: .my))
    }

    func testAtTimeZeroEveryWordSitsAtItsOrigin() {
        for wave in BodyIntroWordLayout.Wave.allCases {
            let layout = BodyIntroWordLayout.make(in: Self.timelineSize, wave: wave)

            for word in layout.words {
                let frame = BodyIntroTimeline.frame(for: word, in: wave, at: 0)
                XCTAssertEqual(frame.position.x, word.origin.x, accuracy: 0.01, "\(wave) \(word.id)")
                XCTAssertEqual(frame.position.y, word.origin.y, accuracy: 0.01, "\(wave) \(word.id)")
            }
        }
    }

    func testHalfwayThroughItsSlideEveryWordIsCentredAndAtTheEndItIsGone() {
        for wave in BodyIntroWordLayout.Wave.allCases {
            let layout = BodyIntroWordLayout.make(in: Self.timelineSize, wave: wave)
            let start = BodyIntroTimeline.start(of: wave)

            for word in layout.words {
                let middle = BodyIntroTimeline.frame(
                    for: word,
                    in: wave,
                    at: start + word.delay + BodyIntroTimeline.slideDuration / 2
                )
                XCTAssertEqual(middle.position.x, word.target.x, accuracy: 0.01, "\(wave) \(word.id)")
                XCTAssertEqual(middle.position.y, word.target.y, accuracy: 0.01, "\(wave) \(word.id)")

                let done = BodyIntroTimeline.frame(
                    for: word,
                    in: wave,
                    at: start + word.delay + BodyIntroTimeline.slideDuration
                )
                XCTAssertEqual(done.position.x, word.exit.x, accuracy: 0.01, "\(wave) \(word.id)")
                XCTAssertEqual(done.position.y, word.exit.y, accuracy: 0.01, "\(wave) \(word.id)")
            }
        }
    }

    func testEveryWordSlidesRightAtAConstantSpeedWithNoVerticalMovement() {
        let step: TimeInterval = 0.05

        for wave in BodyIntroWordLayout.Wave.allCases {
            let layout = BodyIntroWordLayout.make(in: Self.timelineSize, wave: wave)
            let start = BodyIntroTimeline.start(of: wave)

            for word in layout.words {
                let wordStart = start + word.delay
                var previous = BodyIntroTimeline.frame(for: word, in: wave, at: wordStart).position
                var firstDelta: CGFloat?
                var elapsed = step

                while elapsed <= BodyIntroTimeline.slideDuration - step {
                    let position = BodyIntroTimeline.frame(
                        for: word,
                        in: wave,
                        at: wordStart + elapsed
                    ).position

                    XCTAssertGreaterThan(position.x, previous.x, "\(wave) \(word.id) at +\(elapsed)")
                    XCTAssertEqual(position.y, word.target.y, accuracy: 0.01, "\(wave) \(word.id)")

                    let delta = position.x - previous.x
                    if let firstDelta {
                        XCTAssertEqual(delta, firstDelta, accuracy: 0.01, "\(wave) \(word.id) at +\(elapsed)")
                    } else {
                        firstDelta = delta
                    }

                    previous = position
                    elapsed += step
                }
            }
        }
    }

    func testAtEachWaveEndEveryWordIsPastTheRightEdge() {
        for wave in BodyIntroWordLayout.Wave.allCases {
            let layout = BodyIntroWordLayout.make(in: Self.timelineSize, wave: wave)

            for word in layout.words {
                let frame = BodyIntroTimeline.frame(for: word, in: wave, at: BodyIntroTimeline.end(of: wave))
                XCTAssertGreaterThan(frame.position.x, Self.timelineSize.width, "\(wave) \(word.id)")
            }
        }
    }

    func testAtTotalDurationBothWavesAreGone() {
        let time = BodyIntroTimeline.totalDuration

        for wave in BodyIntroWordLayout.Wave.allCases {
            let layout = BodyIntroWordLayout.make(in: Self.timelineSize, wave: wave)

            for word in layout.words {
                let frame = BodyIntroTimeline.frame(for: word, in: wave, at: time)
                XCTAssertGreaterThan(frame.position.x, Self.timelineSize.width, "\(wave) \(word.id)")
            }
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

    /// `^o{2,}h$` for the first wave, `^my{1,4}$` for the second.
    private func matchesWordmarkPattern(_ text: String, wave: BodyIntroWordLayout.Wave) -> Bool {
        switch wave {
        case .oh:
            return text.range(of: "^o{2,}h$", options: .regularExpression) != nil
        case .my:
            return text.range(of: "^my{1,4}$", options: .regularExpression) != nil
        }
    }

    private func isInside(_ point: CGPoint, size: CGSize) -> Bool {
        point.x >= 0 && point.x <= size.width && point.y >= 0 && point.y <= size.height
    }
}
