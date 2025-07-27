import Foundation
import CoreLocation
import MapKit

class LocationService: NSObject, ObservableObject {
    private let locationManager = CLLocationManager()
    
    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var route: [CLLocation] = []
    @Published var totalDistance: Double = 0.0
    @Published var currentSpeed: Double = 0.0 // m/s
    @Published var currentPace: Double = 0.0 // min/km
    @Published var currentAltitude: Double = 0.0 // meters
    @Published var accuracy: Double = 0.0 // meters
    @Published var isGPSReady: Bool = false
    
    private var isTracking = false
    private var isPaused = false
    private var lastLocation: CLLocation?
    private var startTime: Date?
    private var pausedTime: TimeInterval = 0
    
    // Route optimization
    private let minimumDistance: Double = 5.0 // meters
    private let minimumTimeInterval: TimeInterval = 2.0 // seconds
    private let maximumAccuracy: Double = 10.0 // meters
    
    override init() {
        super.init()
        setupLocationManager()
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = minimumDistance
        locationManager.allowsBackgroundLocationUpdates = false // Will be enabled during tracking
        authorizationStatus = locationManager.authorizationStatus
        
        // Start getting location to warm up GPS
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            locationManager.startUpdatingLocation()
        }
    }
    
    func requestLocationPermission() {
        switch authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            break
        case .authorizedWhenInUse:
            locationManager.requestAlwaysAuthorization()
        case .authorizedAlways:
            break
        @unknown default:
            break
        }
    }
    
    func startTracking() {
        guard authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse else {
            print("❌ Location permission not granted for tracking")
            requestLocationPermission()
            return
        }
        
        isTracking = true
        isPaused = false
        route.removeAll()
        totalDistance = 0.0
        lastLocation = nil
        startTime = Date()
        pausedTime = 0
        currentSpeed = 0.0
        currentPace = 0.0
        
        // Configure for high accuracy tracking
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = minimumDistance
        
        // Enable background location for workout tracking
        if authorizationStatus == .authorizedAlways {
            locationManager.allowsBackgroundLocationUpdates = true
        }
        locationManager.pausesLocationUpdatesAutomatically = false
        
        locationManager.startUpdatingLocation()
        print("✅ Started GPS tracking with high accuracy")
    }
    
    func stopTracking() {
        isTracking = false
        isPaused = false
        locationManager.stopUpdatingLocation()
        locationManager.allowsBackgroundLocationUpdates = false
        
        print("✅ Stopped GPS tracking. Total distance: \(String(format: "%.2f", totalDistance/1000))km")
    }
    
    func pauseTracking() {
        guard isTracking else { return }
        isPaused = true
        
        // Calculate paused time
        if let startTime = startTime {
            pausedTime += Date().timeIntervalSince(startTime)
        }
        
        locationManager.stopUpdatingLocation()
        print("⏸️ Paused GPS tracking")
    }
    
    func resumeTracking() {
        guard isTracking else { return }
        isPaused = false
        startTime = Date() // Reset start time for pause calculation
        
        locationManager.startUpdatingLocation()
        print("▶️ Resumed GPS tracking")
    }
    
    var averagePace: Double {
        guard totalDistance > 0, !route.isEmpty else { return 0.0 }
        
        let totalTime = route.last?.timestamp.timeIntervalSince(route.first?.timestamp ?? Date()) ?? 0
        let distanceKm = totalDistance / 1000.0
        
        return (totalTime / 60.0) / distanceKm // minutes per km
    }
    
    var routeCoordinates: [CLLocationCoordinate2D] {
        return route.map { $0.coordinate }
    }
    
    func getElevationGain() -> Double {
        var elevationGain: Double = 0.0
        
        for i in 1..<route.count {
            let altitudeDifference = route[i].altitude - route[i-1].altitude
            if altitudeDifference > 0 {
                elevationGain += altitudeDifference
            }
        }
        
        return elevationGain
    }
    
    func getRouteMapItems() -> [MKMapItem] {
        let placemark = MKPlacemark(coordinate: route.first?.coordinate ?? CLLocationCoordinate2D())
        return [MKMapItem(placemark: placemark)]
    }
}

extension LocationService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // Update current location for GPS readiness indicator
        DispatchQueue.main.async {
            self.currentLocation = location
            self.currentAltitude = location.altitude
            self.accuracy = location.horizontalAccuracy
            self.isGPSReady = location.horizontalAccuracy <= self.maximumAccuracy
        }
        
        // Only process location updates if actively tracking and not paused
        guard isTracking && !isPaused else { return }
        
        // Filter out old, inaccurate, or invalid locations
        let locationAge = -location.timestamp.timeIntervalSinceNow
        guard locationAge < 5.0,
              location.horizontalAccuracy > 0,
              location.horizontalAccuracy <= maximumAccuracy else {
            print("⚠️ Filtered out location: age=\(locationAge)s, accuracy=\(location.horizontalAccuracy)m")
            return
        }
        
        // Check minimum distance and time requirements
        if let lastLoc = lastLocation {
            let distance = location.distance(from: lastLoc)
            let timeInterval = location.timestamp.timeIntervalSince(lastLoc.timestamp)
            
            // Skip if too close or too soon (prevents GPS noise)
            guard distance >= minimumDistance || timeInterval >= minimumTimeInterval else {
                return
            }
            
            // Calculate running metrics
            DispatchQueue.main.async {
                self.totalDistance += distance
                
                if timeInterval > 0 && distance > 0 {
                    // Current speed (m/s)
                    self.currentSpeed = distance / timeInterval
                    
                    // Current pace (min/km)
                    if self.currentSpeed > 0.1 { // Avoid division by very small numbers
                        self.currentPace = (1000.0 / self.currentSpeed) / 60.0
                    }
                }
            }
        }
        
        // Add location to route
        DispatchQueue.main.async {
            self.route.append(location)
            self.lastLocation = location
        }
        
        print("📍 Location updated: accuracy=\(String(format: "%.1f", location.horizontalAccuracy))m, distance=\(String(format: "%.0f", totalDistance))m")
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        DispatchQueue.main.async {
            self.authorizationStatus = status
        }
        
        switch status {
        case .authorizedWhenInUse:
            print("✅ Location permission granted (when in use)")
            locationManager.startUpdatingLocation() // Warm up GPS
            
        case .authorizedAlways:
            print("✅ Location permission granted (always) - background tracking available")
            locationManager.startUpdatingLocation() // Warm up GPS
            
        case .denied:
            print("❌ Location permission denied")
            stopTracking()
            
        case .restricted:
            print("❌ Location permission restricted")
            stopTracking()
            
        case .notDetermined:
            print("⚠️ Location permission not determined")
            
        @unknown default:
            print("⚠️ Unknown location authorization status: \(status.rawValue)")
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ Location manager failed: \(error.localizedDescription)")
        
        if let clError = error as? CLError {
            switch clError.code {
            case .denied:
                print("❌ Location access denied")
            case .locationUnknown:
                print("⚠️ Location unknown - continuing to try")
            case .network:
                print("❌ Network error while getting location")
            default:
                print("❌ Other location error: \(clError.localizedDescription)")
            }
        }
    }
}