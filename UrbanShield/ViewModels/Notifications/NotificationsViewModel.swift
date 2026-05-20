//
//  NotificationsViewModel.swift
//  UrbanShield
//

import Foundation
import Observation
import Supabase

struct InAppNotificationRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    let actorId: UUID?
    let title: String
    let message: String
    let category: String
    let linkType: String?
    let linkId: UUID?
    let requestId: UUID?
    let reportId: UUID?
    let announcementId: UUID?
    let isRead: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case actorId = "actor_id"
        case title
        case message
        case category
        case linkType = "link_type"
        case linkId = "link_id"
        case requestId = "request_id"
        case reportId = "report_id"
        case announcementId = "announcement_id"
        case isRead = "is_read"
        case createdAt = "created_at"
    }

    var categoryValue: InAppNotificationCategory {
        InAppNotificationCategory(rawValue: category) ?? .request
    }

    var linkTypeValue: InAppNotificationLinkType? {
        guard let linkType else { return nil }
        return InAppNotificationLinkType(rawValue: linkType)
    }
}

@MainActor
@Observable
final class NotificationsViewModel {
    var notifications: [InAppNotificationRecord] = []
    var unreadCount = 0
    var isLoading = false
    var errorMessage: String?
    var successMessage: String?
    var cacheMessage: String?

    private let realtimeSubscription = RealtimeRefreshSubscription()
    private var pollingTask: Task<Void, Never>?

    func load(currentUser: User?) async {
        errorMessage = nil
        cacheMessage = nil

        guard let currentUser else {
            notifications = []
            unreadCount = 0
            errorMessage = "You must be signed in to view notifications."
            return
        }

        let cacheKey = "notifications.\(currentUser.id.uuidString)"
        if notifications.isEmpty, let cached = OfflineCacheStore.load([InAppNotificationRecord].self, forKey: cacheKey) {
            notifications = cached.value
            unreadCount = cached.value.filter { !$0.isRead }.count
            cacheMessage = cachedMessage(savedAt: cached.savedAt)
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let loaded: [InAppNotificationRecord] = try await supabase
                .from("notifications")
                .select()
                .eq("user_id", value: currentUser.id.uuidString)
                .order("created_at", ascending: false)
                .limit(100)
                .execute()
                .value

            notifications = loaded
            unreadCount = loaded.filter { !$0.isRead }.count
            cacheMessage = nil
            OfflineCacheStore.save(loaded, forKey: cacheKey)
        } catch where error.isCancellation {
            return
        } catch {
            if let cached = OfflineCacheStore.load([InAppNotificationRecord].self, forKey: cacheKey) {
                notifications = cached.value
                unreadCount = cached.value.filter { !$0.isRead }.count
                cacheMessage = cachedMessage(savedAt: cached.savedAt)
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    func loadUnreadCount(currentUser: User?) async {
        guard let currentUser else {
            unreadCount = 0
            return
        }

        do {
            let unreadRows: [NotificationIdRecord] = try await supabase
                .from("notifications")
                .select("id")
                .eq("user_id", value: currentUser.id.uuidString)
                .eq("is_read", value: false)
                .limit(100)
                .execute()
                .value

            unreadCount = unreadRows.count
        } catch {
            unreadCount = notifications.filter { !$0.isRead }.count
        }
    }

    func markAsRead(_ notification: InAppNotificationRecord, currentUser: User?) async {
        guard let currentUser, !notification.isRead else { return }

        do {
            try await supabase
                .from("notifications")
                .update(NotificationReadUpdate(isRead: true))
                .eq("id", value: notification.id.uuidString)
                .eq("user_id", value: currentUser.id.uuidString)
                .execute()

            if let index = notifications.firstIndex(where: { $0.id == notification.id }) {
                let refreshed: [InAppNotificationRecord] = try await supabase
                    .from("notifications")
                    .select()
                    .eq("id", value: notification.id.uuidString)
                    .limit(1)
                    .execute()
                    .value

                if let updated = refreshed.first {
                    notifications[index] = updated
                }
            }
            unreadCount = max(0, unreadCount - 1)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func markAllAsRead(currentUser: User?) async {
        errorMessage = nil
        successMessage = nil
        cacheMessage = nil

        guard let currentUser else {
            errorMessage = "You must be signed in to update notifications."
            return
        }

        do {
            try await supabase
                .from("notifications")
                .update(NotificationReadUpdate(isRead: true))
                .eq("user_id", value: currentUser.id.uuidString)
                .eq("is_read", value: false)
                .execute()

            await load(currentUser: currentUser)
            successMessage = "Notifications marked as read."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startRealtime(currentUser: User?) async {
        guard let currentUser else { return }

        do {
            try await realtimeSubscription.start(
                channelName: "notifications-\(currentUser.id.uuidString)",
                registrations: [
                    RealtimePostgresChangeRegistration(
                        table: "notifications",
                        filter: "user_id=eq.\(currentUser.id.uuidString)"
                    )
                ]
            ) { [weak self, currentUser] in
                await self?.load(currentUser: currentUser)
            }
        } catch {
            // Manual refresh remains available if realtime is unavailable.
        }
    }

    func startPollingFallback(currentUser: User?) {
        guard let currentUser, pollingTask == nil else { return }

        pollingTask = Task { [weak self, currentUser] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 10_000_000_000)
                } catch {
                    return
                }

                guard !Task.isCancelled else { return }
                await self?.load(currentUser: currentUser)
            }
        }
    }

    func stopRealtime() {
        pollingTask?.cancel()
        pollingTask = nil

        Task {
            await realtimeSubscription.stop()
        }
    }

    private func cachedMessage(savedAt: Date) -> String {
        "Offline mode: showing saved notifications from \(savedAt.formatted(date: .abbreviated, time: .shortened))."
    }
}

private struct NotificationIdRecord: Decodable {
    let id: UUID
}

private struct NotificationReadUpdate: Encodable {
    let isRead: Bool

    enum CodingKeys: String, CodingKey {
        case isRead = "is_read"
    }
}
