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
            requests = try await supabase
                .from("help_requests")
                .select()
                .eq("status", value: HelpRequestStatus.open.rawValue)
                .neq("citizen_id", value: currentUserId.uuidString)
                .order("created_at", ascending: false)
                .execute()
                .value
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
            let update = RequestVolunteerUpdate(
                volunteerId: volunteer.id,
                status: HelpRequestStatus.confirmed.rawValue,
                confirmedAt: now,
                updatedAt: now
            )

            _ = try await supabase
                .from("help_requests")
                .update(update)
                .eq("id", value: request.id.uuidString)
                .eq("status", value: HelpRequestStatus.open.rawValue)
                .select()
                .single()
                .execute()

            try await supabase
                .from("profiles")
                .update(
                    VolunteerAcceptanceProfileUpdate(
                        role: UserRole.volunteer.rawValue,
                        availabilityStatus: VolunteerAvailability.busy.rawValue
                    )
                )
                .eq("id", value: volunteer.id.uuidString)
                .execute()

            requests.removeAll { $0.id == request.id }
            successMessage = "Request confirmed. Your volunteer status is now busy."
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
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

private struct RequestVolunteerUpdate: Encodable {
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
