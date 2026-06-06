//
//  AuthService.swift
//  UrbanShield
//
//  Tüm auth ve profile işlemleri için tek temas noktası.
//  AuthRepository, UserRepository ve tüm UseCase katmanlarının yerine geçer,
//            ayrıca AuthRemoteDataSource, UserRemoteDataSource, UserDTO ve UserMapper yerine kullanılır.
//

import Supabase
import Foundation

final class AuthService: Sendable {

    static let shared = AuthService()
    static let passwordResetRedirectURL = URL(string: "urbanshield://reset-password")!
    private init() {}

    // MARK: - Auth

    // Kayıt işlemi önce Supabase Auth kullanıcısı oluşturur, sonra eşleşen
    // role dayalı yönlendirme için kullanılan profil satırını oluşturur.
    func signUp(email: String, password: String, fullName: String) async throws -> User {
        let response = try await supabase.auth.signUp(email: email, password: password)
        return try await createProfile(userId: response.user.id, email: email, fullName: fullName)
    }

    func signIn(email: String, password: String) async throws -> User {
        let response = try await supabase.auth.signIn(email: email, password: password)
        let user = try await fetchProfile(userId: response.user.id)

        // Auth başarılı olsa bile suspended hesaplar uygulamaya devam edemez.
        if user.isSuspended {
            try? await signOut()
            throw AppError.authFailed("This account has been suspended. Please contact an administrator.")
        }

        return user
    }

    func signOut() async throws {
        try await supabase.auth.signOut()
    }

    func sendPasswordReset(email: String) async throws {
        try await supabase.auth.resetPasswordForEmail(
            email,
            redirectTo: Self.passwordResetRedirectURL
        )
    }

    func handleAuthRedirect(_ url: URL) async throws {
        _ = try await supabase.auth.session(from: url)
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

    @discardableResult
    func updateVolunteerProfile(
        availabilityStatus: VolunteerAvailability,
        skills: [VolunteerSkill]
    ) async throws -> User {
        // Citizen volunteer ayarları. Availability ve skills,
        // request kabul/atama işlemlerinde kullanılır.
        let session = try await supabase.auth.session
        let dto: ProfileDTO = try await supabase
            .from("profiles")
            .update(
                VolunteerProfileUpdateDTO(
                    availabilityStatus: availabilityStatus.rawValue,
                    volunteerSkills: skills.map(\.rawValue)
                )
            )
            .eq("id", value: session.user.id.uuidString)
            .select()
            .single()
            .execute()
            .value

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

    /// Oturum yoksa nil döndürür (uygulama açılışı / çıkış yapılmış durum).
    func currentUser() async throws -> User? {
        guard let session = try? await supabase.auth.session else { return nil }
        guard let user = try? await fetchProfile(userId: session.user.id) else { return nil }

        if user.isSuspended {
            try? await signOut()
            return nil
        }

        return user
    }

    // MARK: - Profile (private)

    private func fetchProfile(userId: UUID) async throws -> User {
        // profiles tablosunu okur ve veritabanı DTO modelini app User modeline çevirir.
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
        // Yeni kullanıcılar citizen olarak başlar. Admin/coordinator ataması
        // daha sonra admin akışı veya Supabase tarafındaki privileged operations ile yapılır.
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

// MARK: - DTOs (bu dosyaya private; dışarı açılmaz)

private struct ProfileDTO: Codable {
    let id: UUID
    let email: String
    let fullName: String
    let role: String
    let availabilityStatus: String?
    let volunteerSkills: [String]?
    let isSuspended: Bool?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, email, role
        case fullName   = "full_name"
        case availabilityStatus = "availability_status"
        case volunteerSkills = "volunteer_skills"
        case isSuspended = "is_suspended"
        case createdAt  = "created_at"
    }

    func toUser() -> User {
        User(
            id:         id,
            email:      email,
            fullName:   fullName,
            role:       UserRole(rawValue: role) ?? .citizen,
            availabilityStatus: VolunteerAvailability(rawValue: availabilityStatus ?? "") ?? .available,
            volunteerSkills: (volunteerSkills ?? []).compactMap(VolunteerSkill.init(rawValue:)),
            isSuspended: isSuspended ?? false,
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

private struct VolunteerProfileUpdateDTO: Encodable {
    let availabilityStatus: String
    let volunteerSkills: [String]

    enum CodingKeys: String, CodingKey {
        case availabilityStatus = "availability_status"
        case volunteerSkills = "volunteer_skills"
    }
}
