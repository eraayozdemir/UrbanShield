//
//  AdminModerationViewModel.swift
//  UrbanShield
//

import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class AdminModerationViewModel {

    var rows: [AdminModerationRow] = []
    var actions: [ModerationActionRecord] = []
    var moderationNote = ""
    var isLoading = false
    var updatingReportId: UUID?
    var cancellingRequestId: UUID?
    var errorMessage: String?
    var successMessage: String?

    var openCount: Int {
        rows.filter { $0.report.statusValue == .open }.count
    }

    var reviewingCount: Int {
        rows.filter { $0.report.statusValue == .reviewing }.count
    }

    var resolvedCount: Int {
        rows.filter { $0.report.statusValue == .resolved }.count
    }

    func load(currentUser: User?) async {
        errorMessage = nil
        successMessage = nil

        guard currentUser?.role == .admin else {
            errorMessage = "Only admins can use moderation."
            rows = []
            actions = []
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let reports: [SuspiciousActivityReportRecord] = try await supabase
                .from("suspicious_activity_reports")
                .select()
                .order("created_at", ascending: false)
                .execute()
                .value

            let profiles: [ProfileUserRecord] = try await supabase
                .from("profiles")
                .select()
                .execute()
                .value

            let requestIds = Array(Set(reports.compactMap { $0.requestId?.uuidString }))
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

            actions = try await supabase
                .from("moderation_actions")
                .select()
                .order("created_at", ascending: false)
                .limit(20)
                .execute()
                .value

            let profileById = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
            let requestById = Dictionary(uniqueKeysWithValues: requests.map { ($0.id, $0) })

            rows = reports.map { report in
                AdminModerationRow(
                    report: report,
                    reporter: profileById[report.reporterId],
                    request: report.requestId.flatMap { requestById[$0] }
                )
            }
        } catch where error.isCancellation {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateReportStatus(
        row: AdminModerationRow,
        status: SuspiciousReportStatus,
        currentUser: User?
    ) async {
        errorMessage = nil
        successMessage = nil

        guard let currentUser, currentUser.role == .admin else {
            errorMessage = "Only admins can update report status."
            return
        }

        updatingReportId = row.report.id
        defer { updatingReportId = nil }

        do {
            let updated: SuspiciousActivityReportRecord = try await supabase
                .from("suspicious_activity_reports")
                .update(
                    AdminSuspiciousReportStatusUpdate(
                        status: status.rawValue,
                        reviewedBy: currentUser.id,
                        updatedAt: Date()
                    )
                )
                .eq("id", value: row.report.id.uuidString)
                .select()
                .single()
                .execute()
                .value

            replaceRow(report: updated)

            let actionType: ModerationActionType
            switch status {
            case .resolved:
                actionType = .reportResolved
            case .dismissed:
                actionType = .reportDismissed
            case .open, .reviewing:
                actionType = .statusUpdated
            }

            try await insertAction(
                adminId: currentUser.id,
                reportId: row.report.id,
                requestId: row.report.requestId,
                targetUserId: row.report.reporterId,
                actionType: actionType,
                notes: noteOrDefault("Report status changed to \(status.title).")
            )

            try? await ActivityLogger.log(
                actor: currentUser,
                action: .suspiciousReportReviewed,
                targetType: .report,
                targetId: row.report.id,
                requestId: row.report.requestId,
                reportId: row.report.id,
                targetUserId: row.report.reporterId,
                message: "Suspicious activity report changed to \(status.title).",
                metadata: [
                    "old_status": row.report.status,
                    "new_status": status.rawValue
                ]
            )

            moderationNote = ""
            actions = try await loadRecentActions()
            successMessage = "Report status updated."
        } catch where error.isCancellation {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancelLinkedRequest(row: AdminModerationRow, currentUser: User?) async {
        errorMessage = nil
        successMessage = nil

        guard let currentUser, currentUser.role == .admin else {
            errorMessage = "Only admins can moderate requests."
            return
        }

        guard let request = row.request else {
            errorMessage = "This report is not linked to a request."
            return
        }

        guard request.statusValue.canBeCancelled else {
            errorMessage = "This request cannot be cancelled in its current status."
            return
        }

        cancellingRequestId = request.id
        defer { cancellingRequestId = nil }

        do {
            let now = Date()
            let updatedRequest: HelpRequestRecord = try await supabase
                .from("help_requests")
                .update(AdminRequestCancellationUpdate(status: HelpRequestStatus.cancelled.rawValue, updatedAt: now))
                .eq("id", value: request.id.uuidString)
                .select()
                .single()
                .execute()
                .value

            let updatedReport: SuspiciousActivityReportRecord = try await supabase
                .from("suspicious_activity_reports")
                .update(
                    AdminSuspiciousReportStatusUpdate(
                        status: SuspiciousReportStatus.resolved.rawValue,
                        reviewedBy: currentUser.id,
                        updatedAt: now
                    )
                )
                .eq("id", value: row.report.id.uuidString)
                .select()
                .single()
                .execute()
                .value

            replaceRow(report: updatedReport, request: updatedRequest)

            try await insertAction(
                adminId: currentUser.id,
                reportId: row.report.id,
                requestId: request.id,
                targetUserId: request.citizenId,
                actionType: .requestCancelled,
                notes: noteOrDefault("Linked request cancelled from moderation.")
            )

            try? await ActivityLogger.log(
                actor: currentUser,
                action: .requestCancelled,
                targetType: .request,
                targetId: request.id,
                requestId: request.id,
                reportId: row.report.id,
                targetUserId: request.citizenId,
                message: "Linked \(request.requestTypeValue.title) request cancelled from moderation.",
                metadata: [
                    "old_request_status": request.status,
                    "new_request_status": HelpRequestStatus.cancelled.rawValue,
                    "report_status": SuspiciousReportStatus.resolved.rawValue
                ]
            )

            moderationNote = ""
            actions = try await loadRecentActions()
            successMessage = "Linked request cancelled and report resolved."
        } catch where error.isCancellation {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func replaceRow(
        report: SuspiciousActivityReportRecord,
        request: HelpRequestRecord? = nil
    ) {
        guard let index = rows.firstIndex(where: { $0.report.id == report.id }) else { return }
        rows[index] = AdminModerationRow(
            report: report,
            reporter: rows[index].reporter,
            request: request ?? rows[index].request
        )
    }

    private func loadRecentActions() async throws -> [ModerationActionRecord] {
        try await supabase
            .from("moderation_actions")
            .select()
            .order("created_at", ascending: false)
            .limit(20)
            .execute()
            .value
    }

    private func insertAction(
        adminId: UUID,
        reportId: UUID?,
        requestId: UUID?,
        targetUserId: UUID?,
        actionType: ModerationActionType,
        notes: String?
    ) async throws {
        try await supabase
            .from("moderation_actions")
            .insert(
                ModerationActionInsert(
                    adminId: adminId,
                    reportId: reportId,
                    requestId: requestId,
                    targetUserId: targetUserId,
                    actionType: actionType.rawValue,
                    notes: notes
                )
            )
            .execute()
    }

    private func noteOrDefault(_ fallback: String) -> String {
        let trimmed = moderationNote.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

struct AdminModerationRow: Identifiable, Equatable {
    let report: SuspiciousActivityReportRecord
    let reporter: ProfileUserRecord?
    let request: HelpRequestRecord?

    var id: UUID { report.id }
}

private struct AdminSuspiciousReportStatusUpdate: Encodable {
    let status: String
    let reviewedBy: UUID
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case status
        case reviewedBy = "reviewed_by"
        case updatedAt = "updated_at"
    }
}

private struct AdminRequestCancellationUpdate: Encodable {
    let status: String
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case status
        case updatedAt = "updated_at"
    }
}

private struct ModerationActionInsert: Encodable {
    let adminId: UUID
    let reportId: UUID?
    let requestId: UUID?
    let targetUserId: UUID?
    let actionType: String
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case adminId = "admin_id"
        case reportId = "report_id"
        case requestId = "request_id"
        case targetUserId = "target_user_id"
        case actionType = "action_type"
        case notes
    }
}
