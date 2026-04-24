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

    func confirmRequest(_ request: HelpRequestRecord, volunteerId: UUID?) async -> Bool {
        errorMessage = nil
        successMessage = nil

        guard let volunteerId else {
            errorMessage = "You must be signed in to confirm a request."
            return false
        }

        guard request.citizenId != volunteerId else {
            errorMessage = "You cannot volunteer for your own request."
            return false
        }

        confirmingRequestId = request.id
        defer { confirmingRequestId = nil }

        do {
            let now = Date()
            let update = RequestVolunteerUpdate(
                volunteerId: volunteerId,
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
                .update(["role": UserRole.volunteer.rawValue])
                .eq("id", value: volunteerId.uuidString)
                .execute()

            requests.removeAll { $0.id == request.id }
            successMessage = "Request confirmed. It is now visible in your volunteer tasks."
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
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
