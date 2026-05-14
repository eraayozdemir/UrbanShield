//
//  NearbyRequestsViewModel.swift
//  UrbanShield
//

import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class NearbyRequestsViewModel {

    var requests: [HelpRequestRecord] = []
    var isLoading: Bool = false
    var confirmingRequestId: UUID?
    var errorMessage: String?
    var successMessage: String?

    func loadOpenRequests(currentUserId: UUID?) async {
        errorMessage = nil

        guard let currentUserId else {
            errorMessage = "You must be signed in to view nearby requests."
            requests = []
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let acceptedAssignments: [HelpRequestVolunteerRecord] = try await supabase
                .from("help_request_volunteers")
                .select()
                .eq("volunteer_id", value: currentUserId.uuidString)
                .in("status", values: [
                    HelpRequestStatus.confirmed.rawValue,
                    HelpRequestStatus.inProgress.rawValue
                ])
                .execute()
                .value

            let acceptedRequestIds = Set(acceptedAssignments.map(\.requestId))

            let openRequests: [HelpRequestRecord] = try await supabase
                .from("help_requests")
                .select()
                .in("status", values: [
                    HelpRequestStatus.open.rawValue,
                    HelpRequestStatus.confirmed.rawValue
                ])
                .neq("citizen_id", value: currentUserId.uuidString)
                .order("created_at", ascending: false)
                .execute()
                .value

            requests = openRequests.filter { request in
                request.statusValue.acceptsVolunteers && !acceptedRequestIds.contains(request.id)
            }
        } catch where error.isCancellation {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func confirmRequest(_ request: HelpRequestRecord, volunteer: User?) async -> Bool {
        errorMessage = nil
        successMessage = nil

        guard let volunteer else {
            errorMessage = "You must be signed in to confirm a request."
            return false
        }

        guard request.citizenId != volunteer.id else {
            errorMessage = "You cannot volunteer for your own request."
            return false
        }

        guard volunteer.availabilityStatus == .available else {
            errorMessage = "You must be available before accepting a request."
            return false
        }

        guard request.statusValue.acceptsVolunteers else {
            errorMessage = "This request is no longer accepting volunteers."
            return false
        }

        guard !volunteer.volunteerSkills.isEmpty else {
            errorMessage = "Add at least one volunteer skill in your profile before accepting requests."
            return false
        }

        guard volunteer.volunteerSkills.contains(where: { $0.supports(request.requestTypeValue) }) else {
            errorMessage = "Your volunteer skills do not match this request type."
            return false
        }

        confirmingRequestId = request.id
        defer { confirmingRequestId = nil }

        do {
            let now = Date()
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
                errorMessage = "Complete your active volunteer task before accepting another request."
                return false
            }

            try await supabase
                .from("help_request_volunteers")
                .insert(
                    VolunteerAssignmentInsert(
                        requestId: request.id,
                        volunteerId: volunteer.id,
                        status: HelpRequestStatus.confirmed.rawValue
                    )
                )
                .execute()

            try? await supabase
                .from("help_requests")
                .update(
                    RequestConfirmationUpdate(
                        status: HelpRequestStatus.confirmed.rawValue,
                        confirmedAt: now,
                        updatedAt: now
                    )
                )
                .eq("id", value: request.id.uuidString)
                .eq("status", value: HelpRequestStatus.open.rawValue)
                .execute()

            try? await supabase
                .from("profiles")
                .update(
                    VolunteerAcceptanceProfileUpdate(
                        role: UserRole.volunteer.rawValue,
                        availabilityStatus: VolunteerAvailability.busy.rawValue
                    )
                )
                .eq("id", value: volunteer.id.uuidString)
                .execute()

            try? await ActivityLogger.log(
                actor: volunteer,
                action: .requestConfirmed,
                targetType: .request,
                targetId: request.id,
                requestId: request.id,
                targetUserId: request.citizenId,
                message: "\(volunteer.fullName) confirmed \(request.requestTypeValue.title) request.",
                metadata: [
                    "old_status": request.status,
                    "new_status": HelpRequestStatus.confirmed.rawValue,
                    "request_type": request.requestType
                ]
            )

            requests.removeAll { $0.id == request.id }
            successMessage = "Request confirmed. Your volunteer status is now busy."
            return true
        } catch where error.isCancellation {
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

private struct VolunteerAssignmentInsert: Encodable {
    let requestId: UUID
    let volunteerId: UUID
    let status: String

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case volunteerId = "volunteer_id"
        case status
    }
}

private struct VolunteerAcceptanceProfileUpdate: Encodable {
    let role: String
    let availabilityStatus: String

    enum CodingKeys: String, CodingKey {
        case role
        case availabilityStatus = "availability_status"
    }
}

private struct RequestConfirmationUpdate: Encodable {
    let status: String
    let confirmedAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case status
        case confirmedAt = "confirmed_at"
        case updatedAt = "updated_at"
    }
}
