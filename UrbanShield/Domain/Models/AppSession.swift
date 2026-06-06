//
//  AppSession.swift
//  UrbanShield
//

/// Uygulamanın mevcut kimlik doğrulama durumunu temsil eder.
/// RootView gösterilecek ekranı bu değere göre değiştirir.
enum AppSession: Sendable {
    case loading            // initial state — determining if a session exists
    case unauthenticated    // no active session → show login/register
    case authenticated(User) // active session with a loaded profile
}
