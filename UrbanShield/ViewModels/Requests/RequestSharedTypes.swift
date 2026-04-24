//
//  RequestSharedTypes.swift
//  UrbanShield
//

import Foundation

enum HelpRequestType: String, CaseIterable, Identifiable, Codable {
    case earthquake
    case fire
    case flood
    case accident
    case medical
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .earthquake: return "Earthquake"
        case .fire: return "Fire"
        case .flood: return "Flood"
        case .accident: return "Accident"
        case .medical: return "Medical"
        case .other: return "Other"
        }
    }
}

enum HelpRequestUrgency: String, CaseIterable, Identifiable, Codable {
    case low
    case medium
    case high
    case critical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .critical: return "Critical"
        }
    }
}

enum HelpRequestStatus: String, CaseIterable, Identifiable, Codable {
    case open
    case confirmed
    case inProgress = "in_progress"
    case completed
    case cancelled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .open: return "Open"
        case .confirmed: return "Confirmed"
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        }
    }

    var shortTitle: String {
        switch self {
        case .open: return "Open"
        case .confirmed: return "Confirm"
        case .inProgress: return "Progress"
        case .completed: return "Done"
        case .cancelled: return "Cancel"
        }
    }

    var canBeCancelled: Bool {
        self == .open || self == .confirmed || self == .inProgress
    }

    var isActive: Bool {
        self == .open || self == .confirmed || self == .inProgress
    }
}

struct HelpRequestRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let citizenId: UUID
    let volunteerId: UUID?
    let requestType: String
    let description: String
    let urgencyLevel: String
    let status: String
    let latitude: Double
    let longitude: Double
    let createdAt: Date
    let updatedAt: Date
    let confirmedAt: Date?
    let completedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case citizenId = "citizen_id"
        case volunteerId = "volunteer_id"
        case requestType = "request_type"
        case description
        case urgencyLevel = "urgency_level"
        case status
        case latitude
        case longitude
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case confirmedAt = "confirmed_at"
        case completedAt = "completed_at"
    }

    var requestTypeValue: HelpRequestType {
        HelpRequestType(rawValue: requestType) ?? .other
    }

    var urgencyValue: HelpRequestUrgency {
        HelpRequestUrgency(rawValue: urgencyLevel) ?? .medium
    }

    var statusValue: HelpRequestStatus {
        HelpRequestStatus(rawValue: status) ?? .open
    }
}
