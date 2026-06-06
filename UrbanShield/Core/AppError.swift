//
//  AppError.swift
//  UrbanShield
//

import Foundation

/// UrbanShield uygulaması için merkezi hata tipi.
/// Tüm katmanlar tutarlı hata yönetimi için bu tipi kullanır.
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

extension Error {
    var isCancellation: Bool {
        if self is CancellationError {
            return true
        }

        if let urlError = self as? URLError, urlError.code == .cancelled {
            return true
        }

        let nsError = self as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}
