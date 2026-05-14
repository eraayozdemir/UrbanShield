//
//  DeviceLocationService.swift
//  UrbanShield
//

import Combine
import CoreLocation
import Foundation

@MainActor
final class DeviceLocationService: NSObject, ObservableObject {
    @Published private(set) var coordinate: CLLocationCoordinate2D?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var isRequestingLocation = false
    @Published private(set) var errorMessage: String?

    private let manager = CLLocationManager()

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var canRequestLocation: Bool {
        CLLocationManager.locationServicesEnabled()
            && authorizationStatus != .restricted
            && authorizationStatus != .denied
    }

    func requestCurrentLocation() {
        errorMessage = nil

        guard CLLocationManager.locationServicesEnabled() else {
            errorMessage = "Location Services are disabled on this device."
            return
        }

        switch authorizationStatus {
        case .notDetermined:
            isRequestingLocation = true
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            isRequestingLocation = true
            manager.requestLocation()
        case .denied:
            errorMessage = "Location permission is denied. Enable it in Settings or enter coordinates manually."
        case .restricted:
            errorMessage = "Location permission is restricted on this device."
        @unknown default:
            errorMessage = "Location permission could not be checked."
        }
    }

    func clearError() {
        errorMessage = nil
    }
}

extension DeviceLocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus

            if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
                manager.requestLocation()
            } else if authorizationStatus == .denied || authorizationStatus == .restricted {
                isRequestingLocation = false
                errorMessage = "Location permission is unavailable. Enter coordinates manually or allow location access in Settings."
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        Task { @MainActor in
            coordinate = location.coordinate
            isRequestingLocation = false
            errorMessage = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            isRequestingLocation = false

            if let locationError = error as? CLError, locationError.code == .denied {
                errorMessage = "Location permission is denied. Enter coordinates manually or allow location access in Settings."
            } else {
                errorMessage = "Could not get your current location. You can still enter coordinates manually."
            }
        }
    }
}
