//
//  VolunteerTasksViewModel.swift
//  UrbanShield
//

import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class VolunteerTasksViewModel {

    var tasks: [HelpRequestRecord] = []
    var isLoading: Bool = false
    var errorMessage: String?
    var cacheMessage: String?
    private let realtimeSubscription = RealtimeRefreshSubscription()

    func loadTasks(volunteerId: UUID?) async {
        errorMessage = nil
        cacheMessage = nil

        guard let volunteerId else {
            errorMessage = "You must be signed in to view volunteer tasks."
            tasks = []
            return
        }

        let cacheKey = "volunteer-tasks.\(volunteerId.uuidString)"
        if tasks.isEmpty, let cached = OfflineCacheStore.load([HelpRequestRecord].self, forKey: cacheKey) {
            tasks = cached.value
            cacheMessage = cachedMessage(savedAt: cached.savedAt)
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let assignments: [HelpRequestVolunteerRecord] = try await supabase
                .from("help_request_volunteers")
                .select()
                .eq("volunteer_id", value: volunteerId.uuidString)
                .in("status", values: [
                    HelpRequestStatus.confirmed.rawValue,
                    HelpRequestStatus.inProgress.rawValue,
                    HelpRequestStatus.completed.rawValue
                ])
                .order("updated_at", ascending: false)
                .execute()
                .value

            let requestIds = assignments.map { $0.requestId.uuidString }
            guard !requestIds.isEmpty else {
                tasks = []
                return
            }

            let requests: [HelpRequestRecord] = try await supabase
                .from("help_requests")
                .select()
                .in("id", values: requestIds)
                .execute()
                .value

            let requestsById = Dictionary(uniqueKeysWithValues: requests.map { ($0.id, $0) })
            tasks = assignments.compactMap { assignment in
                requestsById[assignment.requestId]?.applyingVolunteerAssignment(assignment)
            }
            cacheMessage = nil
            OfflineCacheStore.save(tasks, forKey: cacheKey)
        } catch where error.isCancellation {
            return
        } catch {
            if let cached = OfflineCacheStore.load([HelpRequestRecord].self, forKey: cacheKey) {
                tasks = cached.value
                cacheMessage = cachedMessage(savedAt: cached.savedAt)
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    func startRealtime(volunteerId: UUID?) async {
        guard let volunteerId else { return }

        do {
            try await realtimeSubscription.start(
                channelName: "volunteer-tasks-\(volunteerId.uuidString)",
                registrations: [
                    RealtimePostgresChangeRegistration(
                        table: "help_request_volunteers",
                        filter: "volunteer_id=eq.\(volunteerId.uuidString)"
                    )
                ]
            ) { [weak self] in
                await self?.loadTasks(volunteerId: volunteerId)
            }
        } catch {
            // Realtime geçici olarak çalışmazsa manuel yenileme kullanılmaya devam eder.
        }
    }

    func stopRealtime() {
        Task {
            await realtimeSubscription.stop()
        }
    }

    private func cachedMessage(savedAt: Date) -> String {
        "Offline mode: showing saved volunteer tasks from \(savedAt.formatted(date: .abbreviated, time: .shortened))."
    }
}
