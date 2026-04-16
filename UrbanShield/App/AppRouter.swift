//
//  AppRouter.swift
//  UrbanShield
//

import SwiftUI

/// Resolves which home screen to show based on the authenticated user's role.
/// Expand this in later phases to support deep links, sheet routing, etc.
struct AppRouter {

    @MainActor
    @ViewBuilder
    static func homeView(for role: UserRole, sessionViewModel: AuthSessionViewModel) -> some View {
        switch role {
        case .citizen:
            CitizenHomeView(sessionViewModel: sessionViewModel)
        case .volunteer:
            VolunteerHomeView(sessionViewModel: sessionViewModel)
        case .coordinator:
            CoordinatorHomeView(sessionViewModel: sessionViewModel)
        case .admin:
            AdminHomeView(sessionViewModel: sessionViewModel)
        }
    }
}
