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
            tasks = try await supabase
                .from("help_requests")
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
