//
//  RequestDetailViewModel.swift
//  UrbanShield
//

import Foundation
import Observation
import Supabase
import UIKit

@MainActor
@Observable
final class RequestDetailViewModel {

    private let evidenceBucket = "request-evidence"
    private let maxEvidenceCount = 3
    private let maxEvidenceBytes = 5_000_000
    private let realtimeSubscription = RealtimeRefreshSubscription()

    var request: HelpRequestRecord?
    var evidenceItems: [RequestEvidenceViewState] = []
    var availableVolunteers: [ProfileUserRecord] = []
    var activeVolunteerCount: Int = 0
    var isLoading: Bool = false
    var isCancelling: Bool = false
    var isUpdatingStatus: Bool = false
    var isUpdatingCoordinatorControls: Bool = false
    var isSavingUpdate: Bool = false
    var isUploadingEvidence: Bool = false
    var errorMessage: String?
    var successMessage: String?
    var cacheMessage: String?

    var editDescription = ""
    var editUrgency: HelpRequestUrgency = .medium
    var editLatitude = ""
    var editLongitude = ""

    var canUploadMoreEvidence: Bool {
        evidenceItems.count < maxEvidenceCount
    }

    func loadRequest(id: UUID, currentUserId: UUID? = nil) async {
        errorMessage = nil
        cacheMessage = nil
        let cacheKey = requestDetailCacheKey(id: id, currentUserId: currentUserId)
        if request == nil, let cached = OfflineCacheStore.load(HelpRequestRecord.self, forKey: cacheKey) {
            request = cached.value
            cacheMessage = cachedMessage(savedAt: cached.savedAt)
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let loadedRequests: [HelpRequestRecord] = try await supabase
                .from("help_requests")
                .select()
                .eq("id", value: id.uuidString)
                .limit(1)
                .execute()
                .value

            guard let loadedRequest = loadedRequests.first else {
                request = nil
                return
            }

            if let currentUserId,
               loadedRequest.citizenId != currentUserId,
               let assignment = try await loadAssignment(requestId: id, volunteerId: currentUserId) {
                request = loadedRequest.applyingVolunteerAssignment(assignment)
            } else {
                request = loadedRequest
            }

            if let request {
                OfflineCacheStore.save(request, forKey: cacheKey)
                await loadCoordinatorAssignmentOptions(for: request)
            }
            cacheMessage = nil

            await loadEvidence(requestId: id)
        } catch where error.isCancellation {
            return
        } catch {
            if let cached = OfflineCacheStore.load(HelpRequestRecord.self, forKey: cacheKey) {
                request = cached.value
                cacheMessage = cachedMessage(savedAt: cached.savedAt)
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    func startRealtime(id: UUID, currentUserId: UUID?) async {
        do {
            try await realtimeSubscription.start(
                channelName: "request-detail-\(id.uuidString)",
                registrations: [
                    RealtimePostgresChangeRegistration(
                        table: "help_requests",
                        filter: "id=eq.\(id.uuidString)"
                    ),
                    RealtimePostgresChangeRegistration(
                        table: "help_request_volunteers",
                        filter: "request_id=eq.\(id.uuidString)"
                    ),
                    RealtimePostgresChangeRegistration(
                        table: "request_evidence",
                        filter: "request_id=eq.\(id.uuidString)"
                    )
                ]
            ) { [weak self] in
                await self?.loadRequest(id: id, currentUserId: currentUserId)
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

    func prepareEditForm() {
        guard let request else { return }

        editDescription = request.description
        editUrgency = request.urgencyValue
        editLatitude = coordinateEditText(request.latitude)
        editLongitude = coordinateEditText(request.longitude)
    }

    func updateRequest(id: UUID, currentUser: User?) async -> Bool {
        errorMessage = nil
        successMessage = nil

        guard let currentUser else {
            errorMessage = "You must be signed in to update a request."
            return false
        }

        guard canCurrentCitizenEdit(currentUser: currentUser) else {
            errorMessage = "Only your active requests can be updated."
            return false
        }

        let trimmedDescription = editDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDescription.isEmpty else {
            errorMessage = "Description cannot be empty."
            return false
        }

        guard let latitudeValue = Double(editLatitude.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")),
              (-90...90).contains(latitudeValue) else {
            errorMessage = "Latitude must be a valid number between -90 and 90."
            return false
        }

        guard let longitudeValue = Double(editLongitude.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")),
              (-180...180).contains(longitudeValue) else {
            errorMessage = "Longitude must be a valid number between -180 and 180."
            return false
        }

        isSavingUpdate = true
        defer { isSavingUpdate = false }

        do {
            let previousRequest = request
            let updatedRequest: HelpRequestRecord = try await supabase
                .from("help_requests")
                .update(
                    RequestCitizenUpdate(
                        description: trimmedDescription,
                        urgencyLevel: editUrgency.rawValue,
                        latitude: latitudeValue,
                        longitude: longitudeValue,
                        updatedAt: Date()
                    )
                )
                .eq("id", value: id.uuidString)
                .eq("citizen_id", value: currentUser.id.uuidString)
                .not("status", operator: .in, value: "(\(HelpRequestStatus.completed.rawValue),\(HelpRequestStatus.cancelled.rawValue))")
                .select()
                .single()
                .execute()
                .value

            request = updatedRequest

            try? await ActivityLogger.log(
                actor: currentUser,
                action: .requestUpdated,
                targetType: .request,
                targetId: id,
                requestId: id,
                message: "\(updatedRequest.requestTypeValue.title) request updated by citizen.",
                metadata: [
                    "old_urgency": previousRequest?.urgencyLevel ?? "",
                    "new_urgency": updatedRequest.urgencyLevel
                ]
            )

            successMessage = "Request updated."
            return true
        } catch where error.isCancellation {
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func uploadEvidence(imageData: Data, originalFileName: String, currentUser: User?) async {
        errorMessage = nil
        successMessage = nil

        guard let currentUser else {
            errorMessage = "You must be signed in to upload evidence."
            return
        }

        guard let request else {
            errorMessage = "Request must be loaded before uploading evidence."
            return
        }

        guard canCurrentUserUploadEvidence(currentUser: currentUser) else {
            errorMessage = "Evidence can only be uploaded by the request owner or assigned volunteer."
            return
        }

        guard evidenceItems.count < maxEvidenceCount else {
            errorMessage = "You can upload up to \(maxEvidenceCount) evidence photos per request."
            return
        }

        isUploadingEvidence = true
        defer { isUploadingEvidence = false }

        do {
            let jpegData = try compressedJPEGData(from: imageData)
            let fileName = sanitizedEvidenceFileName(originalFileName)
            let requestPathId = request.id.uuidString.lowercased()
            let uploaderPathId = currentUser.id.uuidString.lowercased()
            let evidencePathId = UUID().uuidString.lowercased()
            let filePath = "\(requestPathId)/\(uploaderPathId)/\(evidencePathId)-\(fileName)"

            try await supabase.storage
                .from(evidenceBucket)
                .upload(
                    filePath,
                    data: jpegData,
                    options: FileOptions(
                        cacheControl: "3600",
                        contentType: "image/jpeg",
                        upsert: false
                    )
                )

            let insertedRows: [RequestEvidenceRecord] = try await supabase
                .rpc(
                    "create_request_evidence_record",
                    params: RequestEvidenceCreateParams(
                        requestId: request.id,
                        filePath: filePath,
                        fileName: fileName,
                        contentType: "image/jpeg",
                        fileSize: jpegData.count
                    )
                )
                .execute()
                .value

            guard let inserted = insertedRows.first else {
                throw EvidenceUploadError.metadataNotCreated
            }

            let signedURL = try? await supabase.storage
                .from(evidenceBucket)
                .createSignedURL(path: inserted.filePath, expiresIn: 3600)

            evidenceItems.insert(RequestEvidenceViewState(record: inserted, signedURL: signedURL), at: 0)

            try? await ActivityLogger.log(
                actor: currentUser,
                action: .evidenceUploaded,
                targetType: .request,
                targetId: request.id,
                requestId: request.id,
                message: "Evidence photo uploaded for \(request.requestTypeValue.title) request.",
                metadata: [
                    "file_name": fileName,
                    "file_size": "\(jpegData.count)"
                ]
            )

            successMessage = "Evidence uploaded."
        } catch where error.isCancellation {
            return
        } catch {
            errorMessage = evidenceUploadMessage(for: error)
        }
    }

    func cancelRequest(id: UUID, currentUser: User?) async {
        errorMessage = nil

        guard let currentUser else {
            errorMessage = "You must be signed in to cancel a request."
            return
        }

        guard request?.statusValue.canBeCancelled == true else {
            errorMessage = "Only open, confirmed, or in-progress requests can be cancelled."
            return
        }

        isCancelling = true
        defer { isCancelling = false }

        do {
            let now = Date()
            let previousRequest = request
            let cancelledRequest: HelpRequestRecord = try await supabase
                .from("help_requests")
                .update(RequestCancellationUpdate(status: HelpRequestStatus.cancelled.rawValue, updatedAt: now))
                .eq("id", value: id.uuidString)
                .eq("citizen_id", value: currentUser.id.uuidString)
                .select()
                .single()
                .execute()
                .value
            request = cancelledRequest

            _ = try? await supabase
                .from("help_request_volunteers")
                .update(VolunteerAssignmentCancellationUpdate(status: HelpRequestStatus.cancelled.rawValue, updatedAt: now))
                .eq("request_id", value: id.uuidString)
                .in("status", values: [
                    HelpRequestStatus.confirmed.rawValue,
                    HelpRequestStatus.inProgress.rawValue
                ])
                .execute()

            try? await ActivityLogger.log(
                actor: currentUser,
                action: .requestCancelled,
                targetType: .request,
                targetId: id,
                requestId: id,
                message: "\(cancelledRequest.requestTypeValue.title) request cancelled by citizen.",
                metadata: [
                    "old_status": previousRequest?.status ?? "",
                    "new_status": HelpRequestStatus.cancelled.rawValue
                ]
            )
        } catch where error.isCancellation {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startVolunteerWork(id: UUID, currentUser: User?) async {
        await updateVolunteerStatus(
            id: id,
            currentUser: currentUser,
            from: .confirmed,
            to: .inProgress,
            errorText: "Only confirmed requests can be moved to in progress."
        )
    }

    func completeVolunteerWork(id: UUID, currentUser: User?) async {
        await updateVolunteerStatus(
            id: id,
            currentUser: currentUser,
            from: .inProgress,
            to: .completed,
            errorText: "Only in-progress requests can be completed."
        )
    }

    func allowedCoordinatorStatusTargets(for request: HelpRequestRecord) -> [HelpRequestStatus] {
        switch request.statusValue {
        case .open:
            return [.cancelled]
        case .confirmed:
            return [.inProgress, .cancelled]
        case .inProgress:
            return [.completed, .cancelled]
        case .completed, .cancelled:
            return []
        }
    }

    func eligibleVolunteers(for request: HelpRequestRecord) -> [ProfileUserRecord] {
        guard request.statusValue.acceptsVolunteers,
              activeVolunteerCount < request.volunteerCapacity else {
            return []
        }

        return availableVolunteers.filter { volunteer in
            volunteer.id != request.citizenId
                && volunteer.availabilityValue == .available
                && !volunteer.isSuspendedValue
                && !volunteer.skillsValue.isEmpty
                && volunteer.skillsValue.contains { $0.supports(request.requestTypeValue) }
        }
    }

    func updateCoordinatorStatus(status: HelpRequestStatus, currentUser: User?) async {
        errorMessage = nil
        successMessage = nil

        guard let currentUser, currentUser.role == .coordinator || currentUser.role == .admin else {
            errorMessage = "Only coordinators can update request status."
            return
        }

        guard let request else {
            errorMessage = "Request must be loaded before updating status."
            return
        }

        guard allowedCoordinatorStatusTargets(for: request).contains(status) else {
            errorMessage = "This status change is not available for the selected request."
            return
        }

        isUpdatingCoordinatorControls = true
        defer { isUpdatingCoordinatorControls = false }

        do {
            let now = Date()
            let updatedRequest: HelpRequestRecord = try await supabase
                .from("help_requests")
                .update(
                    RequestDetailCoordinatorStatusUpdate(
                        status: status.rawValue,
                        updatedAt: now,
                        completedAt: status == .completed ? now : nil
                    )
                )
                .eq("id", value: request.id.uuidString)
                .select()
                .single()
                .execute()
                .value

            try await syncAssignmentsAndVolunteer(for: request, nextStatus: status, updatedAt: now)

            self.request = updatedRequest

            try await insertCoordinationLog(
                requestId: request.id,
                coordinatorId: currentUser.id,
                actionType: .statusUpdated,
                oldValue: request.statusValue.rawValue,
                newValue: status.rawValue,
                message: "Status changed from \(request.statusValue.title) to \(status.title)."
            )

            try? await ActivityLogger.log(
                actor: currentUser,
                action: .requestStatusUpdated,
                targetType: .request,
                targetId: request.id,
                requestId: request.id,
                message: "Status changed from \(request.statusValue.title) to \(status.title).",
                metadata: [
                    "old_status": request.statusValue.rawValue,
                    "new_status": status.rawValue
                ]
            )

            let recipientIds = [
                request.citizenId,
                request.volunteerId
            ].compactMap { $0 }

            try? await InAppNotificationService.notifyUsers(
                userIds: recipientIds,
                actorId: currentUser.id,
                title: "Request status updated",
                message: "\(request.requestTypeValue.title) request moved to \(status.title).",
                category: .coordinator,
                linkType: .request,
                linkId: request.id,
                requestId: request.id
            )

            successMessage = "Status updated to \(status.title)."
        } catch where error.isCancellation {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func assignCoordinatorVolunteer(volunteer: ProfileUserRecord, currentUser: User?) async {
        errorMessage = nil
        successMessage = nil

        guard let currentUser, currentUser.role == .coordinator || currentUser.role == .admin else {
            errorMessage = "Only coordinators can assign volunteers."
            return
        }

        guard let request else {
            errorMessage = "Request must be loaded before assigning a volunteer."
            return
        }

        guard request.statusValue.acceptsVolunteers else {
            errorMessage = "This request is no longer accepting volunteers."
            return
        }

        guard activeVolunteerCount < request.volunteerCapacity else {
            errorMessage = "This request already has the maximum number of active volunteers for its urgency."
            return
        }

        guard volunteer.availabilityValue == .available,
              volunteer.skillsValue.contains(where: { $0.supports(request.requestTypeValue) }) else {
            errorMessage = "This volunteer is not available or does not match the request type."
            return
        }

        isUpdatingCoordinatorControls = true
        defer { isUpdatingCoordinatorControls = false }

        do {
            let activeAssignments: [HelpRequestVolunteerRecord] = try await supabase
                .from("help_request_volunteers")
                .select()
                .eq("volunteer_id", value: volunteer.id.uuidString)
                .in("status", values: [
                    HelpRequestStatus.confirmed.rawValue,
                    HelpRequestStatus.inProgress.rawValue
                ])
                .execute()
                .value

            guard activeAssignments.isEmpty else {
                errorMessage = "\(volunteer.fullName) already has an active task."
                return
            }

            let requestActiveAssignments: [HelpRequestVolunteerRecord] = try await supabase
                .from("help_request_volunteers")
                .select()
                .eq("request_id", value: request.id.uuidString)
                .in("status", values: [
                    HelpRequestStatus.confirmed.rawValue,
                    HelpRequestStatus.inProgress.rawValue
                ])
                .execute()
                .value

            guard requestActiveAssignments.count < request.volunteerCapacity else {
                errorMessage = "This request already has the maximum number of active volunteers for its urgency."
                return
            }

            let now = Date()

            try await supabase
                .from("help_request_volunteers")
                .insert(
                    RequestDetailVolunteerAssignmentInsert(
                        requestId: request.id,
                        volunteerId: volunteer.id,
                        status: HelpRequestStatus.confirmed.rawValue
                    )
                )
                .execute()

            let updatedRequest: HelpRequestRecord = try await supabase
                .from("help_requests")
                .update(
                    RequestDetailCoordinatorAssignmentUpdate(
                        volunteerId: volunteer.id,
                        status: HelpRequestStatus.confirmed.rawValue,
                        confirmedAt: now,
                        updatedAt: now
                    )
                )
                .eq("id", value: request.id.uuidString)
                .in("status", values: [
                    HelpRequestStatus.open.rawValue,
                    HelpRequestStatus.confirmed.rawValue
                ])
                .select()
                .single()
                .execute()
                .value

            try await supabase
                .from("profiles")
                .update(
                    RequestDetailAssignedVolunteerProfileUpdate(
                        role: UserRole.volunteer.rawValue,
                        availabilityStatus: VolunteerAvailability.busy.rawValue
                    )
                )
                .eq("id", value: volunteer.id.uuidString)
                .execute()

            self.request = updatedRequest
            activeVolunteerCount = requestActiveAssignments.count + 1
            availableVolunteers.removeAll { $0.id == volunteer.id }

            try await insertCoordinationLog(
                requestId: request.id,
                coordinatorId: currentUser.id,
                actionType: .volunteerAssigned,
                oldValue: request.statusValue.rawValue,
                newValue: HelpRequestStatus.confirmed.rawValue,
                message: "\(volunteer.fullName) assigned to \(request.requestTypeValue.title)."
            )

            try? await ActivityLogger.log(
                actor: currentUser,
                action: .volunteerAssigned,
                targetType: .request,
                targetId: request.id,
                requestId: request.id,
                targetUserId: volunteer.id,
                message: "\(volunteer.fullName) assigned to \(request.requestTypeValue.title).",
                metadata: [
                    "old_status": request.statusValue.rawValue,
                    "new_status": HelpRequestStatus.confirmed.rawValue,
                    "volunteer_name": volunteer.fullName
                ]
            )

            try? await InAppNotificationService.notifyUsers(
                userIds: [request.citizenId, volunteer.id],
                actorId: currentUser.id,
                title: "Volunteer assigned",
                message: "\(volunteer.fullName) was assigned to \(request.requestTypeValue.title).",
                category: .assignment,
                linkType: .request,
                linkId: request.id,
                requestId: request.id
            )

            successMessage = "\(volunteer.fullName) assigned to \(request.requestTypeValue.title)."
        } catch where error.isCancellation {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateVolunteerStatus(
        id: UUID,
        currentUser: User?,
        from currentStatus: HelpRequestStatus,
        to nextStatus: HelpRequestStatus,
        errorText: String
    ) async {
        errorMessage = nil

        guard let currentUser else {
            errorMessage = "You must be signed in to update this task."
            return
        }

        guard request?.statusValue == currentStatus else {
            errorMessage = errorText
            return
        }

        isUpdatingStatus = true
        defer { isUpdatingStatus = false }

        do {
            guard let assignment = try await loadAssignment(requestId: id, volunteerId: currentUser.id),
                  assignment.statusValue == currentStatus else {
                errorMessage = errorText
                return
            }

            let now = Date()

            if nextStatus == .inProgress {
                try await supabase
                    .from("help_request_volunteers")
                    .update(
                        VolunteerAssignmentStartUpdate(
                            status: nextStatus.rawValue,
                            startedAt: now,
                            updatedAt: now
                        )
                    )
                    .eq("id", value: assignment.id.uuidString)
                    .eq("status", value: currentStatus.rawValue)
                    .execute()

                _ = try? await supabase
                    .from("help_requests")
                    .update(
                        RequestStatusUpdate(
                            status: nextStatus.rawValue,
                            updatedAt: now,
                            completedAt: nil
                        )
                    )
                    .eq("id", value: id.uuidString)
                    .in("status", values: [
                        HelpRequestStatus.open.rawValue,
                        HelpRequestStatus.confirmed.rawValue,
                        HelpRequestStatus.inProgress.rawValue
                    ])
                    .execute()
            } else {
                try await supabase
                    .rpc(
                        "complete_my_volunteer_task",
                        params: CompleteVolunteerTaskParams(requestId: id)
                    )
                    .execute()
            }

            try? await ActivityLogger.log(
                actor: currentUser,
                action: nextStatus == .inProgress ? .requestStarted : .requestCompleted,
                targetType: .request,
                targetId: id,
                requestId: id,
                message: "\(request?.requestTypeValue.title ?? "Request") moved to \(nextStatus.title) by volunteer.",
                metadata: [
                    "old_status": currentStatus.rawValue,
                    "new_status": nextStatus.rawValue
                ]
            )

            if let citizenId = request?.citizenId, citizenId != currentUser.id {
                try? await InAppNotificationService.notifyUser(
                    userId: citizenId,
                    actorId: currentUser.id,
                    title: nextStatus == .inProgress ? "Help is in progress" : "Request completed",
                    message: "\(request?.requestTypeValue.title ?? "Your request") moved to \(nextStatus.title).",
                    category: .assignment,
                    linkType: .request,
                    linkId: id,
                    requestId: id
                )
            }

            await loadRequest(id: id, currentUserId: currentUser.id)
        } catch where error.isCancellation {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func syncAssignmentsAndVolunteer(
        for request: HelpRequestRecord,
        nextStatus: HelpRequestStatus,
        updatedAt: Date
    ) async throws {
        guard nextStatus == .inProgress || nextStatus == .completed || nextStatus == .cancelled else {
            return
        }

        let activeAssignments: [HelpRequestVolunteerRecord] = try await supabase
            .from("help_request_volunteers")
            .select()
            .eq("request_id", value: request.id.uuidString)
            .in("status", values: [
                HelpRequestStatus.confirmed.rawValue,
                HelpRequestStatus.inProgress.rawValue
            ])
            .execute()
            .value

        for assignment in activeAssignments {
            switch nextStatus {
            case .inProgress:
                try await supabase
                    .from("help_request_volunteers")
                    .update(
                        RequestDetailAssignmentStartUpdate(
                            status: nextStatus.rawValue,
                            startedAt: updatedAt,
                            updatedAt: updatedAt
                        )
                    )
                    .eq("id", value: assignment.id.uuidString)
                    .execute()
            case .completed:
                try await supabase
                    .from("help_request_volunteers")
                    .update(
                        RequestDetailAssignmentCompletionUpdate(
                            status: nextStatus.rawValue,
                            completedAt: updatedAt,
                            updatedAt: updatedAt
                        )
                    )
                    .eq("id", value: assignment.id.uuidString)
                    .execute()
                try await markVolunteerAvailableIfNeeded(assignment.volunteerId)
            case .cancelled:
                try await supabase
                    .from("help_request_volunteers")
                    .update(
                        RequestDetailAssignmentCancellationUpdate(
                            status: nextStatus.rawValue,
                            updatedAt: updatedAt
                        )
                    )
                    .eq("id", value: assignment.id.uuidString)
                    .execute()
                try await markVolunteerAvailableIfNeeded(assignment.volunteerId)
            default:
                break
            }
        }
    }

    private func markVolunteerAvailableIfNeeded(_ volunteerId: UUID) async throws {
        try await supabase
            .from("profiles")
            .update(RequestDetailVolunteerAvailabilityUpdate(availabilityStatus: VolunteerAvailability.available.rawValue))
            .eq("id", value: volunteerId.uuidString)
            .execute()
    }

    private func insertCoordinationLog(
        requestId: UUID,
        coordinatorId: UUID,
        actionType: CoordinationActionType,
        oldValue: String?,
        newValue: String?,
        message: String
    ) async throws {
        try await supabase
            .from("coordination_logs")
            .insert(
                RequestDetailCoordinationLogInsert(
                    requestId: requestId,
                    coordinatorId: coordinatorId,
                    actionType: actionType.rawValue,
                    oldValue: oldValue,
                    newValue: newValue,
                    message: message
                )
            )
            .execute()
    }

    private func loadAssignment(requestId: UUID, volunteerId: UUID) async throws -> HelpRequestVolunteerRecord? {
        let assignments: [HelpRequestVolunteerRecord] = try await supabase
            .from("help_request_volunteers")
            .select()
            .eq("request_id", value: requestId.uuidString)
            .eq("volunteer_id", value: volunteerId.uuidString)
            .in("status", values: [
                HelpRequestStatus.confirmed.rawValue,
                HelpRequestStatus.inProgress.rawValue,
                HelpRequestStatus.completed.rawValue
            ])
            .order("updated_at", ascending: false)
            .execute()
            .value

        return assignments.first
    }

    private func loadCoordinatorAssignmentOptions(for request: HelpRequestRecord) async {
        do {
            let activeAssignments: [HelpRequestVolunteerRecord] = try await supabase
                .from("help_request_volunteers")
                .select()
                .eq("request_id", value: request.id.uuidString)
                .in("status", values: [
                    HelpRequestStatus.confirmed.rawValue,
                    HelpRequestStatus.inProgress.rawValue
                ])
                .execute()
                .value

            activeVolunteerCount = activeAssignments.count
            let activeVolunteerIds = Set(activeAssignments.map(\.volunteerId))

            guard request.statusValue.acceptsVolunteers,
                  activeAssignments.count < request.volunteerCapacity else {
                availableVolunteers = []
                return
            }

            let profiles: [ProfileUserRecord] = try await supabase
                .from("profiles")
                .select()
                .eq("availability_status", value: VolunteerAvailability.available.rawValue)
                .order("full_name", ascending: true)
                .execute()
                .value

            availableVolunteers = profiles.filter { profile in
                profile.id != request.citizenId
                    && !activeVolunteerIds.contains(profile.id)
                    && !profile.isSuspendedValue
                    && profile.skillsValue.contains { $0.supports(request.requestTypeValue) }
            }
        } catch where error.isCancellation {
            return
        } catch {
            activeVolunteerCount = 0
            availableVolunteers = []
        }
    }

    private func loadEvidence(requestId: UUID) async {
        do {
            let records: [RequestEvidenceRecord] = try await supabase
                .from("request_evidence")
                .select()
                .eq("request_id", value: requestId.uuidString)
                .order("created_at", ascending: false)
                .execute()
                .value

            var states: [RequestEvidenceViewState] = []
            for record in records {
                let signedURL = try? await supabase.storage
                    .from(evidenceBucket)
                    .createSignedURL(path: record.filePath, expiresIn: 3600)
                states.append(RequestEvidenceViewState(record: record, signedURL: signedURL))
            }

            evidenceItems = states
        } catch where error.isCancellation {
            return
        } catch {
            evidenceItems = []
            errorMessage = error.localizedDescription
        }
    }

    private func requestDetailCacheKey(id: UUID, currentUserId: UUID?) -> String {
        "request-detail.\(id.uuidString).\(currentUserId?.uuidString ?? "anonymous")"
    }

    private func cachedMessage(savedAt: Date) -> String {
        "Offline mode: showing saved request detail from \(savedAt.formatted(date: .abbreviated, time: .shortened))."
    }

    private func canCurrentCitizenEdit(currentUser: User) -> Bool {
        guard let request else { return false }

        return request.citizenId == currentUser.id
            && request.statusValue != .completed
            && request.statusValue != .cancelled
    }

    private func canCurrentUserUploadEvidence(currentUser: User) -> Bool {
        guard let request else { return false }

        let isRequestOwner = request.citizenId == currentUser.id
        let isAssignedVolunteer = request.volunteerId == currentUser.id

        return (isRequestOwner || isAssignedVolunteer)
            && request.statusValue != .completed
            && request.statusValue != .cancelled
    }

    private func coordinateEditText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(4...6)))
    }

    private func sanitizedEvidenceFileName(_ fileName: String) -> String {
        let baseName = fileName
            .split(separator: ".")
            .first
            .map(String.init) ?? "evidence"
        let safeBaseName = baseName
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }

        return "\(safeBaseName.isEmpty ? "evidence" : safeBaseName).jpg"
    }

    private func compressedJPEGData(from data: Data) throws -> Data {
        guard let image = UIImage(data: data) else {
            throw EvidenceUploadError.invalidImage
        }

        var quality: CGFloat = 0.78
        var output = image.jpegData(compressionQuality: quality)

        while let currentOutput = output,
              currentOutput.count > maxEvidenceBytes,
              quality > 0.24 {
            quality -= 0.12
            output = image.jpegData(compressionQuality: quality)
        }

        guard let finalOutput = output else {
            throw EvidenceUploadError.invalidImage
        }

        guard finalOutput.count <= maxEvidenceBytes else {
            throw EvidenceUploadError.fileTooLarge(maxMegabytes: maxEvidenceBytes / 1_000_000)
        }

        return finalOutput
    }

    private func evidenceUploadMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }

        let message = error.localizedDescription
        let lowercasedMessage = message.lowercased()

        if lowercasedMessage.contains("row-level security")
            || lowercasedMessage.contains("rls")
            || lowercasedMessage.contains("permission") {
            return "You do not have permission to upload evidence for this request. If this is your request or assigned task, run the latest evidence SQL in Supabase."
        }

        if lowercasedMessage.contains("bucket")
            || lowercasedMessage.contains("storage") {
            return "Evidence storage is not ready. Confirm the request-evidence bucket exists in Supabase Storage."
        }

        if lowercasedMessage.contains("payload")
            || lowercasedMessage.contains("file size")
            || lowercasedMessage.contains("too large") {
            return "Selected photo is too large. Choose a smaller photo or compress it before uploading."
        }

        if lowercasedMessage.contains("network")
            || lowercasedMessage.contains("offline")
            || lowercasedMessage.contains("timed out") {
            return "Evidence upload needs an internet connection. Please try again when the connection is stable."
        }

        return "Evidence upload failed: \(message)"
    }
}

struct RequestEvidenceViewState: Identifiable, Equatable {
    let record: RequestEvidenceRecord
    let signedURL: URL?

    var id: UUID { record.id }
}

private enum EvidenceUploadError: LocalizedError {
    case invalidImage
    case fileTooLarge(maxMegabytes: Int)
    case metadataNotCreated

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Selected photo could not be prepared for upload."
        case .fileTooLarge(let maxMegabytes):
            return "Selected photo is still larger than \(maxMegabytes) MB after compression. Please choose a smaller photo."
        case .metadataNotCreated:
            return "Evidence photo uploaded, but its request record could not be created. Please refresh and try again."
        }
    }
}

private struct RequestCitizenUpdate: Encodable {
    let description: String
    let urgencyLevel: String
    let latitude: Double
    let longitude: Double
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case description
        case urgencyLevel = "urgency_level"
        case latitude
        case longitude
        case updatedAt = "updated_at"
    }
}

private struct RequestEvidenceCreateParams: Encodable {
    let requestId: UUID
    let filePath: String
    let fileName: String
    let contentType: String
    let fileSize: Int

    enum CodingKeys: String, CodingKey {
        case requestId = "p_request_id"
        case filePath = "p_file_path"
        case fileName = "p_file_name"
        case contentType = "p_content_type"
        case fileSize = "p_file_size"
    }
}

private struct RequestCancellationUpdate: Encodable {
    let status: String
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case status
        case updatedAt = "updated_at"
    }
}

private struct RequestStatusUpdate: Encodable {
    let status: String
    let updatedAt: Date
    let completedAt: Date?

    enum CodingKeys: String, CodingKey {
        case status
        case updatedAt = "updated_at"
        case completedAt = "completed_at"
    }
}

private struct RequestDetailCoordinatorStatusUpdate: Encodable {
    let status: String
    let updatedAt: Date
    let completedAt: Date?

    enum CodingKeys: String, CodingKey {
        case status
        case updatedAt = "updated_at"
        case completedAt = "completed_at"
    }
}

private struct RequestDetailCoordinationLogInsert: Encodable {
    let requestId: UUID
    let coordinatorId: UUID
    let actionType: String
    let oldValue: String?
    let newValue: String?
    let message: String

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case coordinatorId = "coordinator_id"
        case actionType = "action_type"
        case oldValue = "old_value"
        case newValue = "new_value"
        case message
    }
}

private struct RequestDetailVolunteerAssignmentInsert: Encodable {
    let requestId: UUID
    let volunteerId: UUID
    let status: String

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case volunteerId = "volunteer_id"
        case status
    }
}

private struct RequestDetailCoordinatorAssignmentUpdate: Encodable {
    let volunteerId: UUID
    let status: String
    let confirmedAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case volunteerId = "volunteer_id"
        case status
        case confirmedAt = "confirmed_at"
        case updatedAt = "updated_at"
    }
}

private struct RequestDetailAssignedVolunteerProfileUpdate: Encodable {
    let role: String
    let availabilityStatus: String

    enum CodingKeys: String, CodingKey {
        case role
        case availabilityStatus = "availability_status"
    }
}

private struct RequestDetailAssignmentStartUpdate: Encodable {
    let status: String
    let startedAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case status
        case startedAt = "started_at"
        case updatedAt = "updated_at"
    }
}

private struct RequestDetailAssignmentCompletionUpdate: Encodable {
    let status: String
    let completedAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case status
        case completedAt = "completed_at"
        case updatedAt = "updated_at"
    }
}

private struct RequestDetailAssignmentCancellationUpdate: Encodable {
    let status: String
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case status
        case updatedAt = "updated_at"
    }
}

private struct RequestDetailVolunteerAvailabilityUpdate: Encodable {
    let availabilityStatus: String

    enum CodingKeys: String, CodingKey {
        case availabilityStatus = "availability_status"
    }
}

private struct VolunteerAssignmentCancellationUpdate: Encodable {
    let status: String
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case status
        case updatedAt = "updated_at"
    }
}

private struct VolunteerAssignmentStartUpdate: Encodable {
    let status: String
    let startedAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case status
        case startedAt = "started_at"
        case updatedAt = "updated_at"
    }
}

private struct CompleteVolunteerTaskParams: Encodable {
    let requestId: UUID

    enum CodingKeys: String, CodingKey {
        case requestId = "p_request_id"
    }
}
