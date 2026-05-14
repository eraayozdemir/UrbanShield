//
//  AdminActivityLogViewModel.swift
//  UrbanShield
//

import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class AdminActivityLogViewModel {

    var logs: [ActivityLogRecord] = []
    var usersById: [UUID: ProfileUserRecord] = [:]
    var selectedRole: ActivityRoleFilter = .all
    var selectedAction: ActivityActionFilter = .all
    var searchText = ""
    var isLoading = false
    var errorMessage: String?

    var filteredLogs: [ActivityLogRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return logs.filter { log in
            selectedRole.includes(log.actorRole)
                && selectedAction.includes(log.actionType)
                && (
                    query.isEmpty
                    || log.message.lowercased().contains(query)
                    || actorName(for: log).lowercased().contains(query)
                    || log.actionType.lowercased().contains(query)
                    || log.targetType.lowercased().contains(query)
                    || log.targetId?.uuidString.lowercased().contains(query) == true
                    || log.requestId?.uuidString.lowercased().contains(query) == true
                    || log.reportId?.uuidString.lowercased().contains(query) == true
                )
        }
    }

    var todayCount: Int {
        logs.filter { Calendar.current.isDateInToday($0.createdAt) }.count
    }

    var adminActionCount: Int {
        logs.filter { $0.actorRole == UserRole.admin.rawValue }.count
    }

    var requestActionCount: Int {
        logs.filter { $0.targetType == ActivityTargetType.request.rawValue }.count
    }

    var hasActiveFilters: Bool {
        selectedRole != .all || selectedAction != .all || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func resetFilters() {
        selectedRole = .all
        selectedAction = .all
        searchText = ""
    }

    func load(currentUser: User?) async {
        errorMessage = nil

        guard currentUser?.role == .admin else {
            errorMessage = "Only admins can view activity logs."
            logs = []
            usersById = [:]
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            logs = try await supabase
                .from("activity_logs")
                .select()
                .order("created_at", ascending: false)
                .limit(150)
                .execute()
                .value

            let actorIds = Set(logs.map(\.actorId))
            let targetUserIds = Set(logs.compactMap(\.targetUserId))
            let allUserIds = Array(actorIds.union(targetUserIds).map(\.uuidString))

            guard !allUserIds.isEmpty else {
                usersById = [:]
                return
            }

            let users: [ProfileUserRecord] = try await supabase
                .from("profiles")
                .select()
                .in("id", values: allUserIds)
                .execute()
                .value

            usersById = Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0) })
        } catch where error.isCancellation {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func actorName(for log: ActivityLogRecord) -> String {
        usersById[log.actorId]?.fullName ?? shortId(log.actorId)
    }

    func targetUserName(for log: ActivityLogRecord) -> String? {
        guard let targetUserId = log.targetUserId else { return nil }
        return usersById[targetUserId]?.fullName ?? shortId(targetUserId)
    }

    func shortId(_ id: UUID?) -> String {
        guard let id else { return "None" }
        return "#\(id.uuidString.prefix(8))"
    }
}

enum ActivityRoleFilter: String, CaseIterable, Identifiable {
    case all
    case citizen
    case volunteer
    case coordinator
    case admin

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .citizen: return "Citizen"
        case .volunteer: return "Volunteer"
        case .coordinator: return "Coord"
        case .admin: return "Admin"
        }
    }

    func includes(_ role: String) -> Bool {
        self == .all || rawValue == role
    }
}

enum ActivityActionFilter: String, CaseIterable, Identifiable {
    case all
    case requests
    case assignments
    case reports
    case operations

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .requests: return "Requests"
        case .assignments: return "Assign"
        case .reports: return "Reports"
        case .operations: return "Ops"
        }
    }

    func includes(_ action: String) -> Bool {
        guard self != .all else { return true }

        switch self {
        case .all:
            return true
        case .requests:
            return [
                ActivityActionType.requestCreated.rawValue,
                ActivityActionType.requestCancelled.rawValue,
                ActivityActionType.requestConfirmed.rawValue,
                ActivityActionType.requestStarted.rawValue,
                ActivityActionType.requestCompleted.rawValue,
                ActivityActionType.requestStatusUpdated.rawValue,
                ActivityActionType.requestPriorityUpdated.rawValue
            ].contains(action)
        case .assignments:
            return action == ActivityActionType.volunteerAssigned.rawValue
        case .reports:
            return [
                ActivityActionType.suspiciousReportSubmitted.rawValue,
                ActivityActionType.suspiciousReportReviewed.rawValue
            ].contains(action)
        case .operations:
            return [
                ActivityActionType.supplySupportLogged.rawValue,
                ActivityActionType.announcementPublished.rawValue,
                ActivityActionType.roleUpdated.rawValue
            ].contains(action)
        }
    }
}
