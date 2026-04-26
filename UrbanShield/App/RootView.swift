//
//  RootView.swift
//  UrbanShield
//

import SwiftUI

/// The top-level view — switches between loading, auth, and role-based home screens.
/// Owns AuthSessionViewModel and passes it down the view hierarchy.
struct RootView: View {

    @State private var sessionViewModel = AuthSessionViewModel()

    var body: some View {
        Group {
            switch sessionViewModel.session {

            case .loading:
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .unauthenticated:
                LoginView(sessionViewModel: sessionViewModel)

            case .authenticated(let user):
                AppRouter.homeView(for: user.role, sessionViewModel: sessionViewModel)
            }
        }
        .task {
            await sessionViewModel.restoreSession()
        }
        .onOpenURL { url in
            Task {
                await sessionViewModel.handleAuthRedirect(url)
            }
        }
        .sheet(isPresented: $sessionViewModel.isPasswordRecoveryFlow) {
            PasswordRecoveryView(sessionViewModel: sessionViewModel)
        }
    }
}
