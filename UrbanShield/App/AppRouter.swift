//
//  AppRouter.swift
//  UrbanShield
//

import SwiftUI

/// Giriş yapan kullanıcının rolüne göre hangi ana ekranın gösterileceğini çözer.
/// Sonraki fazlarda deep link, sheet routing vb. desteklemek için burası genişletilebilir.
struct AppRouter {

    @MainActor
    @ViewBuilder
    static func homeView(for role: UserRole, sessionViewModel: AuthSessionViewModel) -> some View {
        // Bu switch uygulama seviyesindeki RBAC giriş noktasıdır.
        // Gerçek güvenlik sınırı yine veritabanındaki RLS kurallarıdır.
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
