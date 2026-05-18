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
    private let realtimeSubscription = RealtimeRefreshSubscription()

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
        } catch where error.isCancellation {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startRealtime(citizenId: UUID?) async {
        guard let citizenId else { return }

        do {
            try await realtimeSubscription.start(
                channelName: "my-requests-\(citizenId.uuidString)",
                registrations: [
                    RealtimePostgresChangeRegistration(
                        table: "help_requests",
                        filter: "citizen_id=eq.\(citizenId.uuidString)"
                    )
                ]
            ) { [weak self] in
                await self?.loadRequests(citizenId: citizenId)
            }
        } catch {
            // Manual refresh remains available if realtime is temporarily unavailable.
        }
    }

    func stopRealtime() {
        Task {
            await realtimeSubscription.stop()
        }
    }
}
