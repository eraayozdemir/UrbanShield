//
//  LoginViewModel.swift
//  UrbanShield
//

import Foundation
import Observation

@MainActor
@Observable
final class LoginViewModel {

    var email: String = ""
    var password: String = ""
    var isLoading: Bool = false
    var errorMessage: String?

    func signIn() async -> User? {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            return try await AuthService.shared.signIn(email: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}
