import CoreLocation
import Observation

@Observable
final class LocationManager {
    private(set) var location: CLLocation?
    private(set) var isDenied = false

    private var updatesTask: Task<Void, Never>?
    private var serviceSession: CLServiceSession?

    func start() {
        guard updatesTask == nil else { return }
        serviceSession = CLServiceSession(authorization: .whenInUse)
        updatesTask = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(.fitness) {
                    guard let self else { return }
                    isDenied = update.authorizationDenied || update.authorizationDeniedGlobally
                    if let newLocation = update.location {
                        location = newLocation
                    }
                }
            } catch {
                self?.location = nil
            }
        }
    }

    func stop() {
        updatesTask?.cancel()
        updatesTask = nil
        serviceSession?.invalidate()
        serviceSession = nil
    }
}
