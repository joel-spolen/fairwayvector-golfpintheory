//
//  SeedData.swift
//  fairwayvector-hcp-projection
//

import Foundation
import SwiftData

enum SeedData {
    static func loadIfNeeded(modelContext: ModelContext) {
        let profiles = (try? modelContext.fetch(FetchDescriptor<PlayerProfile>())) ?? []
        for profile in profiles where profile.name == "Demo Player" {
            modelContext.delete(profile)
        }

        let rounds = (try? modelContext.fetch(FetchDescriptor<GolfRound>())) ?? []
        for round in rounds where round.notes == "Demo round" || round.notes == "Stableford example that changes handicap" {
            modelContext.delete(round)
        }
    }
}