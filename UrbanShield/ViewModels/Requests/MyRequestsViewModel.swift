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
    var cacheMessage: String?
    private let realtimeSubscription = RealtimeRefreshSubscription()

    func loadRequests(citizenId: UUID?) async {
        errorMessage = nil
        cacheMessage = nil

        guard let citizenId else {
            errorMessage = "You must be signed in to view your requests."
            requests = []
            return
        }

        let cacheKey = "my-requests.\(citizenId.uuidString)"
        if requests.isEmpty, let cached = OfflineCacheStore.load([HelpRequestRecord].self, forKey: cacheKey) {
            requests = cached.value
            cacheMessage = cachedMessage(savedAt: cached.savedAt)
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let loaded: [HelpRequestRecord] = try await supabase
                .from("help_requests")
                .select()
                .eq("citizen_id", value: citizenId.uuidString)
                .order("created_at", ascending: false)
                .execute()
                .value

            requests = loaded
            cacheMessage = nil
            OfflineCacheStore.save(loaded, forKey: cacheKey)
        } catch where error.isCancellation {
            return
        } catch {
            if let cached = OfflineCacheStore.load([HelpRequestRecord].self, forKey: cacheKey) {
                requests = cached.value
                cacheMessage = cachedMessage(savedAt: cached.savedAt)
            } else {
                errorMessage = error.localizedDescription
            }
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

    private func cachedMessage(savedAt: Date) -> String {
        "Offline mode: showing saved requests from \(savedAt.formatted(date: .abbreviated, time: .shortened))."
    }
}
