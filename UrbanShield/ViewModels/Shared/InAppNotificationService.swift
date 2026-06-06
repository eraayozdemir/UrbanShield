//
//  InAppNotificationService.swift
//  UrbanShield
//

import Foundation
import Supabase

enum InAppNotificationCategory: String, Codable {
    case request
    case assignment
    case announcement
    case report
    case moderation
    case coordinator
}

enum InAppNotificationLinkType: String, Codable {
    case request
    case report
    case announcement
}

enum InAppNotificationService {
    // Belirli bir kullanıcı için tek bir notification oluşturur.
    // Citizen’a request’inin kabul edildiği,
    // cancelled/completed olduğu veya değiştiği bildirilmesi gerektiğinde kullanılır.
    @MainActor
    static func notifyUser(
        userId: UUID,
        actorId: UUID? = nil,
        title: String,
        message: String,
        category: InAppNotificationCategory,
        linkType: InAppNotificationLinkType? = nil,
        linkId: UUID? = nil,
        requestId: UUID? = nil,
        reportId: UUID? = nil,
        announcementId: UUID? = nil
    ) async throws {
        try await notifyUsers(
            userIds: [userId],
            actorId: actorId,
            title: title,
            message: message,
            category: category,
            linkType: linkType,
            linkId: linkId,
            requestId: requestId,
            reportId: reportId,
            announcementId: announcementId
        )
    }

    @MainActor
    static func notifyUsers(
        userIds: [UUID],
        actorId: UUID? = nil,
        title: String,
        message: String,
        category: InAppNotificationCategory,
        linkType: InAppNotificationLinkType? = nil,
        linkId: UUID? = nil,
        requestId: UUID? = nil,
        reportId: UUID? = nil,
        announcementId: UUID? = nil
    ) async throws {
        let uniqueUserIds = Array(Set(userIds))
        guard !uniqueUserIds.isEmpty else { return }

        // Notification oluşturma SQL RPC’ye devredilir; böylece duplicate recipient,
        // RLS ve insert yapısı Supabase tarafında merkezi kalır.
        try await supabase
            .rpc(
                "create_in_app_notifications",
                params: InAppNotificationParams(
                    userIds: uniqueUserIds,
                    actorId: actorId,
                    title: title,
                    message: message,
                    category: category.rawValue,
                    linkType: linkType?.rawValue,
                    linkId: linkId,
                    requestId: requestId,
                    reportId: reportId,
                    announcementId: announcementId
                )
            )
            .execute()
    }

    @MainActor
    static func notifyRoles(
        roles: [UserRole],
        excludingUserId: UUID? = nil,
        actorId: UUID? = nil,
        title: String,
        message: String,
        category: InAppNotificationCategory,
        linkType: InAppNotificationLinkType? = nil,
        linkId: UUID? = nil,
        requestId: UUID? = nil,
        reportId: UUID? = nil,
        announcementId: UUID? = nil
    ) async throws {
        // Seçilen rollerdeki tüm kullanıcıları bulur, ardından notification satırlarını oluşturur.
        // Örnek: critical request -> coordinators ve admins.
        let recipients: [NotificationRecipientRecord] = try await supabase
            .rpc(
                "notification_recipient_ids_for_roles",
                params: NotificationRoleRecipientsParams(
                    roles: roles.map(\.rawValue),
                    excludingUserId: excludingUserId
                )
            )
            .execute()
            .value

        try await notifyUsers(
            userIds: recipients.map(\.id),
            actorId: actorId,
            title: title,
            message: message,
            category: category,
            linkType: linkType,
            linkId: linkId,
            requestId: requestId,
            reportId: reportId,
            announcementId: announcementId
        )
    }

    @MainActor
    static func notifyAdmins(
        actorId: UUID? = nil,
        title: String,
        message: String,
        category: InAppNotificationCategory,
        linkType: InAppNotificationLinkType? = nil,
        linkId: UUID? = nil,
        requestId: UUID? = nil,
        reportId: UUID? = nil
    ) async throws {
        try await notifyRoles(
            roles: [.admin],
            actorId: actorId,
            title: title,
            message: message,
            category: category,
            linkType: linkType,
            linkId: linkId,
            requestId: requestId,
            reportId: reportId
        )
    }

    @MainActor
    static func notifyCoordinatorsAndAdmins(
        actorId: UUID? = nil,
        title: String,
        message: String,
        category: InAppNotificationCategory,
        linkType: InAppNotificationLinkType? = nil,
        linkId: UUID? = nil,
        requestId: UUID? = nil
    ) async throws {
        try await notifyRoles(
            roles: [.coordinator, .admin],
            actorId: actorId,
            title: title,
            message: message,
            category: category,
            linkType: linkType,
            linkId: linkId,
            requestId: requestId
        )
    }
}

private struct NotificationRoleRecipientsParams: Encodable {
    let roles: [String]
    let excludingUserId: UUID?

    enum CodingKeys: String, CodingKey {
        case roles = "p_roles"
        case excludingUserId = "p_excluding_user_id"
    }
}

private struct InAppNotificationParams: Encodable {
    let userIds: [UUID]
    let actorId: UUID?
    let title: String
    let message: String
    let category: String
    let linkType: String?
    let linkId: UUID?
    let requestId: UUID?
    let reportId: UUID?
    let announcementId: UUID?

    enum CodingKeys: String, CodingKey {
        case userIds = "p_user_ids"
        case actorId = "p_actor_id"
        case title = "p_title"
        case message = "p_message"
        case category = "p_category"
        case linkType = "p_link_type"
        case linkId = "p_link_id"
        case requestId = "p_request_id"
        case reportId = "p_report_id"
        case announcementId = "p_announcement_id"
    }
}

private struct NotificationRecipientRecord: Decodable {
    let id: UUID
}
