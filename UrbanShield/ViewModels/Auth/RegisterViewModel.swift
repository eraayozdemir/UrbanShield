//
//  RegisterViewModel.swift
//  UrbanShield
//

import Foundation
import Observation

@MainActor
@Observable
final class RegisterViewModel {

    var fullName: String = ""
    var email: String = ""
    var password: String = ""
    var confirmPassword: String = ""
    var isLoading: Bool = false
    var errorMessage: String?
    var didSignUp: Bool = false

    var passwordRequirements: [PasswordRequirement] {
        [
            PasswordRequirement(
                title: "At least 8 characters",
                isMet: password.count >= 8
            ),
            PasswordRequirement(
                title: "At least one uppercase letter",
                isMet: password.range(of: #"[A-Z]"#, options: .regularExpression) != nil
            ),
            PasswordRequirement(
                title: "At least one lowercase letter",
                isMet: password.range(of: #"[a-z]"#, options: .regularExpression) != nil
            ),
            PasswordRequirement(
                title: "At least one number",
                isMet: password.range(of: #"[0-9]"#, options: .regularExpression) != nil
            ),
            PasswordRequirement(
                title: "At least one special character",
                isMet: password.range(of: #"[!@#$%^&*()_+\-=\[\]{};'\\:\"|<>?,./`~]"#, options: .regularExpression) != nil
            )
        ]
    }

    var isPasswordValid: Bool {
        passwordRequirements.allSatisfy(\.isMet)
    }

    var doPasswordsMatch: Bool {
        !confirmPassword.isEmpty && password == confirmPassword
    }

    var canSubmit: Bool {
        !isLoading
            && !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && isPasswordValid
            && doPasswordsMatch
    }

    func signUp() async -> Bool {
        errorMessage = nil
        didSignUp = false

        guard isPasswordValid else {
            errorMessage = "Password does not meet the security requirements."
            return false
        }

        guard doPasswordsMatch else {
            errorMessage = "Passwords do not match."
            return false
        }

        isLoading = true
        defer { isLoading = false }

        do {
            _ = try await AuthService.shared.signUp(
                email: email,
                password: password,
                fullName: fullName
            )
            try? await AuthService.shared.signOut()
            didSignUp = true
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

struct PasswordRequirement: Identifiable {
    let id = UUID()
    let title: String
    let isMet: Bool
}
