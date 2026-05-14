//
//  ProfileUserRecord.swift
//  UrbanShield
//

import Foundation

struct ProfileUserRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let email: String
    let fullName: String
    let role: String
    let availabilityStatus: String?
    let volunteerSkills: [String]?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, email, role
        case fullName = "full_name"
        case availabilityStatus = "availability_status"
        case volunteerSkills = "volunteer_skills"
        case createdAt = "created_at"
    }

    var roleValue: UserRole {
        UserRole(rawValue: role) ?? .citizen
    }

    var availabilityValue: VolunteerAvailability {
        VolunteerAvailability(rawValue: availabilityStatus ?? "") ?? .available
    }

    var skillsValue: [VolunteerSkill] {
        (volunteerSkills ?? []).compactMap(VolunteerSkill.init(rawValue:))
    }

    var skillSummary: String {
        let skills = skillsValue
        return skills.isEmpty ? "No skills" : skills.map(\.title).joined(separator: ", ")
    }
}
