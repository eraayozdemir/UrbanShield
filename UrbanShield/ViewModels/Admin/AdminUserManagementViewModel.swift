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
}

private struct AdminRoleUpdate: Encodable {
    let role: String
}
