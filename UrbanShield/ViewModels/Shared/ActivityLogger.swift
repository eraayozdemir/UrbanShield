//
//  ActivityLogger.swift
//  UrbanShield
//

import Foundation
import Supabase

enum ActivityActionType: String, CaseIterable, Identifiable, Codable {
    case requestCreated = "request_created"
    case requestCancelled = "request_cancelled"
    case requestConfirmed = "request_confirmed"
    case requestStarted = "request_started"
    case requestCompleted = "request_completed"
    case requestStatusUpdated = "request_status_updated"
    case requestPriorityUpdated = "request_priority_updated"
    case volunteerAssigned = "volunteer_assigned"
    case supplySupportLogged = "supply_support_logged"
    case announcementPublished = "announcement_published"
    case suspiciousReportSubmitted = "suspicious_report_submitted"
    case suspiciousReportReviewed = "suspicious_report_reviewed"
    case roleUpdated = "role_updated"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .requestCreated: return "Request Created"
        case .requestCancelled: return "Request Cancelled"
        case .requestConfirmed: return "Request Confirmed"
        case .requestStarted: return "Request Started"
        case .requestCompleted: return "Request Completed"
        case .requestStatusUpdated: return "Request Status"
        case .requestPriorityUpdated: return "Request Priority"
        case .volunteerAssigned: return "Volunteer Assigned"
        case .supplySupportLogged: return "Supply Support"
        case .announcementPublished: return "Announcement"
        case .suspiciousReportSubmitted: return "Report Submitted"
        case .suspiciousReportReviewed: return "Report Reviewed"
        case .roleUpdated: return "Role Updated"
        }
    }
}

enum ActivityTargetType: String, Codable {
    case request
    case report
    case user
    case announcement
    case supplyAction = "supply_action"
}

struct ActivityLogRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let actorId: UUID
    let actorRole: String
    let actionType: String
    let targetType: String
    let targetId: UUID?
    let requestId: UUID?
    let reportId: UUID?
    let targetUserId: UUID?
    let message: String
    let metadata: [String: String]?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case actorId = "actor_id"
        case actorRole = "actor_role"
        case actionType = "action_type"
        case targetType = "target_type"
        case targetId = "target_id"
        case requestId = "request_id"
        case reportId = "report_id"
        case targetUserId = "target_user_id"
        case message
        case metadata
        case createdAt = "created_at"
    }

    var actionValue: ActivityActionType? {
        ActivityActionType(rawValue: actionType)
    }
}

enum ActivityLogger {
    @MainActor
    static func log(
        actor: User,
        action: ActivityActionType,
        targetType: ActivityTargetType,
        targetId: UUID? = nil,
        requestId: UUID? = nil,
        reportId: UUID? = nil,
        targetUserId: UUID? = nil,
        message: String,
        metadata: [String: String]? = nil
    ) async throws {
        try await supabase
            .from("activity_logs")
            .insert(
                ActivityLogInsert(
                    actorId: actor.id,
                    actorRole: actor.role.rawValue,
                    actionType: action.rawValue,
                    targetType: targetType.rawValue,
                    targetId: targetId,
                    requestId: requestId,
                    reportId: reportId,
                    targetUserId: targetUserId,
                    message: message,
                    metadata: metadata
                )
            )
            .execute()
    }

    @MainActor
    static func log(
        actorId: UUID,
        actorRole: UserRole,
        action: ActivityActionType,
        targetType: ActivityTargetType,
        targetId: UUID? = nil,
        requestId: UUID? = nil,
        reportId: UUID? = nil,
        targetUserId: UUID? = nil,
        message: String,
        metadata: [String: String]? = nil
    ) async throws {
        try await supabase
            .from("activity_logs")
            .insert(
                ActivityLogInsert(
                    actorId: actorId,
                    actorRole: actorRole.rawValue,
                    actionType: action.rawValue,
                    targetType: targetType.rawValue,
                    targetId: targetId,
                    requestId: requestId,
                    reportId: reportId,
                    targetUserId: targetUserId,
                    message: message,
                    metadata: metadata
                )
            )
            .execute()
    }
}

private struct ActivityLogInsert: Encodable {
    let actorId: UUID
    let actorRole: String
    let actionType: String
    let targetType: String
    let targetId: UUID?
    let requestId: UUID?
    let reportId: UUID?
    let targetUserId: UUID?
    let message: String
    let metadata: [String: String]?

    enum CodingKeys: String, CodingKey {
        case actorId = "actor_id"
        case actorRole = "actor_role"
        case actionType = "action_type"
        case targetType = "target_type"
        case targetId = "target_id"
        case requestId = "request_id"
        case reportId = "report_id"
        case targetUserId = "target_user_id"
        case message
        case metadata
    }
}
