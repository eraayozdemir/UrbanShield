//
//  VolunteerCoordinationViewModel.swift
//  UrbanShield
//

import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class VolunteerCoordinationViewModel {

    var members: [VolunteerCoordinationMember] = []
    var isLoading = false
    var errorMessage: String?

    var totalCount: Int { members.count }
    var availableCount: Int { members.filter { $0.displayAvailability == .available }.count }
    var busyCount: Int { members.filter { $0.displayAvailability == .busy }.count }
    var offlineCount: Int { members.filter { $0.displayAvailability == .offline }.count }
    var skilledAvailableCount: Int {
        members.filter { $0.displayAvailability == .available && !$0.profile.skillsValue.isEmpty }.count
    }

    func loadVolunteers(currentUser: User?) async {
        errorMessage = nil

        guard currentUser?.role == .coordinator || currentUser?.role == .admin else {
            errorMessage = "Only coordinators can view volunteer coordination."
            members = []
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let profiles: [ProfileUserRecord] = try await supabase
                .from("profiles")
                .select()
                .in("role", values: [
                    UserRole.citizen.rawValue,
                    UserRole.volunteer.rawValue
                ])
                .order("full_name", ascending: true)
                .execute()
                .value

            let assignments: [HelpRequestVolunteerRecord] = try await supabase
                .from("help_request_volunteers")
                .select()
                .in("status", values: [
                    HelpRequestStatus.confirmed.rawValue,
                    HelpRequestStatus.inProgress.rawValue
                ])
                .order("updated_at", ascending: false)
                .execute()
                .value

            let requestIds = Array(Set(assignments.map { $0.requestId.uuidString }))
            let requests: [HelpRequestRecord]
            if requestIds.isEmpty {
                requests = []
            } else {
                requests = try await supabase
                    .from("help_requests")
                    .select()
                    .in("id", values: requestIds)
                    .execute()
                    .value
            }

            let requestById = Dictionary(uniqueKeysWithValues: requests.map { ($0.id, $0) })
            let assignmentByVolunteer = Dictionary(grouping: assignments, by: \.volunteerId)
                .compactMapValues { grouped in
                    grouped.sorted { $0.updatedAt > $1.updatedAt }.first
                }

            members = profiles
                .map { profile in
                    let assignment = assignmentByVolunteer[profile.id]
                    return VolunteerCoordinationMember(
                        profile: profile,
                        assignment: assignment,
                        activeRequest: assignment.flatMap { requestById[$0.requestId] }
                    )
                }
                .sorted(by: sortMembers)
        } catch where error.isCancellation {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sortMembers(_ lhs: VolunteerCoordinationMember, _ rhs: VolunteerCoordinationMember) -> Bool {
        if lhs.sortRank != rhs.sortRank {
            return lhs.sortRank < rhs.sortRank
        }

        if lhs.profile.skillsValue.count != rhs.profile.skillsValue.count {
            return lhs.profile.skillsValue.count > rhs.profile.skillsValue.count
        }

        return lhs.profile.fullName.localizedCaseInsensitiveCompare(rhs.profile.fullName) == .orderedAscending
    }
}

struct VolunteerCoordinationMember: Identifiable, Equatable {
    let profile: ProfileUserRecord
    let assignment: HelpRequestVolunteerRecord?
    let activeRequest: HelpRequestRecord?

    var id: UUID { profile.id }

    var displayAvailability: VolunteerAvailability {
        assignment == nil ? profile.availabilityValue : .busy
    }

    var isAssigned: Bool {
        assignment != nil
    }

    var sortRank: Int {
        if isAssigned { return 0 }

        switch displayAvailability {
        case .available: return 1
        case .busy: return 2
        case .offline: return 3
        }
    }
}
