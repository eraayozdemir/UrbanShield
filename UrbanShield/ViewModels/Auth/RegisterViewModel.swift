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
    var isLoading: Bool = false
    var errorMessage: String?

    func signUp() async -> User? {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            return try await AuthService.shared.signUp(
                email: email,
                password: password,
                fullName: fullName
            )
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}
