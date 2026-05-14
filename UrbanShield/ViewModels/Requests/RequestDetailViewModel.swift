//
//  RequestDetailViewModel.swift
//  UrbanShield
//

import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class RequestDetailViewModel {

    var request: HelpRequestRecord?
    var isLoading: Bool = false
    var isCancelling: Bool = false
    var isUpdatingStatus: Bool = false
    var errorMessage: String?

    func loadRequest(id: UUID, currentUserId: UUID? = nil) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let loadedRequests: [HelpRequestRecord] = try await supabase
                .from("help_requests")
                .select()
                .eq("id", value: id.uuidString)
                .limit(1)
                .execute()
                .value

            guard let loadedRequest = loadedRequests.first else {
                request = nil
                return
            }

            if let currentUserId,
               loadedRequest.citizenId != currentUserId,
               let assignment = try await loadAssignment(requestId: id, volunteerId: currentUserId) {
                request = loadedRequest.applyingVolunteerAssignment(assignment)
            } else {
                request = loadedRequest
            }
        } catch where error.isCancellation {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancelRequest(id: UUID, citizenId: UUID?) async {
        errorMessage = nil

        guard let citizenId else {
            errorMessage = "You must be signed in to cancel a request."
            return
        }

        guard request?.statusValue.canBeCancelled == true else {
            errorMessage = "Only open, confirmed, or in-progress requests can be cancelled."
            return
        }

        isCancelling = true
        defer { isCancelling = false }

        do {
            let now = Date()
            request = try await supabase
                .from("help_requests")
                .update(RequestCancellationUpdate(status: HelpRequestStatus.cancelled.rawValue, updatedAt: now))
                .eq("id", value: id.uuidString)
                .eq("citizen_id", value: citizenId.uuidString)
                .select()
                .single()
                .execute()
                .value

            try? await supabase
                .from("help_request_volunteers")
                .update(VolunteerAssignmentCancellationUpdate(status: HelpRequestStatus.cancelled.rawValue, updatedAt: now))
                .eq("request_id", value: id.uuidString)
                .in("status", values: [
                    HelpRequestStatus.confirmed.rawValue,
                    HelpRequestStatus.inProgress.rawValue
                ])
                .execute()
        } catch where error.isCancellation {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startVolunteerWork(id: UUID, volunteerId: UUID?) async {
        await updateVolunteerStatus(
            id: id,
            volunteerId: volunteerId,
            from: .confirmed,
            to: .inProgress,
            errorText: "Only confirmed requests can be moved to in progress."
        )
    }

    func completeVolunteerWork(id: UUID, volunteerId: UUID?) async {
        await updateVolunteerStatus(
            id: id,
            volunteerId: volunteerId,
            from: .inProgress,
            to: .completed,
            errorText: "Only in-progress requests can be completed."
        )
    }

    private func updateVolunteerStatus(
        id: UUID,
        volunteerId: UUID?,
        from currentStatus: HelpRequestStatus,
        to nextStatus: HelpRequestStatus,
        errorText: String
    ) async {
        errorMessage = nil

        guard let volunteerId else {
            errorMessage = "You must be signed in to update this task."
            return
        }

        guard request?.statusValue == currentStatus else {
            errorMessage = errorText
            return
        }

        isUpdatingStatus = true
        defer { isUpdatingStatus = false }

        do {
            guard let assignment = try await loadAssignment(requestId: id, volunteerId: volunteerId),
                  assignment.statusValue == currentStatus else {
                errorMessage = errorText
                return
            }

            let now = Date()
            let update = RequestStatusUpdate(
                status: nextStatus.rawValue,
                updatedAt: now,
                completedAt: nextStatus == .completed ? now : nil
            )

            if nextStatus == .inProgress {
                try await supabase
                    .from("help_request_volunteers")
                    .update(
                        VolunteerAssignmentStartUpdate(
                            status: nextStatus.rawValue,
                            startedAt: now,
                            updatedAt: now
                        )
                    )
                    .eq("id", value: assignment.id.uuidString)
                    .eq("status", value: currentStatus.rawValue)
                    .execute()
            } else {
                try await supabase
                    .from("help_request_volunteers")
                    .update(
                        VolunteerAssignmentCompletionUpdate(
                            status: nextStatus.rawValue,
                            completedAt: now,
                            updatedAt: now
                        )
                    )
                    .eq("id", value: assignment.id.uuidString)
                    .eq("status", value: currentStatus.rawValue)
                    .execute()
            }

            try? await supabase
                .from("help_requests")
                .update(update)
                .eq("id", value: id.uuidString)
                .in("status", values: [
                    HelpRequestStatus.open.rawValue,
                    HelpRequestStatus.confirmed.rawValue,
                    HelpRequestStatus.inProgress.rawValue
                ])
                .execute()

            if nextStatus == .completed {
                try? await supabase
                    .from("profiles")
                    .update(
                        CompletedVolunteerProfileUpdate(
                            role: UserRole.citizen.rawValue,
                            availabilityStatus: VolunteerAvailability.available.rawValue
                        )
                    )
                    .eq("id", value: volunteerId.uuidString)
                    .execute()
            }

            await loadRequest(id: id, currentUserId: volunteerId)
        } catch where error.isCancellation {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadAssignment(requestId: UUID, volunteerId: UUID) async throws -> HelpRequestVolunteerRecord? {
        let assignments: [HelpRequestVolunteerRecord] = try await supabase
            .from("help_request_volunteers")
            .select()
            .eq("request_id", value: requestId.uuidString)
            .eq("volunteer_id", value: volunteerId.uuidString)
            .in("status", values: [
                HelpRequestStatus.confirmed.rawValue,
                HelpRequestStatus.inProgress.rawValue,
                HelpRequestStatus.completed.rawValue
            ])
            .order("updated_at", ascending: false)
            .execute()
            .value

        return assignments.first
    }
}

private struct RequestCancellationUpdate: Encodable {
    let status: String
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case status
        case updatedAt = "updated_at"
    }
}

private struct RequestStatusUpdate: Encodable {
    let status: String
    let updatedAt: Date
    let completedAt: Date?

    enum CodingKeys: String, CodingKey {
        case status
        case updatedAt = "updated_at"
        case completedAt = "completed_at"
    }
}

private struct VolunteerAssignmentCancellationUpdate: Encodable {
    let status: String
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case status
        case updatedAt = "updated_at"
    }
}

private struct VolunteerAssignmentStartUpdate: Encodable {
    let status: String
    let startedAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case status
        case startedAt = "started_at"
        case updatedAt = "updated_at"
    }
}

private struct VolunteerAssignmentCompletionUpdate: Encodable {
    let status: String
    let completedAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case status
        case completedAt = "completed_at"
        case updatedAt = "updated_at"
    }
}

private struct CompletedVolunteerProfileUpdate: Encodable {
    let role: String
    let availabilityStatus: String

    enum CodingKeys: String, CodingKey {
        case role
        case availabilityStatus = "availability_status"
    }
}
