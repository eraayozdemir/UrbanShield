//
//  CoordinatorDashboardViewModel.swift
//  UrbanShield
//

import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class CoordinatorDashboardViewModel {

    var requests: [HelpRequestRecord] = []
    var availableVolunteers: [ProfileUserRecord] = []
    var activityLogs: [CoordinationLogRecord] = []
    var isLoading = false
    var updatingRequestId: UUID?
    var errorMessage: String?
    var successMessage: String?

    func loadRequests(currentUser: User?) async {
        errorMessage = nil
        successMessage = nil

        guard currentUser?.role == .coordinator || currentUser?.role == .admin else {
            errorMessage = "Only coordinators can view the dashboard."
            requests = []
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let loadedRequests: [HelpRequestRecord] = try await supabase
                .from("help_requests")
                .select()
                .order("updated_at", ascending: false)
                .execute()
                .value

            availableVolunteers = try await supabase
                .from("profiles")
                .select()
                .eq("availability_status", value: VolunteerAvailability.available.rawValue)
                .order("full_name", ascending: true)
                .execute()
                .value

            requests = loadedRequests.sorted(by: sortForCoordinator)
            activityLogs = (try? await loadRecentLogs()) ?? []
        } catch where error.isCancellation {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updatePriority(
        request: HelpRequestRecord,
        priority: HelpRequestPriority,
        currentUser: User?
    ) async {
        errorMessage = nil
        successMessage = nil

        guard let currentUser, currentUser.role == .coordinator || currentUser.role == .admin else {
            errorMessage = "Only coordinators can update request priority."
            return
        }

        updatingRequestId = request.id
        defer { updatingRequestId = nil }

        do {
            let updatedRequest: HelpRequestRecord = try await supabase
                .from("help_requests")
                .update(
                    RequestPriorityUpdate(
                        priorityLevel: priority.rawValue,
                        updatedAt: Date()
                    )
                )
                .eq("id", value: request.id.uuidString)
                .select()
                .single()
                .execute()
                .value

            try await insertLog(
                requestId: request.id,
                coordinatorId: currentUser.id,
                actionType: .priorityUpdated,
                oldValue: request.priorityValue.rawValue,
                newValue: priority.rawValue,
                message: "Priority changed from \(request.priorityValue.title) to \(priority.title)."
            )

            try? await ActivityLogger.log(
                actor: currentUser,
                action: .requestPriorityUpdated,
                targetType: .request,
                targetId: request.id,
                requestId: request.id,
                message: "Priority changed from \(request.priorityValue.title) to \(priority.title).",
                metadata: [
                    "old_priority": request.priorityValue.rawValue,
                    "new_priority": priority.rawValue
                ]
            )

            if let index = requests.firstIndex(where: { $0.id == request.id }) {
                requests[index] = updatedRequest
                requests.sort(by: sortForCoordinator)
            }
            activityLogs = try await loadRecentLogs()

            successMessage = "Priority updated to \(priority.title)."
        } catch where error.isCancellation {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateStatus(
        request: HelpRequestRecord,
        status: HelpRequestStatus,
        currentUser: User?
    ) async {
        errorMessage = nil
        successMessage = nil

        guard let currentUser, currentUser.role == .coordinator || currentUser.role == .admin else {
            errorMessage = "Only coordinators can update request status."
            return
        }

        guard allowedStatusTargets(for: request).contains(status) else {
            errorMessage = "This status change is not available for the selected request."
            return
        }

        updatingRequestId = request.id
        defer { updatingRequestId = nil }

        do {
            let now = Date()
            let updatedRequest: HelpRequestRecord = try await supabase
                .from("help_requests")
                .update(
                    CoordinatorRequestStatusUpdate(
                        status: status.rawValue,
                        updatedAt: now,
                        completedAt: status == .completed ? now : nil
                    )
                )
                .eq("id", value: request.id.uuidString)
                .select()
                .single()
                .execute()
                .value

            try await syncAssignmentsAndVolunteer(for: request, nextStatus: status, updatedAt: now)

            try await insertLog(
                requestId: request.id,
                coordinatorId: currentUser.id,
                actionType: .statusUpdated,
                oldValue: request.statusValue.rawValue,
                newValue: status.rawValue,
                message: "Status changed from \(request.statusValue.title) to \(status.title)."
            )

            try? await ActivityLogger.log(
                actor: currentUser,
                action: .requestStatusUpdated,
                targetType: .request,
                targetId: request.id,
                requestId: request.id,
                message: "Status changed from \(request.statusValue.title) to \(status.title).",
                metadata: [
                    "old_status": request.statusValue.rawValue,
                    "new_status": status.rawValue
                ]
            )

            if let index = requests.firstIndex(where: { $0.id == request.id }) {
                requests[index] = updatedRequest
                requests.sort(by: sortForCoordinator)
            }
            activityLogs = try await loadRecentLogs()

            successMessage = "Status updated to \(status.title)."
        } catch where error.isCancellation {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func allowedStatusTargets(for request: HelpRequestRecord) -> [HelpRequestStatus] {
        switch request.statusValue {
        case .open:
            return [.cancelled]
        case .confirmed:
            return [.inProgress, .cancelled]
        case .inProgress:
            return [.completed, .cancelled]
        case .completed, .cancelled:
            return []
        }
    }

    func eligibleVolunteers(for request: HelpRequestRecord) -> [ProfileUserRecord] {
        availableVolunteers.filter { volunteer in
            volunteer.id != request.citizenId
                && volunteer.availabilityValue == .available
                && !volunteer.skillsValue.isEmpty
                && volunteer.skillsValue.contains { $0.supports(request.requestTypeValue) }
        }
    }

    func assignVolunteer(
        request: HelpRequestRecord,
        volunteer: ProfileUserRecord,
        currentUser: User?
    ) async {
        errorMessage = nil
        successMessage = nil

        guard let currentUser, currentUser.role == .coordinator || currentUser.role == .admin else {
            errorMessage = "Only coordinators can assign volunteers."
            return
        }

        guard request.statusValue.acceptsVolunteers else {
            errorMessage = "This request is no longer accepting volunteers."
            return
        }

        guard volunteer.availabilityValue == .available,
              volunteer.skillsValue.contains(where: { $0.supports(request.requestTypeValue) }) else {
            errorMessage = "This volunteer is not available or does not match the request type."
            return
        }

        updatingRequestId = request.id
        defer { updatingRequestId = nil }

        do {
            let activeAssignments: [HelpRequestVolunteerRecord] = try await supabase
                .from("help_request_volunteers")
                .select()
                .eq("volunteer_id", value: volunteer.id.uuidString)
                .in("status", values: [
                    HelpRequestStatus.confirmed.rawValue,
                    HelpRequestStatus.inProgress.rawValue
                ])
                .execute()
                .value

            guard activeAssignments.isEmpty else {
                errorMessage = "\(volunteer.fullName) already has an active task."
                return
            }

            let now = Date()

            try await supabase
                .from("help_request_volunteers")
                .insert(
                    CoordinatorVolunteerAssignmentInsert(
                        requestId: request.id,
                        volunteerId: volunteer.id,
                        status: HelpRequestStatus.confirmed.rawValue
                    )
                )
                .execute()

            let updatedRequest: HelpRequestRecord = try await supabase
                .from("help_requests")
                .update(
                    CoordinatorRequestAssignmentUpdate(
                        volunteerId: volunteer.id,
                        status: HelpRequestStatus.confirmed.rawValue,
                        confirmedAt: now,
                        updatedAt: now
                    )
                )
                .eq("id", value: request.id.uuidString)
                .in("status", values: [
                    HelpRequestStatus.open.rawValue,
                    HelpRequestStatus.confirmed.rawValue
                ])
                .select()
                .single()
                .execute()
                .value

            try await supabase
                .from("profiles")
                .update(
                    CoordinatorAssignedVolunteerProfileUpdate(
                        role: UserRole.volunteer.rawValue,
                        availabilityStatus: VolunteerAvailability.busy.rawValue
                    )
                )
                .eq("id", value: volunteer.id.uuidString)
                .execute()

            try await insertLog(
                requestId: request.id,
                coordinatorId: currentUser.id,
                actionType: .volunteerAssigned,
                oldValue: request.statusValue.rawValue,
                newValue: HelpRequestStatus.confirmed.rawValue,
                message: "\(volunteer.fullName) assigned to \(request.requestTypeValue.title)."
            )

            try? await ActivityLogger.log(
                actor: currentUser,
                action: .volunteerAssigned,
                targetType: .request,
                targetId: request.id,
                requestId: request.id,
                targetUserId: volunteer.id,
                message: "\(volunteer.fullName) assigned to \(request.requestTypeValue.title).",
                metadata: [
                    "old_status": request.statusValue.rawValue,
                    "new_status": HelpRequestStatus.confirmed.rawValue,
                    "volunteer_name": volunteer.fullName
                ]
            )

            if let index = requests.firstIndex(where: { $0.id == request.id }) {
                requests[index] = updatedRequest
                requests.sort(by: sortForCoordinator)
            }
            availableVolunteers.removeAll { $0.id == volunteer.id }
            activityLogs = try await loadRecentLogs()
            successMessage = "\(volunteer.fullName) assigned to \(request.requestTypeValue.title)."
        } catch where error.isCancellation {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sortForCoordinator(_ lhs: HelpRequestRecord, _ rhs: HelpRequestRecord) -> Bool {
        if lhs.statusValue.isActive != rhs.statusValue.isActive {
            return lhs.statusValue.isActive
        }

        if lhs.priorityValue.sortRank != rhs.priorityValue.sortRank {
            return lhs.priorityValue.sortRank > rhs.priorityValue.sortRank
        }

        return lhs.updatedAt > rhs.updatedAt
    }

    private func syncAssignmentsAndVolunteer(
        for request: HelpRequestRecord,
        nextStatus: HelpRequestStatus,
        updatedAt: Date
    ) async throws {
        guard nextStatus == .inProgress || nextStatus == .completed || nextStatus == .cancelled else {
            return
        }

        let activeAssignments: [HelpRequestVolunteerRecord] = try await supabase
            .from("help_request_volunteers")
            .select()
            .eq("request_id", value: request.id.uuidString)
            .in("status", values: [
                HelpRequestStatus.confirmed.rawValue,
                HelpRequestStatus.inProgress.rawValue
            ])
            .execute()
            .value

        for assignment in activeAssignments {
            switch nextStatus {
            case .inProgress:
                try await supabase
                    .from("help_request_volunteers")
                    .update(
                        CoordinatorAssignmentStartUpdate(
                            status: nextStatus.rawValue,
                            startedAt: updatedAt,
                            updatedAt: updatedAt
                        )
                    )
                    .eq("id", value: assignment.id.uuidString)
                    .execute()
            case .completed:
                try await supabase
                    .from("help_request_volunteers")
                    .update(
                        CoordinatorAssignmentCompletionUpdate(
                            status: nextStatus.rawValue,
                            completedAt: updatedAt,
                            updatedAt: updatedAt
                        )
                    )
                    .eq("id", value: assignment.id.uuidString)
                    .execute()
                try await markVolunteerAvailableIfNeeded(assignment.volunteerId)
            case .cancelled:
                try await supabase
                    .from("help_request_volunteers")
                    .update(
                        CoordinatorAssignmentCancellationUpdate(
                            status: nextStatus.rawValue,
                            updatedAt: updatedAt
                        )
                    )
                    .eq("id", value: assignment.id.uuidString)
                    .execute()
                try await markVolunteerAvailableIfNeeded(assignment.volunteerId)
            default:
                break
            }
        }
    }

    private func markVolunteerAvailableIfNeeded(_ volunteerId: UUID) async throws {
        try await supabase
            .from("profiles")
            .update(CoordinatorVolunteerAvailabilityUpdate(availabilityStatus: VolunteerAvailability.available.rawValue))
            .eq("id", value: volunteerId.uuidString)
            .execute()
    }

    private func loadRecentLogs() async throws -> [CoordinationLogRecord] {
        try await supabase
            .from("coordination_logs")
            .select()
            .order("created_at", ascending: false)
            .limit(8)
            .execute()
            .value
    }

    private func insertLog(
        requestId: UUID,
        coordinatorId: UUID,
        actionType: CoordinationActionType,
        oldValue: String?,
        newValue: String?,
        message: String
    ) async throws {
        try await supabase
            .from("coordination_logs")
            .insert(
                CoordinationLogInsert(
                    requestId: requestId,
                    coordinatorId: coordinatorId,
                    actionType: actionType.rawValue,
                    oldValue: oldValue,
                    newValue: newValue,
                    message: message
                )
            )
            .execute()
    }
}

enum CoordinationActionType: String, Codable, CaseIterable, Identifiable {
    case priorityUpdated = "priority_updated"
    case statusUpdated = "status_updated"
    case volunteerAssigned = "volunteer_assigned"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .priorityUpdated: return "Priority"
        case .statusUpdated: return "Status"
        case .volunteerAssigned: return "Assignment"
        }
    }
}

struct CoordinationLogRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let requestId: UUID
    let coordinatorId: UUID
    let actionType: String
    let oldValue: String?
    let newValue: String?
    let message: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case requestId = "request_id"
        case coordinatorId = "coordinator_id"
        case actionType = "action_type"
        case oldValue = "old_value"
        case newValue = "new_value"
        case message
        case createdAt = "created_at"
    }

    var actionValue: CoordinationActionType {
        CoordinationActionType(rawValue: actionType) ?? .statusUpdated
    }
}

private struct CoordinationLogInsert: Encodable {
    let requestId: UUID
    let coordinatorId: UUID
    let actionType: String
    let oldValue: String?
    let newValue: String?
    let message: String

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case coordinatorId = "coordinator_id"
        case actionType = "action_type"
        case oldValue = "old_value"
        case newValue = "new_value"
        case message
    }
}

private struct CoordinatorVolunteerAssignmentInsert: Encodable {
    let requestId: UUID
    let volunteerId: UUID
    let status: String

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case volunteerId = "volunteer_id"
        case status
    }
}

private struct CoordinatorRequestAssignmentUpdate: Encodable {
    let volunteerId: UUID
    let status: String
    let confirmedAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case volunteerId = "volunteer_id"
        case status
        case confirmedAt = "confirmed_at"
        case updatedAt = "updated_at"
    }
}

private struct CoordinatorAssignedVolunteerProfileUpdate: Encodable {
    let role: String
    let availabilityStatus: String

    enum CodingKeys: String, CodingKey {
        case role
        case availabilityStatus = "availability_status"
    }
}

private struct CoordinatorRequestStatusUpdate: Encodable {
    let status: String
    let updatedAt: Date
    let completedAt: Date?

    enum CodingKeys: String, CodingKey {
        case status
        case updatedAt = "updated_at"
        case completedAt = "completed_at"
    }
}

private struct CoordinatorAssignmentStartUpdate: Encodable {
    let status: String
    let startedAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case status
        case startedAt = "started_at"
        case updatedAt = "updated_at"
    }
}

private struct CoordinatorAssignmentCompletionUpdate: Encodable {
    let status: String
    let completedAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case status
        case completedAt = "completed_at"
        case updatedAt = "updated_at"
    }
}

private struct CoordinatorAssignmentCancellationUpdate: Encodable {
    let status: String
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case status
        case updatedAt = "updated_at"
    }
}

private struct CoordinatorVolunteerAvailabilityUpdate: Encodable {
    let availabilityStatus: String

    enum CodingKeys: String, CodingKey {
        case availabilityStatus = "availability_status"
    }
}

private struct RequestPriorityUpdate: Encodable {
    let priorityLevel: String
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case priorityLevel = "priority_level"
        case updatedAt = "updated_at"
    }
}
