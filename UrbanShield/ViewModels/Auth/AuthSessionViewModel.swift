//
//  AuthSessionViewModel.swift
//  UrbanShield
//

import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class AuthSessionViewModel {

    // Kök oturum durumu. RootView/ContentView bunu kullanarak
    // login ekranlarının mı yoksa role dayalı giriş yapılmış uygulamanın mı gösterileceğine karar verir.
    var session: AppSession = .loading
    var errorMessage: String?
    var isPasswordRecoveryFlow = false

    @ObservationIgnored
    private var observeAuthChangesTask: Task<Void, Never>?

    init() {
        // Kullanıcı reset linkini açtığında Supabase passwordRecovery event’i gönderir.
        // Uygulama daha sonra PasswordRecoveryView ekranına yönlenir.
        observeAuthChangesTask = Task { [weak self] in
            for await (event, _) in supabase.auth.authStateChanges {
                guard let self else { return }

                if event == .passwordRecovery {
                    isPasswordRecoveryFlow = true
                }
            }
        }
    }

    deinit {
        observeAuthChangesTask?.cancel()
    }

    func restoreSession() async {
        // Uygulama açılışında çağrılır. Supabase oturumu hâlâ varsa
        // ilgili profil satırını çeker ve giriş yapılmış uygulama durumunu geri yükler.
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
        // Request kabul etme veya volunteer task tamamlama gibi role/availability
        // değişikliklerinden sonra profili yeniden çeker.
        if let user = try? await AuthService.shared.currentUser() {
            session = .authenticated(user)
        }
    }

    func handleAuthRedirect(_ url: URL) async {
        do {
            try await AuthService.shared.handleAuthRedirect(url)

            if isPasswordResetRedirect(url) {
                isPasswordRecoveryFlow = true
            } else {
                await refreshCurrentUser()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() async {
        // Supabase oturumunu bitirir ve RootView’i unauthenticated akışa döndürür.
        do {
            try await AuthService.shared.signOut()
            session = .unauthenticated
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteAccount() async throws {
        try await AuthService.shared.deleteAccount()
        session = .unauthenticated
    }

    private func isPasswordResetRedirect(_ url: URL) -> Bool {
        url.scheme == AuthService.passwordResetRedirectURL.scheme
            && url.host == AuthService.passwordResetRedirectURL.host
    }
}
