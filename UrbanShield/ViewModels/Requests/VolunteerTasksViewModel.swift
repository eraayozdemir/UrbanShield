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

    func loadTasks(volunteerId: UUID?) async {
        errorMessage = nil

        guard let volunteerId else {
            errorMessage = "You must be signed in to view volunteer tasks."
            tasks = []
            return
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
        } catch where error.isCancellation {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
