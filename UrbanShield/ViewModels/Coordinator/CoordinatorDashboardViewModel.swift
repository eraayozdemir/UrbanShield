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

    // Coordinator/admin kullanıcılarına gösterilen dashboard verisi.
    var requests: [HelpRequestRecord] = []
    var availableVolunteers: [ProfileUserRecord] = []
    var activeVolunteerCounts: [UUID: Int] = [:]
    var activityLogs: [CoordinationLogRecord] = []
    var isLoading = false
    var updatingRequestId: UUID?
    var errorMessage: String?
    var successMessage: String?
    private let realtimeSubscription = RealtimeRefreshSubscription()

    // Operasyonel takip için tüm request kayıtlarını yükler. Citizen ekranlarından farklı olarak,
    // coordinator/admin completed/cancelled kayıtları da görebilir.
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
            // Temel request listesi.
            let loadedRequests: [HelpRequestRecord] = try await supabase
                .from("help_requests")
                .select()
                .order("updated_at", ascending: false)
                .execute()
                .value

            let requestIds = loadedRequests.map { $0.id.uuidString }
            let activeAssignments: [HelpRequestVolunteerRecord]
            if requestIds.isEmpty {
                activeAssignments = []
            } else {
                // Aktif assignment sayıları 0/1, 2/3 vb. şekilde gösterilir.
                activeAssignments = try await supabase
                    .from("help_request_volunteers")
                    .select()
                    .in("request_id", values: requestIds)
                    .in("status", values: [
                        HelpRequestStatus.confirmed.rawValue,
                        HelpRequestStatus.inProgress.rawValue
                    ])
                    .execute()
                    .value
            }

            activeVolunteerCounts = Dictionary(
                grouping: activeAssignments,
                by: \.requestId
            ).mapValues(\.count)

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

    func startRealtime(currentUser: User?) async {
        guard currentUser?.role == .coordinator || currentUser?.role == .admin else { return }

        do {
            // Realtime refresh, coordinator ekranını canlıya yakın tutar ve
            // her citizen/volunteer işleminden sonra manuel yenileme gerektirmez.
            try await realtimeSubscription.start(
                channelName: "coordinator-dashboard-\(currentUser?.id.uuidString ?? "unknown")",
                registrations: [
                    RealtimePostgresChangeRegistration(table: "help_requests"),
                    RealtimePostgresChangeRegistration(table: "help_request_volunteers"),
                    RealtimePostgresChangeRegistration(table: "coordination_logs")
                ]
            ) { [weak self, currentUser] in
                await self?.loadRequests(currentUser: currentUser)
            }
        } catch {
            // Realtime geçici olarak çalışmazsa manuel yenileme kullanılmaya devam eder.
        }
    }

    func stopRealtime() {
        Task {
            await realtimeSubscription.stop()
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
            // Status güncellemesi RPC kullanır çünkü completed/cancelled işlemleri
            // request satırını, assignment satırlarını ve volunteer uygunluğunu birlikte etkileyebilir.
            let updatedRequests: [HelpRequestRecord] = try await supabase
                .rpc(
                    "coordinator_update_help_request_status",
                    params: CoordinatorStatusUpdateParams(
                        requestId: request.id,
                        status: status.rawValue
                    )
                )
                .execute()
                .value

            guard let updatedRequest = updatedRequests.first else {
                errorMessage = "Request could not be updated."
                return
            }

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

            let recipientIds = [
                request.citizenId,
                request.volunteerId
            ].compactMap { $0 }
            try? await InAppNotificationService.notifyUsers(
                userIds: recipientIds,
                actorId: currentUser.id,
                title: "Request status updated",
                message: "\(request.requestTypeValue.title) request moved to \(status.title).",
                category: .coordinator,
                linkType: .request,
                linkId: request.id,
                requestId: request.id
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
        // Coordinator yalnızca geçerli sonraki durumlara geçiş yapabilir.
        // Bu, lifecycle akışını UI tarafındaki geçersiz atlamalara karşı korur.
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
        guard requestHasVolunteerCapacity(request) else { return [] }

        return availableVolunteers.filter { volunteer in
            // Assignment seçici için eşleşme kuralı.
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

        guard requestHasVolunteerCapacity(request) else {
            errorMessage = "This request already has the maximum number of active volunteers for its urgency."
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
            // RPC öncesi yapılan güncel kontroller, eski dashboard verisiyle
            // başka cihazda busy olmuş bir volunteer atanmasını engeller.
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

            let requestActiveAssignments: [HelpRequestVolunteerRecord] = try await supabase
                .from("help_request_volunteers")
                .select()
                .eq("request_id", value: request.id.uuidString)
                .in("status", values: [
                    HelpRequestStatus.confirmed.rawValue,
                    HelpRequestStatus.inProgress.rawValue
                ])
                .execute()
                .value

            guard requestActiveAssignments.count < request.volunteerCapacity else {
                errorMessage = "This request already has the maximum number of active volunteers for its urgency."
                return
            }

            let updatedStatus = request.statusValue == .open
                ? HelpRequestStatus.confirmed.rawValue
                : request.statusValue.rawValue

            let updatedRequests: [HelpRequestRecord] = try await supabase
                .rpc(
                    "coordinator_assign_volunteer_to_request",
                    params: CoordinatorAssignVolunteerParams(
                        requestId: request.id,
                        volunteerId: volunteer.id
                    )
                )
                .execute()
                .value

            guard let updatedRequest = updatedRequests.first else {
                errorMessage = "Volunteer could not be assigned."
                return
            }

            try await insertLog(
                requestId: request.id,
                coordinatorId: currentUser.id,
                actionType: .volunteerAssigned,
                oldValue: request.statusValue.rawValue,
                newValue: updatedStatus,
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
                    "new_status": updatedStatus,
                    "volunteer_name": volunteer.fullName
                ]
            )

            try? await InAppNotificationService.notifyUsers(
                userIds: [request.citizenId, volunteer.id],
                actorId: currentUser.id,
                title: "Volunteer assigned",
                message: "\(volunteer.fullName) was assigned to \(request.requestTypeValue.title).",
                category: .assignment,
                linkType: .request,
                linkId: request.id,
                requestId: request.id
            )


            if let index = requests.firstIndex(where: { $0.id == request.id }) {
                requests[index] = updatedRequest
                requests.sort(by: sortForCoordinator)
            }
            activeVolunteerCounts[request.id] = requestActiveAssignments.count + 1
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
        // Dashboard önceliği: önce aktif requestler, sonra critical/high urgency,
        // ardından yakın zamanda güncellenen kayıtlar.
        if lhs.statusValue.isActive != rhs.statusValue.isActive {
            return lhs.statusValue.isActive
        }

        if lhs.urgencyValue.sortRank != rhs.urgencyValue.sortRank {
            return lhs.urgencyValue.sortRank > rhs.urgencyValue.sortRank
        }

        return lhs.updatedAt > rhs.updatedAt
    }

    private func requestHasVolunteerCapacity(_ request: HelpRequestRecord) -> Bool {
        (activeVolunteerCounts[request.id] ?? 0) < request.volunteerCapacity
    }

    func activeVolunteerCount(for request: HelpRequestRecord) -> Int {
        activeVolunteerCounts[request.id] ?? 0
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

private struct CoordinatorStatusUpdateParams: Encodable {
    let requestId: UUID
    let status: String

    enum CodingKeys: String, CodingKey {
        case requestId = "p_request_id"
        case status = "p_status"
    }
}

private struct CoordinatorAssignVolunteerParams: Encodable {
    let requestId: UUID
    let volunteerId: UUID

    enum CodingKeys: String, CodingKey {
        case requestId = "p_request_id"
        case volunteerId = "p_volunteer_id"
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
