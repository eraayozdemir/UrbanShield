//
//  CoordinatorOperationsViewModel.swift
//  UrbanShield
//

import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class CoordinatorOperationsViewModel {

    var activeRequests: [HelpRequestRecord] = []
    var supplyActions: [SupplySupportActionRecord] = []
    var announcements: [EmergencyAnnouncementRecord] = []
    var suspiciousReports: [SuspiciousActivityReportRecord] = []

    var selectedSupplyRequestId: UUID?
    var supplyType: SupplySupportType = .medical
    var supplyStatus: SupplyActionStatus = .planned
    var supplyQuantity = ""
    var supplyNotes = ""

    var announcementTitle = ""
    var announcementMessage = ""
    var announcementSeverity: EmergencyAnnouncementSeverity = .warning
    var announcementAudience: EmergencyAnnouncementAudience = .all

    var isLoading = false
    var isSavingSupply = false
    var isPublishingAnnouncement = false
    var errorMessage: String?
    var successMessage: String?

    func load(currentUser: User?) async {
        errorMessage = nil
        successMessage = nil

        guard let currentUser, currentUser.role == .coordinator || currentUser.role == .admin else {
            errorMessage = "Only coordinators can use coordination tools."
            clearLoadedData()
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            activeRequests = try await supabase
                .from("help_requests")
                .select()
                .in("status", values: [
                    HelpRequestStatus.open.rawValue,
                    HelpRequestStatus.confirmed.rawValue,
                    HelpRequestStatus.inProgress.rawValue
                ])
                .order("updated_at", ascending: false)
                .execute()
                .value

            supplyActions = try await supabase
                .from("supply_support_actions")
                .select()
                .order("created_at", ascending: false)
                .limit(20)
                .execute()
                .value

            announcements = try await supabase
                .from("emergency_announcements")
                .select()
                .order("created_at", ascending: false)
                .limit(20)
                .execute()
                .value

            suspiciousReports = try await supabase
                .from("suspicious_activity_reports")
                .select()
                .eq("reporter_id", value: currentUser.id.uuidString)
                .order("created_at", ascending: false)
                .limit(20)
                .execute()
                .value

            if selectedSupplyRequestId == nil {
                selectedSupplyRequestId = activeRequests.first?.id
            }
        } catch where error.isCancellation {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createSupplyAction(currentUser: User?) async {
        errorMessage = nil
        successMessage = nil

        guard let currentUser, currentUser.role == .coordinator || currentUser.role == .admin else {
            errorMessage = "Only coordinators can log supply support."
            return
        }

        guard let selectedSupplyRequestId else {
            errorMessage = "Select an active request before logging support."
            return
        }

        isSavingSupply = true
        defer { isSavingSupply = false }

        do {
            let inserted: SupplySupportActionRecord = try await supabase
                .from("supply_support_actions")
                .insert(
                    SupplySupportActionInsert(
                        requestId: selectedSupplyRequestId,
                        coordinatorId: currentUser.id,
                        supportType: supplyType.rawValue,
                        status: supplyStatus.rawValue,
                        quantity: trimmedOptional(supplyQuantity),
                        notes: trimmedOptional(supplyNotes)
                    )
                )
                .select()
                .single()
                .execute()
                .value

            supplyActions.insert(inserted, at: 0)
            supplyQuantity = ""
            supplyNotes = ""
            try? await ActivityLogger.log(
                actor: currentUser,
                action: .supplySupportLogged,
                targetType: .supplyAction,
                targetId: inserted.id,
                requestId: inserted.requestId,
                message: "\(inserted.supportTypeValue.title) support logged as \(inserted.statusValue.title).",
                metadata: [
                    "support_type": inserted.supportType,
                    "status": inserted.status
                ]
            )
            successMessage = "Supply support logged."
        } catch where error.isCancellation {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func publishAnnouncement(currentUser: User?) async {
        errorMessage = nil
        successMessage = nil

        guard let currentUser, currentUser.role == .coordinator || currentUser.role == .admin else {
            errorMessage = "Only coordinators can publish announcements."
            return
        }

        let title = announcementTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = announcementMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !message.isEmpty else {
            errorMessage = "Announcement title and message are required."
            return
        }

        isPublishingAnnouncement = true
        defer { isPublishingAnnouncement = false }

        do {
            let inserted: EmergencyAnnouncementRecord = try await supabase
                .from("emergency_announcements")
                .insert(
                    EmergencyAnnouncementInsert(
                        coordinatorId: currentUser.id,
                        title: title,
                        message: message,
                        severity: announcementSeverity.rawValue,
                        audience: announcementAudience.rawValue
                    )
                )
                .select()
                .single()
                .execute()
                .value

            announcements.insert(inserted, at: 0)
            announcementTitle = ""
            announcementMessage = ""
            try? await ActivityLogger.log(
                actor: currentUser,
                action: .announcementPublished,
                targetType: .announcement,
                targetId: inserted.id,
                message: "Emergency announcement published: \(inserted.title).",
                metadata: [
                    "severity": inserted.severity,
                    "audience": inserted.audience
                ]
            )
            successMessage = "Announcement published."
        } catch where error.isCancellation {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func requestTitle(for id: UUID?) -> String {
        guard let id else { return "Optional request" }
        guard let request = activeRequests.first(where: { $0.id == id }) else {
            return "Request \(id.uuidString.prefix(8))"
        }
        return "\(request.requestTypeValue.title) • \(request.statusValue.title)"
    }

    private func clearLoadedData() {
        activeRequests = []
        supplyActions = []
        announcements = []
        suspiciousReports = []
    }

    private func trimmedOptional(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct SupplySupportActionInsert: Encodable {
    let requestId: UUID
    let coordinatorId: UUID
    let supportType: String
    let status: String
    let quantity: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case coordinatorId = "coordinator_id"
        case supportType = "support_type"
        case status
        case quantity
        case notes
    }
}

private struct EmergencyAnnouncementInsert: Encodable {
    let coordinatorId: UUID
    let title: String
    let message: String
    let severity: String
    let audience: String

    enum CodingKeys: String, CodingKey {
        case coordinatorId = "coordinator_id"
        case title
        case message
        case severity
        case audience
    }
}
