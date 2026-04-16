//
//  UserRole.swift
//  UrbanShield
//

/// Represents the access level of a user in the system.
/// Stored as a String in Supabase (e.g. "citizen", "volunteer", etc.)
enum UserRole: String, Codable, CaseIterable, Sendable {
    case citizen
    case volunteer
    case coordinator
    case admin
}
