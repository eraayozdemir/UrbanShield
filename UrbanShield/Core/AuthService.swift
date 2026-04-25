//
//  AuthService.swift
//  UrbanShield
//
//  Single point of contact for all auth and profile operations.
//  Replaces: AuthRepository, UserRepository, all UseCases,
//            AuthRemoteDataSource, UserRemoteDataSource, UserDTO, UserMapper.
//

import Supabase
import Foundation

final class AuthService: Sendable {

    static let shared = AuthService()
    private init() {}

    // MARK: - Auth

    func signUp(email: String, password: String, fullName: String) async throws -> User {
        let response = try await supabase.auth.signUp(email: email, password: password)
        return try await createProfile(userId: response.user.id, email: email, fullName: fullName)
    }

    func signIn(email: String, password: String) async throws -> User {
        _ = try await supabase.auth.signIn(email: email, password: password)
        guard let user = try await currentUser() else { throw AppError.profileNotFound }
        return user
    }

    func signOut() async throws {
        try await supabase.auth.signOut()
    }

    func sendPasswordReset(email: String) async throws {
        try await supabase.auth.resetPasswordForEmail(email)
    }

    @discardableResult
    func updateProfile(fullName: String) async throws -> User {
        let session = try await supabase.auth.session
        let dto: ProfileDTO = try await supabase
            .from("profiles")
            .update(ProfileUpdateDTO(fullName: fullName))
            .eq("id", value: session.user.id.uuidString)
            .select()
            .single()
            .execute()
            .value

        _ = try await supabase.auth.update(
            user: UserAttributes(data: ["full_name": .string(fullName)])
        )

        return dto.toUser()
    }

    func updatePassword(_ password: String) async throws {
        _ = try await supabase.auth.update(user: UserAttributes(password: password))
    }

    func deleteAccount() async throws {
        let session = try await supabase.auth.session
        try await supabase.auth.admin.deleteUser(id: session.user.id, shouldSoftDelete: true)
        try await signOut()
    }

    /// Returns nil when no session exists (app launch / logged out).
    func currentUser() async throws -> User? {
        guard let session = try? await supabase.auth.session else { return nil }
        return try? await fetchProfile(userId: session.user.id)
    }

    // MARK: - Profile (private)

    private func fetchProfile(userId: UUID) async throws -> User {
        let dto: ProfileDTO = try await supabase
            .from("profiles")
            .select()
            .eq("id", value: userId.uuidString)
            .single()
            .execute()
            .value
        return dto.toUser()
    }

    private func createProfile(userId: UUID, email: String, fullName: String) async throws -> User {
        let dto: ProfileDTO = try await supabase
            .from("profiles")
            .insert(ProfileInsertDTO(id: userId, email: email, fullName: fullName))
            .select()
            .single()
            .execute()
            .value
        return dto.toUser()
    }
}

// MARK: - DTOs (private to this file — not exposed outside)

private struct ProfileDTO: Codable {
    let id: UUID
    let email: String
    let fullName: String
    let role: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, email, role
        case fullName   = "full_name"
        case createdAt  = "created_at"
    }

    func toUser() -> User {
        User(
            id:         id,
            email:      email,
            fullName:   fullName,
            role:       UserRole(rawValue: role) ?? .citizen,
            createdAt:  createdAt
        )
    }
}

private struct ProfileInsertDTO: Encodable {
    let id: UUID
    let email: String
    let fullName: String
    let role: String = UserRole.citizen.rawValue

    enum CodingKeys: String, CodingKey {
        case id, email, role
        case fullName = "full_name"
    }
}

private struct ProfileUpdateDTO: Encodable {
    let fullName: String

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
    }
}
