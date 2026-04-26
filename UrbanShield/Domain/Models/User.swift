//
//  User.swift
//  UrbanShield
//

import Foundation

/// The domain model representing an authenticated user with a profile.
/// This is what the app works with — no Supabase types leak into the domain.
struct User: Equatable, Sendable {
    let id: UUID
    let email: String
    let fullName: String
    let role: UserRole
    let availabilityStatus: VolunteerAvailability
    let volunteerSkills: [VolunteerSkill]
    let createdAt: Date
}

enum VolunteerAvailability: String, Codable, CaseIterable, Identifiable, Sendable {
    case available
    case busy
    case offline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .available: return "Available"
        case .busy: return "Busy"
        case .offline: return "Offline"
        }
    }
}

enum VolunteerSkill: String, Codable, CaseIterable, Identifiable, Sendable {
    case medical
    case searchRescue = "search_rescue"
    case transport
    case fireResponse = "fire_response"
    case floodRescue = "flood_rescue"
    case logistics
    case shelter
    case communication
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .medical: return "Medical"
        case .searchRescue: return "Search & Rescue"
        case .transport: return "Transport"
        case .fireResponse: return "Fire Response"
        case .floodRescue: return "Flood Rescue"
        case .logistics: return "Logistics"
        case .shelter: return "Shelter"
        case .communication: return "Communication"
        case .other: return "Other"
        }
    }

    func supports(_ requestType: HelpRequestType) -> Bool {
        switch requestType {
        case .earthquake:
            return self == .searchRescue || self == .medical || self == .logistics || self == .shelter
        case .fire:
            return self == .fireResponse || self == .medical || self == .searchRescue
        case .flood:
            return self == .floodRescue || self == .transport || self == .searchRescue || self == .medical
        case .accident:
            return self == .medical || self == .transport || self == .searchRescue
        case .medical:
            return self == .medical || self == .transport
        case .other:
            return true
        }
    }
}
