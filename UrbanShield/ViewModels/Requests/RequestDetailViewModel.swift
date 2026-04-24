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
            errorMessage = "Only open or in-progress requests can be cancelled."
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
}
