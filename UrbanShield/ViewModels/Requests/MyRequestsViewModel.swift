//
//  MyRequestsViewModel.swift
//  UrbanShield
//

import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class MyRequestsViewModel {

    var requests: [HelpRequestRecord] = []
    var isLoading: Bool = false
    var errorMessage: String?

    func loadRequests(citizenId: UUID?) async {
        errorMessage = nil

        guard let citizenId else {
            errorMessage = "You must be signed in to view your requests."
            requests = []
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            requests = try await supabase
                .from("help_requests")
                .select()
                .eq("citizen_id", value: citizenId.uuidString)
                .order("created_at", ascending: false)
                .execute()
                .value
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
