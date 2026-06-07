import Foundation
import CoreLocation

// ==========================================
//  Models cho GPS Tracking iOS App
// ==========================================

// MARK: - Location Data gửi lên server
struct LocationUpdate: Codable {
    let deviceId: String
    let locations: [LocationPoint]
    let deviceInfo: DeviceInfo
}

struct LocationPoint: Codable {
    let latitude: Double
    let longitude: Double
    let altitude: Double?
    let horizontalAccuracy: Double?
    let verticalAccuracy: Double?
    let speed: Double?
    let course: Double?
    let timestamp: String
    let batteryLevel: Double?
    let isMoving: Bool?
}

struct DeviceInfo: Codable {
    let deviceId: String
    let deviceName: String
    let deviceModel: String
    let osVersion: String
    let appVersion: String
}

// MARK: - Response từ server
struct LocationResponse: Codable {
    let success: Bool
    let received: Int
    let stored: Int
    let skipped: Int
}

struct ServerHealth: Codable {
    let status: String
    let uptime: Double
    let locations: Int
    let devices: Int
    let version: String
}

// MARK: - Chuyển đổi CLLocation → LocationPoint
extension LocationPoint {
    init(from clLocation: CLLocation, batteryLevel: Float?) {
        self.latitude = clLocation.coordinate.latitude
        self.longitude = clLocation.coordinate.longitude
        self.altitude = clLocation.altitude
        self.horizontalAccuracy = clLocation.horizontalAccuracy
        self.verticalAccuracy = clLocation.verticalAccuracy
        self.speed = clLocation.speed >= 0 ? clLocation.speed : nil
        self.course = clLocation.course >= 0 ? clLocation.course : nil
        self.timestamp = ISO8601DateFormatter().string(from: clLocation.timestamp)
        self.batteryLevel = batteryLevel.map { Double($0) }
        self.isMoving = (clLocation.speed >= 0.5)
    }
}

// MARK: - App States
enum TrackingState {
    case stopped
    case tracking
    case paused
    case error(String)
    
    var label: String {
        switch self {
        case .stopped: return "⏹ Đã dừng"
        case .tracking: return "🟢 Đang theo dõi"
        case .paused: return "⏸ Tạm dừng"
        case .error(let msg): return "⚠️ \(msg)"
        }
    }
}

enum ConnectionState {
    case disconnected
    case connecting
    case connected
    case error(String)
    
    var label: String {
        switch self {
        case .disconnected: return "🔴 Mất kết nối"
        case .connecting: return "🟡 Đang kết nối..."
        case .connected: return "🟢 Đã kết nối"
        case .error(let msg): return "⚠️ \(msg)"
        }
    }
}
