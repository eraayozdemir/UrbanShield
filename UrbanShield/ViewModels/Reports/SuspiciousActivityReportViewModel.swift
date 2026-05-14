//
//  SuspiciousActivityReportViewModel.swift
//  UrbanShield
//

import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class SuspiciousActivityReportViewModel {

    var visibleRequests: [HelpRequestRecord] = []
    var myReports: [SuspiciousActivityReportRecord] = []
    var selectedRequestId: UUID?
    var category: SuspiciousReportCategory = .fakeRequest
    var details = ""
    var isLoading = false
    var isSubmitting = false
    var errorMessage: String?
    var successMessage: String?

    var selectedRequest: HelpRequestRecord? {
        guard let selectedRequestId else { return nil }
        return visibleRequests.first { $0.id == selectedRequestId }
    }

    func load(currentUser: User?) async {
        errorMessage = nil
        successMessage = nil

        guard let currentUser, currentUser.role != .admin else {
            errorMessage = "Only citizen, volunteer, and coordinator users can submit suspicious activity reports."
            visibleRequests = []
            myReports = []
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            visibleRequests = try await supabase
                .from("help_requests")
                .select()
                .order("updated_at", ascending: false)
                .limit(30)
                .execute()
                .value

            myReports = try await supabase
                .from("suspicious_activity_reports")
                .select()
                .eq("reporter_id", value: currentUser.id.uuidString)
                .order("created_at", ascending: false)
                .limit(10)
                .execute()
                .value
        } catch where error.isCancellation {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func submit(currentUser: User?) async {
        errorMessage = nil
        successMessage = nil

        guard let currentUser, currentUser.role != .admin else {
            errorMessage = "Only citizen, volunteer, and coordinator users can submit suspicious activity reports."
            return
        }

        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDetails.isEmpty else {
            errorMessage = "Report details are required."
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let inserted: SuspiciousActivityReportRecord = try await supabase
                .from("suspicious_activity_reports")
                .insert(
                    SharedSuspiciousActivityReportInsert(
                        reporterId: currentUser.id,
                        requestId: selectedRequestId,
                        category: category.rawValue,
                        details: trimmedDetails,
                        status: SuspiciousReportStatus.open.rawValue
                    )
                )
                .select()
                .single()
                .execute()
                .value

            myReports.insert(inserted, at: 0)
            try? await ActivityLogger.log(
                actor: currentUser,
                action: .suspiciousReportSubmitted,
                targetType: .report,
                targetId: inserted.id,
                requestId: inserted.requestId,
                reportId: inserted.id,
                message: "\(inserted.categoryValue.title) report submitted for admin review.",
                metadata: [
                    "category": inserted.category,
                    "status": inserted.status
                ]
            )
            selectedRequestId = nil
            category = .fakeRequest
            details = ""
            successMessage = "Suspicious activity report sent to admin review."
        } catch where error.isCancellation {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func requestTitle(for id: UUID?) -> String {
        guard let id else { return "No linked request" }
        guard let request = visibleRequests.first(where: { $0.id == id }) else {
            return "Request \(id.uuidString.prefix(8))"
        }
        return "\(request.requestTypeValue.title) • \(request.statusValue.title) • #\(request.id.uuidString.prefix(8))"
    }
}

private struct SharedSuspiciousActivityReportInsert: Encodable {
    let reporterId: UUID
    let requestId: UUID?
    let category: String
    let details: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case reporterId = "reporter_id"
        case requestId = "request_id"
        case category
        case details
        case status
    }
}
