//
//  EmergencyAnnouncementsViewModel.swift
//  UrbanShield
//

import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class EmergencyAnnouncementsViewModel {

    var announcements: [EmergencyAnnouncementRecord] = []
    var isLoading = false
    var errorMessage: String?

    var criticalCount: Int {
        announcements.filter { $0.severityValue == .critical }.count
    }

    var latestAnnouncement: EmergencyAnnouncementRecord? {
        announcements.first
    }

    func load(currentUser: User?) async {
        errorMessage = nil

        guard let currentUser else {
            errorMessage = "You must be signed in to view announcements."
            announcements = []
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let loaded: [EmergencyAnnouncementRecord] = try await supabase
                .from("emergency_announcements")
                .select()
                .eq("is_active", value: true)
                .order("created_at", ascending: false)
                .limit(50)
                .execute()
                .value

            announcements = loaded.filter { announcement in
                shouldShow(announcement, to: currentUser.role)
            }
        } catch where error.isCancellation {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func shouldShow(_ announcement: EmergencyAnnouncementRecord, to role: UserRole) -> Bool {
        switch announcement.audienceValue {
        case .all:
            return true
        case .citizens:
            return role == .citizen
        case .volunteers:
            return role == .volunteer
        }
    }
}
