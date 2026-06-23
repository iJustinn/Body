//
//  BodyWorkoutType.swift
//  Body
//

import SwiftUI

enum BodyWorkoutType: String, Codable, CaseIterable, Identifiable {
    case americanFootball
    case archery
    case australianFootball
    case badminton
    case baseball
    case basketball
    case bowling
    case boxing
    case climbing
    case cricket
    case crossTraining
    case curling
    case walking
    case running
    case strengthTraining
    case functionalStrengthTraining
    case cycling
    case dance
    case danceInspiredTraining
    case elliptical
    case equestrianSports
    case fencing
    case fishing
    case golf
    case gymnastics
    case handball
    case yoga
    case swimming
    case hiking
    case hockey
    case hunting
    case lacrosse
    case martialArts
    case mindAndBody
    case mixedMetabolicCardioTraining
    case paddleSports
    case play
    case preparationAndReadiness
    case racquetball
    case rowing
    case rugby
    case sailing
    case skatingSports
    case snowSports
    case soccer
    case softball
    case squash
    case stairClimbing
    case surfingSports
    case tableTennis
    case tennis
    case trackAndField
    case volleyball
    case waterFitness
    case waterPolo
    case waterSports
    case wrestling
    case barre
    case coreTraining
    case crossCountrySkiing
    case downhillSkiing
    case flexibility
    case hiit
    case jumpRope
    case kickboxing
    case pilates
    case snowboarding
    case stairs
    case stepTraining
    case wheelchairWalkPace
    case wheelchairRunPace
    case taiChi
    case mixedCardio
    case handCycling
    case discSports
    case fitnessGaming
    case cardioDance
    case socialDance
    case pickleball
    case cooldown
    case swimBikeRun
    case transition
    case underwaterDiving
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .walking:
            return "Walk"
        case .running:
            return "Run"
        case .strengthTraining:
            return "Strength"
        case .functionalStrengthTraining:
            return "Functional Strength"
        case .cycling:
            return "Ride"
        case .swimming:
            return "Swim"
        case .hiking:
            return "Hike"
        case .hiit:
            return "HIIT"
        case .mindAndBody:
            return "Mind & Body"
        case .mixedMetabolicCardioTraining, .mixedCardio:
            return "Mixed Cardio"
        case .preparationAndReadiness:
            return "Readiness"
        case .taiChi:
            return "Tai Chi"
        case .swimBikeRun:
            return "Swim Bike Run"
        case .other:
            return "Workout"
        default:
            return rawValue.bodyWorkoutTitleCased()
        }
    }

    var symbolName: String {
        switch self {
        case .americanFootball:
            return "figure.american.football"
        case .archery:
            return "figure.archery"
        case .australianFootball:
            return "figure.australian.football"
        case .badminton:
            return "figure.badminton"
        case .baseball:
            return "figure.baseball"
        case .basketball:
            return "figure.basketball"
        case .bowling:
            return "figure.bowling"
        case .boxing:
            return "figure.boxing"
        case .climbing:
            return "figure.climbing"
        case .cricket:
            return "figure.cricket"
        case .crossTraining:
            return "figure.cross.training"
        case .curling:
            return "figure.curling"
        case .walking:
            return "figure.walk"
        case .running:
            return "figure.run"
        case .strengthTraining:
            return "figure.strengthtraining.traditional"
        case .functionalStrengthTraining:
            return "figure.strengthtraining.functional"
        case .cycling:
            return "figure.outdoor.cycle"
        case .dance, .danceInspiredTraining, .cardioDance, .socialDance:
            return "figure.dance"
        case .elliptical:
            return "figure.elliptical"
        case .equestrianSports:
            return "figure.equestrian.sports"
        case .fencing:
            return "figure.fencing"
        case .fishing:
            return "figure.fishing"
        case .golf:
            return "figure.golf"
        case .gymnastics:
            return "figure.gymnastics"
        case .handball:
            return "figure.handball"
        case .yoga, .mindAndBody:
            return "figure.mind.and.body"
        case .swimming, .swimBikeRun:
            return "figure.pool.swim"
        case .hiking:
            return "figure.hiking"
        case .hockey:
            return "figure.hockey"
        case .hunting:
            return "figure.hunting"
        case .lacrosse:
            return "figure.lacrosse"
        case .martialArts:
            return "figure.martial.arts"
        case .mixedMetabolicCardioTraining, .mixedCardio:
            return "figure.mixed.cardio"
        case .paddleSports, .waterSports:
            return "figure.open.water.swim"
        case .play:
            return "figure.play"
        case .preparationAndReadiness, .flexibility, .cooldown:
            return "figure.flexibility"
        case .racquetball:
            return "figure.racquetball"
        case .rowing:
            return "figure.outdoor.rowing"
        case .rugby:
            return "figure.rugby"
        case .sailing:
            return "figure.sailing"
        case .skatingSports:
            return "figure.skateboarding"
        case .snowSports:
            return "snowflake"
        case .soccer:
            return "figure.outdoor.soccer"
        case .softball:
            return "figure.softball"
        case .squash:
            return "figure.squash"
        case .stairClimbing:
            return "figure.stair.stepper"
        case .surfingSports:
            return "figure.surfing"
        case .tableTennis:
            return "figure.table.tennis"
        case .tennis:
            return "figure.tennis"
        case .trackAndField:
            return "figure.track.and.field"
        case .volleyball:
            return "figure.volleyball"
        case .waterFitness:
            return "figure.water.fitness"
        case .waterPolo:
            return "figure.waterpolo"
        case .wrestling:
            return "figure.wrestling"
        case .barre:
            return "figure.barre"
        case .coreTraining:
            return "figure.core.training"
        case .crossCountrySkiing:
            return "figure.skiing.crosscountry"
        case .downhillSkiing:
            return "figure.skiing.downhill"
        case .snowboarding:
            return "figure.snowboarding"
        case .hiit:
            return "figure.highintensity.intervaltraining"
        case .jumpRope:
            return "figure.jumprope"
        case .kickboxing:
            return "figure.kickboxing"
        case .pilates:
            return "figure.pilates"
        case .stairs:
            return "figure.stairs"
        case .stepTraining:
            return "figure.step.training"
        case .wheelchairWalkPace:
            return "figure.roll"
        case .wheelchairRunPace:
            return "figure.roll.runningpace"
        case .taiChi:
            return "figure.taichi"
        case .handCycling:
            return "figure.hand.cycling"
        case .discSports:
            return "figure.disc.sports"
        case .fitnessGaming:
            return "gamecontroller"
        case .pickleball:
            return "figure.pickleball"
        case .transition:
            return "figure.mixed.cardio"
        case .underwaterDiving:
            return "figure.open.water.swim"
        case .other:
            return "figure.mixed.cardio"
        }
    }

    var color: Color {
        Self.attachedWorkoutColor(hex: colorHex)
    }

    var calendarContentColor: Color {
        Self.luminance(hex: colorHex) > 0.58 ? Color.black.opacity(0.82) : .white
    }

    var colorHex: UInt32 {
        switch self {
        case .strengthTraining:
            return 0xB7172D
        case .functionalStrengthTraining:
            return 0xA34053
        case .coreTraining:
            return 0x662249
        case .walking, .wheelchairWalkPace:
            return 0x0D9099
        case .running, .wheelchairRunPace, .trackAndField:
            return 0x1B305D
        case .cycling, .handCycling:
            return 0xEE9D58
        case .hiking, .climbing, .stairClimbing, .stairs, .stepTraining:
            return 0x0A6F73
        case .swimming, .waterFitness, .waterPolo, .waterSports, .paddleSports, .sailing, .surfingSports, .underwaterDiving:
            return 0x6AA4BE
        case .hiit, .mixedCardio, .mixedMetabolicCardioTraining, .crossTraining, .elliptical, .jumpRope:
            return 0xF2926E
        case .yoga, .mindAndBody, .taiChi, .flexibility:
            return 0xAF7DAC
        case .preparationAndReadiness:
            return 0xEABCBA
        case .cooldown:
            return 0xFEE4D9
        case .snowSports, .crossCountrySkiing, .downhillSkiing, .snowboarding, .curling:
            return 0xF5DADF
        case .pilates, .barre:
            return 0xE3B6B1
        case .dance, .danceInspiredTraining, .cardioDance, .socialDance, .gymnastics, .skatingSports:
            return 0x835061
        case .boxing, .kickboxing, .martialArts, .wrestling:
            return 0x55152B
        case .basketball, .baseball, .softball, .handball, .volleyball:
            return 0xFEA382
        case .americanFootball, .australianFootball, .cricket, .hockey, .lacrosse, .rugby, .soccer:
            return 0x274E61
        case .badminton, .pickleball, .racquetball, .squash, .tableTennis, .tennis:
            return 0x423B63
        case .rowing:
            return 0x032E30
        case .golf, .discSports:
            return 0x021716
        case .equestrianSports, .fishing, .hunting:
            return 0x45184D
        case .archery:
            return 0x522C5C
        case .bowling:
            return 0x011230
        case .fencing:
            return 0x252F47
        case .play:
            return 0x150017
        case .fitnessGaming:
            return 0x2A104B
        case .swimBikeRun:
            return 0x373F5B
        case .transition:
            return 0x19192F
        case .other:
            return 0x8E8E93
        }
    }

    var displayPriority: Int {
        switch self {
        case .running:
            return 90
        case .strengthTraining:
            return 80
        case .functionalStrengthTraining, .coreTraining:
            return 78
        case .cycling:
            return 70
        case .hiking:
            return 60
        case .hiit:
            return 50
        case .swimming:
            return 40
        case .walking:
            return 30
        case .yoga:
            return 20
        case .other:
            return 10
        default:
            return 15
        }
    }

    static let attachedPaletteHexes: Set<UInt32> = [
        0x8E8E93, 0x45184D, 0x662249, 0xA34053, 0xEE9D58, 0xEABCBA,
        0x011230, 0x1B305D, 0x423B63, 0xAF7DAC, 0xF5DADF, 0xF2926E,
        0x021716, 0x032E30, 0x0A6F73, 0x0D9099, 0x6AA4BE, 0x274E61,
        0x19192F, 0x252F47, 0x373F5B, 0xFEA382, 0xB7172D, 0x55152B,
        0x150017, 0x2A104B, 0x522C5C, 0x835061, 0xE3B6B1, 0xFEE4D9
    ]

    private static func attachedWorkoutColor(hex: UInt32) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    private static func luminance(hex: UInt32) -> Double {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255

        return (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
    }
}

private extension String {
    func bodyWorkoutTitleCased() -> String {
        var words: [String] = []
        var current = ""

        for character in self {
            if character.isUppercase, !current.isEmpty {
                words.append(current)
                current = String(character)
            } else {
                current.append(character)
            }
        }

        if !current.isEmpty {
            words.append(current)
        }

        return words
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
