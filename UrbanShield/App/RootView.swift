//
//  RootView.swift
//  UrbanShield
//

import SwiftUI

/// En üst seviye view; loading, auth ve role göre ana ekranlar arasında geçiş yapar.
/// AuthSessionViewModel örneğini sahiplenir ve view hiyerarşisine aktarır.
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
        .dismissKeyboardOnTap()
    }
}
