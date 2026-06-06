//
//  AdminUserManagementViewModel.swift
//  UrbanShield
//

import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class AdminUserManagementViewModel {

    // AdminUserManagementView içinde gösterilen kullanıcı listesi.
    var users: [ProfileUserRecord] = []
    var isLoading = false
    var updatingUserId: UUID?
    var errorMessage: String?
    var successMessage: String?

    func loadUsers(currentUser: User?) async {
        errorMessage = nil
        successMessage = nil

        guard currentUser?.role == .admin else {
            errorMessage = "Only admins can manage users."
            users = []
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            // Admin role ve suspension yönetimi için tüm profile satırlarını görür.
            users = try await supabase
                .from("profiles")
                .select()
                .order("created_at", ascending: false)
                .execute()
                .value
        } catch where error.isCancellation {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateRole(
        user: ProfileUserRecord,
        role: UserRole,
        currentUser: User?
    ) async {
        errorMessage = nil
        successMessage = nil

        guard let currentUser, currentUser.role == .admin else {
            errorMessage = "Only admins can update user roles."
            return
        }

        guard user.id != currentUser.id else {
            errorMessage = "You cannot change your own admin role from the app."
            return
        }

        updatingUserId = user.id
        defer { updatingUserId = nil }

        do {
            // Role güncellemesi yalnızca admin içindir. UI kullanıcının kendi admin rolünü düşürmesini engeller ve
            // RLS/RPC politikaları da yetkili role değişikliklerini korumalıdır.
            let updatedUser: ProfileUserRecord = try await supabase
                .from("profiles")
                .update(AdminRoleUpdate(role: role.rawValue))
                .eq("id", value: user.id.uuidString)
                .select()
                .single()
                .execute()
                .value

            if let index = users.firstIndex(where: { $0.id == user.id }) {
                users[index] = updatedUser
            }

            try? await ActivityLogger.log(
                actor: currentUser,
                action: .roleUpdated,
                targetType: .user,
                targetId: user.id,
                targetUserId: user.id,
                message: "\(updatedUser.fullName) role changed from \(user.roleValue.rawValue.capitalized) to \(role.rawValue.capitalized).",
                metadata: [
                    "old_role": user.roleValue.rawValue,
                    "new_role": role.rawValue
                ]
            )

            successMessage = "\(updatedUser.fullName) is now \(role.rawValue.capitalized)."
        } catch where error.isCancellation {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateSuspension(
        user: ProfileUserRecord,
        isSuspended: Bool,
        currentUser: User?
    ) async {
        errorMessage = nil
        successMessage = nil

        guard let currentUser, currentUser.role == .admin else {
            errorMessage = "Only admins can suspend users."
            return
        }

        guard user.id != currentUser.id else {
            errorMessage = "You cannot suspend your own admin account from the app."
            return
        }

        updatingUserId = user.id
        defer { updatingUserId = nil }

        do {
            // Suspension RPC kullanır çünkü kullanıcı active volunteer ise
            // backend task kaydını ve request kapasitesini güvenli şekilde boşa çıkarmalıdır.
            let updatedUsers: [ProfileUserRecord] = try await supabase
                .rpc(
                    "set_profile_suspension",
                    params: AdminSuspensionParams(
                        userId: user.id,
                        isSuspended: isSuspended
                    )
                )
                .execute()
                .value

            guard let updatedUser = updatedUsers.first else {
                errorMessage = "User could not be updated."
                return
            }

            if let index = users.firstIndex(where: { $0.id == user.id }) {
                users[index] = updatedUser
            }

            try? await ActivityLogger.log(
                actor: currentUser,
                action: .roleUpdated,
                targetType: .user,
                targetId: user.id,
                targetUserId: user.id,
                message: "\(updatedUser.fullName) account \(isSuspended ? "suspended" : "reactivated").",
                metadata: [
                    "moderation_action": isSuspended ? "suspended" : "reactivated",
                    "old_is_suspended": "\(user.isSuspendedValue)",
                    "new_is_suspended": "\(isSuspended)"
                ]
            )

            successMessage = isSuspended
                ? "\(updatedUser.fullName) has been suspended."
                : "\(updatedUser.fullName) has been reactivated."
        } catch where error.isCancellation {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct AdminRoleUpdate: Encodable {
    let role: String
}

private struct AdminSuspensionParams: Encodable {
    let userId: UUID
    let isSuspended: Bool

    enum CodingKeys: String, CodingKey {
        case userId = "p_user_id"
        case isSuspended = "p_is_suspended"
    }
}
