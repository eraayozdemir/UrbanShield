//
//  AuthSessionViewModel.swift
//  UrbanShield
//

import Foundation
import Observation

@MainActor
@Observable
final class AuthSessionViewModel {

    var session: AppSession = .loading
    var errorMessage: String?

    func restoreSession() async {
        session = .loading
        if let user = try? await AuthService.shared.currentUser() {
            session = .authenticated(user)
        } else {
            session = .unauthenticated
        }
    }

    func setAuthenticated(_ user: User) {
        session = .authenticated(user)
    }

    func refreshCurrentUser() async {
        if let user = try? await AuthService.shared.currentUser() {
            session = .authenticated(user)
        }
    }

    func signOut() async {
        do {
            try await AuthService.shared.signOut()
            session = .unauthenticated
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
