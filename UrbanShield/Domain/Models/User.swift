//
//  User.swift
//  UrbanShield
//

import Foundation

/// The domain model representing an authenticated user with a profile.
/// This is what the app works with — no Supabase types leak into the domain.
struct User: Equatable, Sendable {
    let id: UUID
    let email: String
    let fullName: String
    let role: UserRole
    let createdAt: Date
}
