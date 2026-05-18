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
    private let maxEvidenceBytes = 1_000_000
    private let realtimeSubscription = RealtimeRefreshSubscription()

    var request: HelpRequestRecord?
    var evidenceItems: [RequestEvidenceViewState] = []
    var isLoading: Bool = false
    var isCancelling: Bool = false
    var isUpdatingStatus: Bool = false
    var isSavingUpdate: Bool = false
    var isUploadingEvidence: Bool = false
    var errorMessage: String?
    var successMessage: String?

    var editDescription = ""
    var editUrgency: HelpRequestUrgency = .medium
    var editLatitude = ""
    var editLongitude = ""

    var canUploadMoreEvidence: Bool {
        evidenceItems.count < maxEvidenceCount
    }

    func loadRequest(id: UUID, currentUserId: UUID? = nil) async {
        errorMessage = nil
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

            await loadEvidence(requestId: id)
        } catch where error.isCancellation {
            return
        } catch {
            errorMessage = error.localizedDescription
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
            let filePath = "\(request.id.uuidString)/\(currentUser.id.uuidString)/\(UUID().uuidString)-\(fileName)"

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

            let inserted: RequestEvidenceRecord = try await supabase
                .from("request_evidence")
                .insert(
                    RequestEvidenceInsert(
                        requestId: request.id,
                        uploadedBy: currentUser.id,
                        filePath: filePath,
                        fileName: fileName,
                        contentType: "image/jpeg",
                        fileSize: jpegData.count
                    )
                )
                .select()
                .single()
                .execute()
                .value

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
            errorMessage = error.localizedDescription
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

        return finalOutput
    }
}

struct RequestEvidenceViewState: Identifiable, Equatable {
    let record: RequestEvidenceRecord
    let signedURL: URL?

    var id: UUID { record.id }
}

private enum EvidenceUploadError: LocalizedError {
    case invalidImage

    var errorDescription: String? {
        "Selected photo could not be prepared for upload."
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

private struct RequestEvidenceInsert: Encodable {
    let requestId: UUID
    let uploadedBy: UUID
    let filePath: String
    let fileName: String
    let contentType: String
    let fileSize: Int

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case uploadedBy = "uploaded_by"
        case filePath = "file_path"
        case fileName = "file_name"
        case contentType = "content_type"
        case fileSize = "file_size"
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
