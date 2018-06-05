/*
See LICENSE folder for this sample’s licensing information.

Abstract:
iBeacon implementation for setting up at WWDC game room tables.
*/

import Foundation
import CoreLocation

private let regionUUID = UUID(uuidString: "53FA6CD3-DFE4-493C-8795-56E71D2DAEAF")!
private let regionId = "GameRoom"
private let log = Log()

struct GameTableLocation: Equatable, Hashable {
    typealias ProximityLocationId = Int
    let identifier: ProximityLocationId
    let name: String
    
    var hashValue: Int {
        return identifier.hashValue
    }
    
    private init(identifier: Int) {
        self.identifier = identifier
        self.name = "Table \(self.identifier)"
    }
    
    private static var locations: [ProximityLocationId: GameTableLocation] = [:]
    static func location(with identifier: ProximityLocationId) -> GameTableLocation {
        if let location = locations[identifier] {
            return location
        }
        
        let location = GameTableLocation(identifier: identifier)
        locations[identifier] = location
        return location
    }
    
    static func == (lhs: GameTableLocation, rhs: GameTableLocation) -> Bool {
        return lhs.identifier == rhs.identifier
    }
}

extension CLProximity: CustomStringConvertible {
    public var description: String {
        switch self {
        case .unknown:
            return "unknown"
        case .immediate:
            return "immediate"
        case .near:
            return "near"
        case .far:
            return "far"
        }
    }
}

protocol ProximityManagerDelegate: class {
    func proximityManager(_ manager: ProximityManager, didChange location: GameTableLocation?)
    func proximityManager(_ manager: ProximityManager, didChange authorization: Bool)
}

class ProximityManager: NSObject {
    static var shared = ProximityManager()

    let locationManager = CLLocationManager()
    let region = CLBeaconRegion(proximityUUID: regionUUID, identifier: regionId)
    var isAvailable: Bool {
        return CLLocationManager.isMonitoringAvailable(for: CLBeaconRegion.self)
    }
    var isAuthorized: Bool {
        return CLLocationManager.authorizationStatus() == .authorizedWhenInUse || CLLocationManager.authorizationStatus() == .authorizedAlways
    }
    
    var closestLocation: GameTableLocation?
    weak var delegate: ProximityManagerDelegate?
    
    override private init() {
        super.init()
        self.locationManager.delegate = self
        requestAuthorization()
    }

    func requestAuthorization() {
        if CLLocationManager.authorizationStatus() == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
    }
    
    func start() {
        guard isAvailable else { return }
        log.debug("Starting beacon ranging")
        locationManager.startRangingBeacons(in: region)
    }
    
    func stop() {
        guard isAvailable else { return }
        log.debug("Stopping beacon ranging")
        log.debug("Closest location is: \(closestLocation?.identifier ?? 0)")
        locationManager.stopRangingBeacons(in: region)
    }
}

extension ProximityManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didRangeBeacons beacons: [CLBeacon], in region: CLBeaconRegion) {
        // we want to filter out beacons that have unknown proximity
        let knownBeacons = beacons.filter { $0.proximity != CLProximity.unknown }
        for beacon in knownBeacons {
            let proximity = beacon.proximity.description
            log.debug("Beacon \(beacon.minor) proximity: \(proximity)")
        }
        if let beacon = knownBeacons.first {
            log.debug("First Beacon is \(beacon.minor)")
            var location: GameTableLocation? = nil
            if beacon.proximity == .near || beacon.proximity == .immediate {
                location = GameTableLocation.location(with: beacon.minor.intValue)
            }
            
            if closestLocation != location {
                log.debug("Closest location changed to: \(location?.identifier ?? 0)")
                closestLocation = location
                delegate?.proximityManager(self, didChange: location)
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, rangingBeaconsDidFailFor region: CLBeaconRegion, withError error: Error) {
        log.error("Ranging beacons failed for region \(region.identifier): (\(error.localizedDescription))")
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways:
            log.debug("Changed location authorization status: always")
        case .authorizedWhenInUse:
            log.debug("Changed location authorization status: when in use")
        case .denied:
            log.debug("Changed location authorization status: denied")
        case .notDetermined:
            log.debug("Changed location authorization status: not determined")
        case .restricted:
            log.debug("Changed location authorization status: restricted")
        }
        
        if let delegate = delegate {
            delegate.proximityManager(self, didChange: self.isAuthorized)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        log.error("Location manager did fail with error \(error.localizedDescription)")
    }
}
