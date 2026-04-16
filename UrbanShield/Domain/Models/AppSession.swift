//
//  AppSession.swift
//  UrbanShield
//

/// Represents the current authentication state of the app.
/// RootView switches its displayed screen based on this value.
enum AppSession: Sendable {
    case loading            // initial state — determining if a session exists
    case unauthenticated    // no active session → show login/register
    case authenticated(User) // active session with a loaded profile
}
