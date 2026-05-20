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
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !password.isEmpty else {
            errorMessage = "Please enter your email and password."
            return nil
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            return try await AuthService.shared.signIn(email: trimmedEmail, password: password)
        } catch {
            errorMessage = friendlySignInError(from: error)
            return nil
        }
    }

    private func friendlySignInError(from error: Error) -> String {
        if let appError = error as? AppError,
           let description = appError.errorDescription {
            return description
        }

        let message = error.localizedDescription
        let lowercasedMessage = message.lowercased()

        if lowercasedMessage.contains("invalid login credentials")
            || lowercasedMessage.contains("invalid credentials")
            || lowercasedMessage.contains("email not found")
            || lowercasedMessage.contains("user not found") {
            return "Email or password is incorrect. Please check your details and try again."
        }

        if lowercasedMessage.contains("email not confirmed")
            || lowercasedMessage.contains("not confirmed") {
            return "Please confirm your email address before signing in."
        }

        if lowercasedMessage.contains("too many")
            || lowercasedMessage.contains("rate limit") {
            return "Too many sign-in attempts. Please wait a moment and try again."
        }

        if lowercasedMessage.contains("network")
            || lowercasedMessage.contains("offline")
            || lowercasedMessage.contains("timed out")
            || lowercasedMessage.contains("internet") {
            return "Sign in failed because the connection is not stable. Please check your internet and try again."
        }

        if lowercasedMessage.contains("suspended") {
            return "This account has been suspended. Please contact an administrator."
        }

        return "Sign in failed. Please try again."
    }
}
