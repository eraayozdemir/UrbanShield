//
//  AppError.swift
//  UrbanShield
//

import Foundation

/// Centralized error type for the UrbanShield app.
/// All layers (data, domain, presentation) use this for consistent error handling.
enum AppError: LocalizedError {

    case authFailed(String)
    case profileNotFound
    case networkFailed(String)
    case unknown

    var errorDescription: String? {
        switch self {
        case .authFailed(let msg):      return msg
        case .profileNotFound:          return "User profile could not be found."
        case .networkFailed(let msg):   return msg
        case .unknown:                  return "An unexpected error occurred."
        }
    }
}
