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

    func loadRequest(id: UUID) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            request = try await supabase
                .from("help_requests")
                .select()
                .eq("id", value: id.uuidString)
                .single()
                .execute()
                .value
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
            request = try await supabase
                .from("help_requests")
                .update(["status": HelpRequestStatus.cancelled.rawValue])
                .eq("id", value: id.uuidString)
                .eq("citizen_id", value: citizenId.uuidString)
                .select()
                .single()
                .execute()
                .value
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
            let now = Date()
            let update = RequestStatusUpdate(
                status: nextStatus.rawValue,
                updatedAt: now,
                completedAt: nextStatus == .completed ? now : nil
            )

            request = try await supabase
                .from("help_requests")
                .update(update)
                .eq("id", value: id.uuidString)
                .eq("volunteer_id", value: volunteerId.uuidString)
                .eq("status", value: currentStatus.rawValue)
                .select()
                .single()
                .execute()
                .value
        } catch {
            errorMessage = error.localizedDescription
        }
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
