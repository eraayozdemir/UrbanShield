//
//  UserRole.swift
//  UrbanShield
//

/// Kullanıcının sistemdeki erişim seviyesini temsil eder.
/// Supabase tarafında String olarak saklanır (örn. "citizen", "volunteer" vb.).
enum UserRole: String, Codable, CaseIterable, Sendable {
    case citizen
    case volunteer
    case coordinator
    case admin
}
