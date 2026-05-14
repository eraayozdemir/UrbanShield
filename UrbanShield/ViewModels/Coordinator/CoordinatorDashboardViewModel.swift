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

        guard currentUser?.role == .coordinator || currentUser?.role == .admin else {
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

            if let index = requests.firstIndex(where: { $0.id == request.id }) {
                requests[index] = updatedRequest
                requests.sort(by: sortForCoordinator)
            }

            successMessage = "Priority updated to \(priority.title)."
        } catch where error.isCancellation {
            return
        } catch {
            errorMessage = error.localizedDescription
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

        guard currentUser?.role == .coordinator || currentUser?.role == .admin else {
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

            if let index = requests.firstIndex(where: { $0.id == request.id }) {
                requests[index] = updatedRequest
                requests.sort(by: sortForCoordinator)
            }
            availableVolunteers.removeAll { $0.id == volunteer.id }
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

private struct RequestPriorityUpdate: Encodable {
    let priorityLevel: String
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case priorityLevel = "priority_level"
        case updatedAt = "updated_at"
    }
}
