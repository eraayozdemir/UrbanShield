//
//  CreateRequestViewModel.swift
//  UrbanShield
//

import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class CreateRequestViewModel {

    // Doğrudan CreateRequestView kontrollerine bağlanan form alanları.
    var requestType: HelpRequestType = .earthquake
    var urgencyLevel: HelpRequestUrgency = .medium
    var description: String = ""
    var latitude: String = ""
    var longitude: String = ""

    // Progress indicator, error banner ve success routing için kullanılan UI state.
    var isLoading: Bool = false
    var errorMessage: String?
    var didSubmit: Bool = false

    // Citizen formunu doğrular ve help_requests içine yeni satır ekler.
    // Bu ana Phase 2 request creation akışıdır.
    func submit(currentUser: User?) async -> Bool {
        errorMessage = nil
        didSubmit = false

        guard let currentUser else {
            errorMessage = "You must be signed in to create a request."
            return false
        }

        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDescription.isEmpty else {
            errorMessage = "Description cannot be empty."
            return false
        }

        guard let latitudeValue = Double(latitude.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")),
              (-90...90).contains(latitudeValue) else {
            errorMessage = "Latitude must be a valid number between -90 and 90."
            return false
        }

        guard let longitudeValue = Double(longitude.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")),
              (-180...180).contains(longitudeValue) else {
            errorMessage = "Longitude must be a valid number between -180 and 180."
            return false
        }

        isLoading = true
        defer { isLoading = false }

        do {
            // Supabase kolonları snake_case olduğu için payload aşağıdaki CodingKeys
            // ile citizen_id, request_type, urgency_level vb. isimlere eşlenir.
            let payload = HelpRequestInsertPayload(
                citizenId: currentUser.id,
                requestType: requestType.rawValue,
                description: trimmedDescription,
                urgencyLevel: urgencyLevel.rawValue,
                status: HelpRequestStatus.open.rawValue,
                latitude: latitudeValue,
                longitude: longitudeValue
            )

            let inserted: HelpRequestRecord = try await supabase
                .from("help_requests")
                .insert(payload)
                .select()
                .single()
                .execute()
                .value

            try? await ActivityLogger.log(
                actor: currentUser,
                action: .requestCreated,
                targetType: .request,
                targetId: inserted.id,
                requestId: inserted.id,
                message: "\(inserted.requestTypeValue.title) request created with \(inserted.urgencyValue.title) urgency.",
                metadata: [
                    "request_type": inserted.requestType,
                    "urgency": inserted.urgencyLevel,
                    "status": inserted.status
                ]
            )

            if inserted.urgencyValue == .critical {
                // Critical requestler operasyonel kullanıcılara bildirim gönderir; böylece coordinatorlar
                // demo/acil durum akışında bunları hızlıca önceliklendirebilir.
                try? await InAppNotificationService.notifyCoordinatorsAndAdmins(
                    actorId: currentUser.id,
                    title: "Critical request created",
                    message: "\(inserted.requestTypeValue.title) request needs coordinator review.",
                    category: .request,
                    linkType: .request,
                    linkId: inserted.id,
                    requestId: inserted.id
                )
            }

            clearForm()
            didSubmit = true
            return true
        } catch where error.isCancellation {
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func clearForm() {
        requestType = .earthquake
        urgencyLevel = .medium
        description = ""
        latitude = ""
        longitude = ""
    }
}

// Supabase için insert DTO. Yalnızca bu ViewModel doğrudan
// help request satırı oluşturduğu için private tutulur.
private struct HelpRequestInsertPayload: Encodable {
    let citizenId: UUID
    let requestType: String
    let description: String
    let urgencyLevel: String
    let status: String
    let latitude: Double
    let longitude: Double

    enum CodingKeys: String, CodingKey {
        case citizenId = "citizen_id"
        case requestType = "request_type"
        case description
        case urgencyLevel = "urgency_level"
        case status
        case latitude
        case longitude
    }
}
