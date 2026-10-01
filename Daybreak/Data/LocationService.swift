import CoreLocation

/// The phone's location as a [Place], through CoreLocation with the When-In-Use permission, named by reverse
/// geocoding ("Weston"). Asks for permission the first time; a single fix, with a timeout.
@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    enum Outcome {
        case place(Place)
        /// The user said no, or the phone doesn't allow it (parental controls, MDM).
        case denied
        /// Allowed, but no fix came (no signal, or Location Services off).
        case unavailable
    }

    private let manager = CLLocationManager()
    private var authorizationWaiters: [CheckedContinuation<CLAuthorizationStatus, Never>] = []
    private var locationWaiter: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        // A town's name and its weather need no more than this, and it's quicker and kinder to the battery.
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var status: CLAuthorizationStatus { manager.authorizationStatus }

    func currentPlace() async -> Outcome {
        var status = manager.authorizationStatus
        if status == .notDetermined {
            status = await withCheckedContinuation { continuation in
                authorizationWaiters.append(continuation)
                manager.requestWhenInUseAuthorization()
            }
        }
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return .denied }
        guard let location = await oneFix() else { return .unavailable }
        let name = await placeName(location)
        return .place(Place(
            id: Place.currentLocationId,
            name: name.name ?? "Current location",
            region: name.region,
            country: name.country,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            countryCode: name.countryCode
        ))
    }

    /// A fresh fix if one comes within 15 seconds, else the last one the phone had.
    private func oneFix() async -> CLLocation? {
        if let pending = locationWaiter {
            locationWaiter = nil
            pending.resume(returning: nil)
        }
        let fix: CLLocation? = await withCheckedContinuation { continuation in
            locationWaiter = continuation
            manager.requestLocation()
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(15))
                self?.finish(with: nil)
            }
        }
        return fix ?? manager.location
    }

    private func finish(with location: CLLocation?) {
        guard let waiter = locationWaiter else { return }
        locationWaiter = nil
        waiter.resume(returning: location)
    }

    /// Best-effort town, region and country for a location; nils when the phone can't resolve it.
    private func placeName(_ location: CLLocation) async -> (name: String?, region: String?, country: String?, countryCode: String?) {
        guard let mark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return (nil, nil, nil, nil) }
        let name = [mark.locality, mark.subAdministrativeArea, mark.administrativeArea]
            .compactMap { $0 }.first { !$0.isBlank }
        return (name, mark.administrativeArea, mark.country, mark.isoCountryCode?.uppercased())
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard status != .notDetermined else { return }
            let waiters = authorizationWaiters
            authorizationWaiters = []
            waiters.forEach { $0.resume(returning: status) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        Task { @MainActor in finish(with: last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in finish(with: nil) }
    }
}
