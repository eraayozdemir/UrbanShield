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

    var requestType: HelpRequestType = .earthquake
    var urgencyLevel: HelpRequestUrgency = .medium
    var description: String = ""
    var latitude: String = ""
    var longitude: String = ""

    var isLoading: Bool = false
    var errorMessage: String?
    var didSubmit: Bool = false

    func submit(citizenId: UUID?) async -> Bool {
        errorMessage = nil
        didSubmit = false

        guard let citizenId else {
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
            let payload = HelpRequestInsertPayload(
                citizenId: citizenId,
                requestType: requestType.rawValue,
                description: trimmedDescription,
                urgencyLevel: urgencyLevel.rawValue,
                status: HelpRequestStatus.open.rawValue,
                latitude: latitudeValue,
                longitude: longitudeValue
            )

            let _: HelpRequestRecord = try await supabase
                .from("help_requests")
                .insert(payload)
                .select()
                .single()
                .execute()
                .value

            clearForm()
            didSubmit = true
            return true
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
