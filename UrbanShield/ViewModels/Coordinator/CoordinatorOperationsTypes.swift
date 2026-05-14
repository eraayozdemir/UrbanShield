//
//  CoordinatorOperationsTypes.swift
//  UrbanShield
//

import Foundation

enum SupplySupportType: String, CaseIterable, Identifiable, Codable {
    case food
    case water
    case medical
    case shelter
    case transport
    case rescueEquipment = "rescue_equipment"
    case communication
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .food: return "Food"
        case .water: return "Water"
        case .medical: return "Medical"
        case .shelter: return "Shelter"
        case .transport: return "Transport"
        case .rescueEquipment: return "Rescue Equipment"
        case .communication: return "Communication"
        case .other: return "Other"
        }
    }
}

enum SupplyActionStatus: String, CaseIterable, Identifiable, Codable {
    case planned
    case dispatched
    case delivered
    case cancelled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .planned: return "Planned"
        case .dispatched: return "Dispatched"
        case .delivered: return "Delivered"
        case .cancelled: return "Cancelled"
        }
    }
}

enum EmergencyAnnouncementSeverity: String, CaseIterable, Identifiable, Codable {
    case info
    case warning
    case critical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .info: return "Info"
        case .warning: return "Warning"
        case .critical: return "Critical"
        }
    }
}

enum EmergencyAnnouncementAudience: String, CaseIterable, Identifiable, Codable {
    case all
    case citizens
    case volunteers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .citizens: return "Citizens"
        case .volunteers: return "Volunteers"
        }
    }
}

enum SuspiciousReportCategory: String, CaseIterable, Identifiable, Codable {
    case fakeRequest = "fake_request"
    case abuse
    case spam
    case unsafeBehavior = "unsafe_behavior"
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fakeRequest: return "Fake Request"
        case .abuse: return "Abuse"
        case .spam: return "Spam"
        case .unsafeBehavior: return "Unsafe Behavior"
        case .other: return "Other"
        }
    }
}

enum SuspiciousReportStatus: String, CaseIterable, Identifiable, Codable {
    case open
    case reviewing
    case resolved
    case dismissed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .open: return "Open"
        case .reviewing: return "Reviewing"
        case .resolved: return "Resolved"
        case .dismissed: return "Dismissed"
        }
    }
}

struct SupplySupportActionRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let requestId: UUID
    let coordinatorId: UUID
    let supportType: String
    let status: String
    let quantity: String?
    let notes: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case requestId = "request_id"
        case coordinatorId = "coordinator_id"
        case supportType = "support_type"
        case status
        case quantity
        case notes
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var supportTypeValue: SupplySupportType {
        SupplySupportType(rawValue: supportType) ?? .other
    }

    var statusValue: SupplyActionStatus {
        SupplyActionStatus(rawValue: status) ?? .planned
    }
}

struct EmergencyAnnouncementRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let coordinatorId: UUID
    let title: String
    let message: String
    let severity: String
    let audience: String
    let isActive: Bool
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case coordinatorId = "coordinator_id"
        case title
        case message
        case severity
        case audience
        case isActive = "is_active"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var severityValue: EmergencyAnnouncementSeverity {
        EmergencyAnnouncementSeverity(rawValue: severity) ?? .info
    }

    var audienceValue: EmergencyAnnouncementAudience {
        EmergencyAnnouncementAudience(rawValue: audience) ?? .all
    }
}

struct SuspiciousActivityReportRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let reporterId: UUID
    let requestId: UUID?
    let category: String
    let details: String
    let status: String
    let reviewedBy: UUID?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case reporterId = "reporter_id"
        case requestId = "request_id"
        case category
        case details
        case status
        case reviewedBy = "reviewed_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var categoryValue: SuspiciousReportCategory {
        SuspiciousReportCategory(rawValue: category) ?? .other
    }

    var statusValue: SuspiciousReportStatus {
        SuspiciousReportStatus(rawValue: status) ?? .open
    }
}

enum ModerationActionType: String, CaseIterable, Identifiable, Codable {
    case statusUpdated = "status_updated"
    case requestCancelled = "request_cancelled"
    case reportResolved = "report_resolved"
    case reportDismissed = "report_dismissed"
    case noteAdded = "note_added"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .statusUpdated: return "Status Updated"
        case .requestCancelled: return "Request Cancelled"
        case .reportResolved: return "Report Resolved"
        case .reportDismissed: return "Report Dismissed"
        case .noteAdded: return "Note Added"
        }
    }
}

struct ModerationActionRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let adminId: UUID
    let reportId: UUID?
    let requestId: UUID?
    let targetUserId: UUID?
    let actionType: String
    let notes: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case adminId = "admin_id"
        case reportId = "report_id"
        case requestId = "request_id"
        case targetUserId = "target_user_id"
        case actionType = "action_type"
        case notes
        case createdAt = "created_at"
    }

    var actionValue: ModerationActionType {
        ModerationActionType(rawValue: actionType) ?? .noteAdded
    }
}
