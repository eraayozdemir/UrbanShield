//
//  NearbyRequestsViewModel.swift
//  UrbanShield
//

import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class NearbyRequestsViewModel {

    // Nearby içinde mevcut kullanıcıya görünen requestler. Liste
    // kullanıcının kendi requestlerini, dolu requestleri ve kullanıcının zaten kabul ettiği requestleri
    // hariç tutar.
    var requests: [HelpRequestRecord] = []
    var activeVolunteerCounts: [UUID: Int] = [:]
    var isLoading: Bool = false
    var confirmingRequestId: UUID?
    var errorMessage: String?
    var successMessage: String?
    var cacheMessage: String?
    private let realtimeSubscription = RealtimeRefreshSubscription()
    private var pollingTask: Task<Void, Never>?

    // Active requestleri yükler ve volunteer-capacity kurallarını client tarafında uygular.
    // Database/RPC aynı kuralları yine uygular; bu nedenle bu yalnızca UI filtering işlemidir,
    // güvenlik sınırı değildir.
    func loadOpenRequests(currentUserId: UUID?) async {
        errorMessage = nil
        cacheMessage = nil

        guard let currentUserId else {
            errorMessage = "You must be signed in to view nearby requests."
            requests = []
            return
        }

        let cacheKey = "nearby-requests.\(currentUserId.uuidString)"
        if requests.isEmpty, let cached = OfflineCacheStore.load([HelpRequestRecord].self, forKey: cacheKey) {
            requests = cached.value
            cacheMessage = cachedMessage(savedAt: cached.savedAt)
        }

        isLoading = true
        defer { isLoading = false }

        do {
            // Önce mevcut kullanıcının zaten active task sahibi olup olmadığını kontrol eder.
            // Accepted requestler Nearby listesinden kaldırılır çünkü Tasks ekranına aittir.
            let acceptedAssignments: [HelpRequestVolunteerRecord] = try await supabase
                .from("help_request_volunteers")
                .select()
                .eq("volunteer_id", value: currentUserId.uuidString)
                .in("status", values: [
                    HelpRequestStatus.confirmed.rawValue,
                    HelpRequestStatus.inProgress.rawValue
                ])
                .execute()
                .value

            let acceptedRequestIds = Set(acceptedAssignments.map(\.requestId))

            let openRequests: [HelpRequestRecord] = try await supabase
                .from("help_requests")
                .select()
                .in("status", values: [
                    HelpRequestStatus.open.rawValue,
                    HelpRequestStatus.confirmed.rawValue,
                    HelpRequestStatus.inProgress.rawValue
                ])
                .neq("citizen_id", value: currentUserId.uuidString)
                .order("created_at", ascending: false)
                .execute()
                .value

            activeVolunteerCounts = try await loadActiveVolunteerCounts(for: openRequests)

            // UI seviyesi capacity kontrolü: critical requestler kapasitesi dolana kadar
            // görünür kalabilir; lower urgency requestler normalde
            // bir active volunteer sonrası kaybolur.
            requests = openRequests.filter { request in
                let activeVolunteerCount = activeVolunteerCounts[request.id] ?? 0
                return request.statusValue.acceptsVolunteers
                    && !acceptedRequestIds.contains(request.id)
                    && activeVolunteerCount < request.volunteerCapacity
            }
            cacheMessage = nil
            OfflineCacheStore.save(requests, forKey: cacheKey)
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

    func confirmRequest(_ request: HelpRequestRecord, volunteer: User?) async -> Bool {
        errorMessage = nil
        successMessage = nil
        cacheMessage = nil

        guard let volunteer else {
            errorMessage = "You must be signed in to confirm a request."
            return false
        }

        guard request.citizenId != volunteer.id else {
            errorMessage = "You cannot volunteer for your own request."
            return false
        }

        guard volunteer.availabilityStatus == .available else {
            errorMessage = "You must be available before accepting a request."
            return false
        }

        guard request.statusValue.acceptsVolunteers else {
            errorMessage = "This request is no longer accepting volunteers."
            return false
        }

        guard !volunteer.volunteerSkills.isEmpty else {
            errorMessage = "Add at least one volunteer skill in your profile before accepting requests."
            return false
        }

        guard volunteer.volunteerSkills.contains(where: { $0.supports(request.requestTypeValue) }) else {
            errorMessage = "Your volunteer skills do not match this request type."
            return false
        }

        confirmingRequestId = request.id
        defer { confirmingRequestId = nil }

        do {
            // Güncel backend state, eski UI verisiyle request kabul edilmesini engeller.
            // İki cihaz aynı requesti test ederken bu önemlidir.
            let acceptanceState = try await loadVolunteerAcceptanceState()

            guard acceptanceState.availabilityValue == .available else {
                errorMessage = "You must be available before accepting a request."
                return false
            }

            guard acceptanceState.activeAssignmentCount == 0 else {
                errorMessage = "Complete your active volunteer task before accepting another request."
                return false
            }

            try await supabase
                .rpc(
                    "accept_help_request_as_volunteer",
                    params: AcceptHelpRequestParams(requestId: request.id)
                )
                .execute()

            try? await ActivityLogger.log(
                actor: volunteer,
                action: .requestConfirmed,
                targetType: .request,
                targetId: request.id,
                requestId: request.id,
                targetUserId: request.citizenId,
                message: "\(volunteer.fullName) confirmed \(request.requestTypeValue.title) request.",
                metadata: [
                    "old_status": request.status,
                    "new_status": HelpRequestStatus.confirmed.rawValue,
                    "request_type": request.requestType
                ]
            )

            try? await InAppNotificationService.notifyUser(
                userId: request.citizenId,
                actorId: volunteer.id,
                title: "Request accepted",
                message: "\(volunteer.fullName) accepted your \(request.requestTypeValue.title) request.",
                category: .assignment,
                linkType: .request,
                linkId: request.id,
                requestId: request.id
            )

            await loadOpenRequests(currentUserId: volunteer.id)
            successMessage = "Request confirmed. Your volunteer status is now busy."
            return true
        } catch where error.isCancellation {
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func startRealtime(currentUserId: UUID?) async {
        guard let currentUserId else { return }

        do {
            try await realtimeSubscription.start(
                channelName: "nearby-requests-\(currentUserId.uuidString)",
                registrations: [
                    RealtimePostgresChangeRegistration(
                        table: "help_requests"
                    ),
                    RealtimePostgresChangeRegistration(
                        table: "help_request_volunteers",
                        filter: "volunteer_id=eq.\(currentUserId.uuidString)"
                    )
                ]
            ) { [weak self] in
                await self?.loadOpenRequests(currentUserId: currentUserId)
            }
        } catch {
            // Realtime geçici olarak çalışmazsa manuel yenileme kullanılmaya devam eder.
        }
    }

    func startPollingFallback(currentUserId: UUID?) {
        guard let currentUserId, pollingTask == nil else { return }

        // Polling demo/free-plan güvenilirliği için düşük maliyetli yedek yöntemdir.
        // Realtime değişiklikleri iletmezse ekranı her 10 saniyede bir yeniler.
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 10_000_000_000)
                } catch {
                    return
                }

                guard !Task.isCancelled else { return }
                await self?.loadOpenRequests(currentUserId: currentUserId)
            }
        }
    }

    func stopRealtime() {
        pollingTask?.cancel()
        pollingTask = nil

        Task {
            await realtimeSubscription.stop()
        }
    }

    private func cachedMessage(savedAt: Date) -> String {
        "Offline mode: showing saved nearby requests from \(savedAt.formatted(date: .abbreviated, time: .shortened))."
    }

    private func loadActiveVolunteerCounts(for requests: [HelpRequestRecord]) async throws -> [UUID: Int] {
        let requestIds = requests.map(\.id)
        guard !requestIds.isEmpty else { return [:] }

        let countRows: [RequestActiveVolunteerCountRecord] = try await supabase
            .rpc(
                "get_help_request_active_volunteer_counts",
                params: RequestActiveVolunteerCountsParams(requestIds: requestIds)
            )
            .execute()
            .value

        return Dictionary(
            uniqueKeysWithValues: countRows.map { ($0.requestId, $0.activeVolunteerCount) }
        )
    }

    private func loadVolunteerAcceptanceState() async throws -> VolunteerAcceptanceStateRecord {
        let stateRows: [VolunteerAcceptanceStateRecord] = try await supabase
            .rpc("get_my_volunteer_acceptance_state")
            .execute()
            .value

        guard let state = stateRows.first else {
            throw NearbyRequestsError.profileNotFound
        }

        return state
    }

    func activeVolunteerCount(for request: HelpRequestRecord) -> Int {
        activeVolunteerCounts[request.id] ?? 0
    }
}

private enum NearbyRequestsError: LocalizedError {
    case profileNotFound

    var errorDescription: String? {
        switch self {
        case .profileNotFound:
            return "Profile could not be found."
        }
    }
}

private struct AcceptHelpRequestParams: Encodable {
    let requestId: UUID

    enum CodingKeys: String, CodingKey {
        case requestId = "p_request_id"
    }
}

private struct RequestActiveVolunteerCountsParams: Encodable {
    let requestIds: [UUID]

    enum CodingKeys: String, CodingKey {
        case requestIds = "p_request_ids"
    }
}

private struct RequestActiveVolunteerCountRecord: Decodable {
    let requestId: UUID
    let activeVolunteerCount: Int

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case activeVolunteerCount = "active_volunteer_count"
    }
}

private struct VolunteerAcceptanceStateRecord: Decodable {
    let availabilityStatus: String
    let activeAssignmentCount: Int

    enum CodingKeys: String, CodingKey {
        case availabilityStatus = "availability_status"
        case activeAssignmentCount = "active_assignment_count"
    }

    var availabilityValue: VolunteerAvailability {
        VolunteerAvailability(rawValue: availabilityStatus) ?? .available
    }
}
