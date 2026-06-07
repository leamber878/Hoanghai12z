import Foundation
import CoreLocation
import UIKit
import Combine

// ==========================================
//  LocationManager - Quản lý định vị GPS
//  Hỗ trợ cả foreground và background tracking
// ==========================================

@MainActor
final class LocationManager: NSObject, ObservableObject {
    
    // MARK: - Singleton
    static let shared = LocationManager()
    
    // MARK: - Published State
    @Published var trackingState: TrackingState = .stopped
    @Published var currentLocation: CLLocation?
    @Published var lastLocations: [CLLocation] = []
    @Published var distanceTraveled: Double = 0       // mét
    @Published var totalLocations: Int = 0
    @Published var averageSpeed: Double = 0            // km/h
    @Published var maxSpeed: Double = 0                // km/h
    
    // MARK: - Private
    private let locationManager = CLLocationManager()
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var timer: Timer?
    
    // Cấu hình tracking
    private let minDistance: Double = 10        // mét tối thiểu giữa 2 lần ghi
    private let minInterval: TimeInterval = 5   // giây tối thiểu giữa 2 lần ghi
    private var lastSavedLocation: CLLocation?
    private var lastSaveTime: Date?
    
    // Callback khi có location mới
    var onNewLocation: ((CLLocation) -> Void)?
    
    // Tốc độ tính toán
    private var speedSamples: [Double] = []
    
    private override init() {
        super.init()
        setupLocationManager()
    }
    
    // MARK: - Setup
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.showsBackgroundLocationIndicator = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.activityType = .fitness
    }
    
    // MARK: - Public Methods
    
    /// Yêu cầu quyền truy cập vị trí
    func requestPermission() {
        locationManager.requestAlwaysAuthorization()
    }
    
    /// Bắt đầu theo dõi
    func startTracking() {
        let status = locationManager.authorizationStatus
        
        guard status == .authorizedAlways || status == .authorizedWhenInUse else {
            trackingState = .error("Chưa được cấp quyền truy cập vị trí")
            requestPermission()
            return
        }
        
        resetTrackingData()
        
        if status == .authorizedAlways {
            locationManager.startUpdatingLocation()
            locationManager.startMonitoringSignificantLocationChanges()
            locationManager.startUpdatingHeading()
            print("📍 Bắt đầu theo dõi GPS (Always + Significant Changes)")
        } else {
            locationManager.startUpdatingLocation()
            print("📍 Bắt đầu theo dõi GPS (WhenInUse)")
        }
        
        trackingState = .tracking
        setupBackgroundTimer()
    }
    
    /// Dừng theo dõi
    func stopTracking() {
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        locationManager.stopUpdatingHeading()
        timer?.invalidate()
        timer = nil
        trackingState = .stopped
        print("⏹ Đã dừng theo dõi GPS")
    }
    
    /// Tạm dừng / tiếp tục
    func togglePause() {
        switch trackingState {
        case .tracking:
            locationManager.stopUpdatingLocation()
            trackingState = .paused
            print("⏸ Tạm dừng tracking")
        case .paused:
            locationManager.startUpdatingLocation()
            trackingState = .tracking
            print("▶️ Tiếp tục tracking")
        default:
            break
        }
    }
    
    /// Xoá dữ liệu tracking
    func resetTrackingData() {
        lastLocations.removeAll()
        distanceTraveled = 0
        totalLocations = 0
        averageSpeed = 0
        maxSpeed = 0
        speedSamples.removeAll()
        lastSavedLocation = nil
        lastSaveTime = nil
    }
    
    /// Lấy thông tin thiết bị
    func getDeviceInfo() -> DeviceInfo {
        let device = UIDevice.current
        return DeviceInfo(
            deviceId: device.identifierForVendor?.uuidString ?? UUID().uuidString,
            deviceName: device.name,
            deviceModel: device.model,
            osVersion: "\(device.systemName) \(device.systemVersion)",
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        )
    }
    
    // MARK: - Background Support
    
    private func setupBackgroundTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: minInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkBackgroundTask()
            }
        }
    }
    
    private func checkBackgroundTask() {
        let state = UIApplication.shared.applicationState
        if state == .background && trackingState == .tracking {
            beginBackgroundTask()
        }
    }
    
    private func beginBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
        }
        
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
        }
    }
    
    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
}

// MARK: - CLLocationManagerDelegate
extension LocationManager: CLLocationManagerDelegate {
    
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            handleAuthChange(manager.authorizationStatus)
        }
    }
    
    private func handleAuthChange(_ status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways:
            print("✅ Đã cấp quyền Always Access")
            if trackingState == .tracking {
                locationManager.startUpdatingLocation()
            }
        case .authorizedWhenInUse:
            print("✅ Đã cấp quyền WhenInUse")
        case .denied, .restricted:
            trackingState = .error("Vui lòng cấp quyền truy cập vị trí trong Settings")
        case .notDetermined:
            print("⏳ Chưa xác định quyền")
        @unknown default:
            break
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            processLocations(locations)
        }
    }
    
    private func processLocations(_ locations: [CLLocation]) {
        for location in locations {
            // Filter: bỏ location không hợp lệ
            guard location.horizontalAccuracy >= 0 && location.horizontalAccuracy < 100 else { continue }
            
            // Cập nhật current location
            currentLocation = location
            
            // Tính khoảng cách từ lần ghi trước
            if let last = lastSavedLocation {
                let dist = location.distance(from: last)
                if dist >= minDistance || Date().timeIntervalSince(lastSaveTime ?? .distantPast) >= 30 {
                    // Lưu location
                    lastLocations.append(location)
                    distanceTraveled += dist
                    totalLocations += 1
                    lastSavedLocation = location
                    lastSaveTime = Date()
                    
                    // Gửi callback
                    onNewLocation?(location)
                    
                    // Cập nhật tốc độ
                    updateSpeed(location.speed)
                }
            } else {
                // Lần đầu tiên
                lastSavedLocation = location
                lastSaveTime = Date()
                lastLocations.append(location)
                totalLocations += 1
                onNewLocation?(location)
            }
        }
    }
    
    private func updateSpeed(_ speed: CLLocationSpeed) {
        guard speed >= 0 else { return }
        
        speedSamples.append(speed)
        if speedSamples.count > 10 {
            speedSamples.removeFirst()
        }
        
        let avgMps = speedSamples.reduce(0, +) / Double(speedSamples.count)
        averageSpeed = avgMps * 3.6  // m/s → km/h
        
        if speed > maxSpeed {
            maxSpeed = speed * 3.6
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            print("❌ Location error: \(error.localizedDescription)")
            if let clErr = error as? CLError {
                switch clErr.code {
                case .denied:
                    trackingState = .error("Quyền truy cập vị trí bị từ chối")
                case .locationUnknown:
                    break // Tạm thời không có GPS
                default:
                    trackingState = .error(clErr.localizedDescription)
                }
            }
        }
    }
}
