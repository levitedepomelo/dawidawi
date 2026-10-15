import CoreLocation
import Foundation

/// Ubicación opcional. El permiso solo se solicita cuando el usuario activa la opción.
@MainActor
final class LocationProvider: NSObject, ObservableObject {
    static let shared = LocationProvider()

    @Published private(set) var status: CLAuthorizationStatus = .notDetermined
    private let manager = CLLocationManager()
    private var waiters: [CheckedContinuation<CLLocation?, Never>] = []

    private override init() {
        super.init()
        status = manager.authorizationStatus
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var isAuthorized: Bool {
        status == .authorizedWhenInUse || status == .authorizedAlways
    }

    var isDenied: Bool { status == .denied || status == .restricted }

    func requestPermissionIfNeeded() {
        if status == .notDetermined { manager.requestWhenInUseAuthorization() }
    }

    /// Ubicación actual con tiempo máximo de espera. Devuelve nil si no hay permiso o no llega a tiempo.
    func currentLocation(timeout: TimeInterval = 8) async -> CLLocation? {
        guard isAuthorized else { return nil }
        if let recent = manager.location, abs(recent.timestamp.timeIntervalSinceNow) < 60 {
            return recent
        }
        return await withCheckedContinuation { cont in
            waiters.append(cont)
            manager.requestLocation()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self.resolve(self.manager.location)
            }
        }
    }

    private func resolve(_ location: CLLocation?) {
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume(returning: location) }
    }

    /// Nombre legible del lugar (calle/barrio/ciudad). Es geocodificación inversa de coordenadas,
    /// no tiene nada que ver con el contenido de la foto.
    func placeName(for location: CLLocation) async -> String? {
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location)
        guard let p = placemarks?.first else { return nil }
        let parts = [p.name, p.locality].compactMap { $0 }
        var unique: [String] = []
        for part in parts where !unique.contains(part) { unique.append(part) }
        return unique.isEmpty ? nil : unique.joined(separator: ", ")
    }
}

extension LocationProvider: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let newStatus = manager.authorizationStatus
        Task { @MainActor in self.status = newStatus }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        Task { @MainActor in self.resolve(last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.resolve(nil) }
    }
}
