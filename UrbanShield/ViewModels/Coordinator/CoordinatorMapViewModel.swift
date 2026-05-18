//
//  CoordinatorMapViewModel.swift
//  UrbanShield
//

import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class CoordinatorMapViewModel {

    var requests: [HelpRequestRecord] = []
    var statusFilter: HelpRequestStatus?
    var urgencyFilter: HelpRequestUrgency?
    var typeFilter: HelpRequestType?
    var priorityFilter: HelpRequestPriority?
    var searchText = ""
    var latitudeText = ""
    var longitudeText = ""
    var radiusText = ""
    var isLoading = false
    var errorMessage: String?
    private let realtimeSubscription = RealtimeRefreshSubscription()

    func loadRequests(currentUser: User?) async {
        errorMessage = nil

        guard currentUser?.role == .coordinator || currentUser?.role == .admin else {
            errorMessage = "Only coordinators can view the operational map."
            requests = []
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            requests = try await supabase
                .from("help_requests")
                .select()
                .order("updated_at", ascending: false)
                .execute()
                .value
        } catch where error.isCancellation {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startRealtime(currentUser: User?) async {
        guard currentUser?.role == .coordinator || currentUser?.role == .admin else { return }

        do {
            try await realtimeSubscription.start(
                channelName: "coordinator-map-\(currentUser?.id.uuidString ?? "unknown")",
                registrations: [
                    RealtimePostgresChangeRegistration(table: "help_requests")
                ]
            ) { [weak self, currentUser] in
                await self?.loadRequests(currentUser: currentUser)
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

    var filteredRequests: [HelpRequestRecord] {
        let normalizedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let centerLatitude = Double(latitudeText.replacingOccurrences(of: ",", with: "."))
        let centerLongitude = Double(longitudeText.replacingOccurrences(of: ",", with: "."))
        let radius = Double(radiusText.replacingOccurrences(of: ",", with: "."))

        return requests.filter { request in
            if let statusFilter, request.statusValue != statusFilter {
                return false
            }

            if let urgencyFilter, request.urgencyValue != urgencyFilter {
                return false
            }

            if let typeFilter, request.requestTypeValue != typeFilter {
                return false
            }

            if let priorityFilter, request.priorityValue != priorityFilter {
                return false
            }

            if !normalizedSearch.isEmpty {
                let haystack = [
                    request.requestTypeValue.title,
                    request.statusValue.title,
                    request.urgencyValue.title,
                    request.priorityValue.title,
                    request.description
                ]
                .joined(separator: " ")
                .lowercased()

                guard haystack.contains(normalizedSearch) else {
                    return false
                }
            }

            if let centerLatitude,
               let centerLongitude,
               let radius,
               radius > 0,
               request.operationalDistanceInKilometers(fromLatitude: centerLatitude, longitude: centerLongitude) > radius {
                return false
            }

            return true
        }
        .sorted(by: sortForMap)
    }

    func clearFilters() {
        statusFilter = nil
        urgencyFilter = nil
        typeFilter = nil
        priorityFilter = nil
        searchText = ""
        radiusText = ""
    }

    private func sortForMap(_ lhs: HelpRequestRecord, _ rhs: HelpRequestRecord) -> Bool {
        if lhs.statusValue.isActive != rhs.statusValue.isActive {
            return lhs.statusValue.isActive
        }

        if lhs.priorityValue.sortRank != rhs.priorityValue.sortRank {
            return lhs.priorityValue.sortRank > rhs.priorityValue.sortRank
        }

        return lhs.updatedAt > rhs.updatedAt
    }
}

extension HelpRequestRecord {
    func operationalDistanceInKilometers(fromLatitude latitude: Double, longitude: Double) -> Double {
        let earthRadius = 6_371.0
        let lat1 = self.latitude * .pi / 180
        let lat2 = latitude * .pi / 180
        let deltaLat = (latitude - self.latitude) * .pi / 180
        let deltaLon = (longitude - self.longitude) * .pi / 180

        let a = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2)
            * sin(deltaLon / 2) * sin(deltaLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))

        return earthRadius * c
    }
}
