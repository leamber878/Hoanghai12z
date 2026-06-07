import Foundation
import CoreLocation

// ==========================================
//  NetworkManager - Giao tiếp với server
//  REST API + WebSocket realtime
// ==========================================

@MainActor
final class NetworkManager: ObservableObject {
    
    // MARK: - Singleton
    static let shared = NetworkManager()
    
    // MARK: - Published
    @Published var connectionState: ConnectionState = .disconnected
    @Published var lastSyncTime: Date?
    @Published var pendingCount: Int = 0
    @Published var totalSent: Int = 0
    
    // MARK: - Config
    var serverURL: String = "http://localhost:3000" {
        didSet { disconnect() }
    }
    var apiKey: String = "gps-tracker-secret-key-2024"
    
    // MARK: - Private
    private var webSocketTask: URLSessionWebSocketTask?
    private let session: URLSession
    private var pingTimer: Timer?
    private var reconnectTimer: Timer?
    private let maxRetries = 5
    private var retryCount = 0
    private var isReconnecting = false
    
    // Queue locations khi không có mạng
    private var offlineQueue: [LocationPoint] = []
    private let queueLock = NSLock()
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Connection
    
    /// Kết nối WebSocket tới server
    func connect() {
        guard let url = URL(string: serverURL) else {
            connectionState = .error("URL không hợp lệ: \(serverURL)")
            return
        }
        
        connectionState = .connecting
        retryCount = 0
        
        // Convert http -> ws
        var wsURL = url
        if var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.scheme = (components.scheme == "https" ? "wss" : "ws")
            if let wsURL2 = components.url {
                wsURL = wsURL2
            }
        }
        
        let wsURLString = "\(wsURL.absoluteString)/ws"
        guard let wsURLFinal = URL(string: wsURLString) ?? URL(string: "\(wsURL.absoluteString)") else { return }
        
        let request = URLRequest(url: wsURLFinal)
        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()
        receiveMessage()
        
        // Register device
        let deviceId = LocationManager.shared.getDeviceInfo().deviceId
        sendWSMessage(["event": "register:device", "data": deviceId])
        
        connectionState = .connected
        startPing()
        stopReconnect()
        
        // Gửi offline queue
        flushOfflineQueue()
        
        print("✅ WebSocket connected to \(serverURL)")
    }
    
    /// Ngắt kết nối
    func disconnect() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        pingTimer?.invalidate()
        pingTimer = nil
        stopReconnect()
        connectionState = .disconnected
        print("🔌 WebSocket disconnected")
    }
    
    // MARK: - Send Locations
    
    /// Gửi location lên server qua REST API
    func sendLocations(_ locations: [CLLocation], deviceInfo: DeviceInfo) async throws -> LocationResponse {
        guard let url = URL(string: "\(serverURL)/api/locations") else {
            throw NetworkError.invalidURL
        }
        
        let locationPoints = locations.map { LocationPoint(from: $0, batteryLevel: getBatteryLevel()) }
        let update = LocationUpdate(
            deviceId: deviceInfo.deviceId,
            locations: locationPoints,
            deviceInfo: deviceInfo
        )
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.httpBody = try JSONEncoder().encode(update)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw NetworkError.unauthorized
        }
        
        guard httpResponse.statusCode == 200 else {
            throw NetworkError.serverError(httpResponse.statusCode)
        }
        
        let result = try JSONDecoder().decode(LocationResponse.self, from: data)
        lastSyncTime = Date()
        totalSent += result.stored
        
        return result
    }
    
    /// Gửi location qua WebSocket (realtime, lightweight)
    func sendLocationRealtime(_ location: CLLocation) {
        guard case .connected = connectionState else {
            // Queue để gửi sau
            addToQueue(LocationPoint(from: location, batteryLevel: getBatteryLevel()))
            return
        }
        
        sendWSMessage([
            "event": "location:send",
            "data": [
                "deviceId": LocationManager.shared.getDeviceInfo().deviceId,
                "latitude": location.coordinate.latitude,
                "longitude": location.coordinate.longitude,
                "speed": location.speed >= 0 ? location.speed as Any : NSNull(),
                "altitude": location.altitude,
                "batteryLevel": getBatteryLevel() as Any,
                "timestamp": ISO8601DateFormatter().string(from: location.timestamp)
            ]
        ])
        
        totalSent += 1
    }
    
    // MARK: - Server Health
    
    func checkHealth() async -> ServerHealth? {
        guard let url = URL(string: "\(serverURL)/api/health") else { return nil }
        
        do {
            let (data, _) = try await session.data(from: url)
            return try JSONDecoder().decode(ServerHealth.self, from: data)
        } catch {
            print("⚠️ Health check failed: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - WebSocket Message Handler
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text):
                        self.handleMessage(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            self.handleMessage(text)
                        }
                    @unknown default:
                        break
                    }
                    // Continue receiving
                    self.receiveMessage()
                    
                case .failure(let error):
                    print("⚠️ WebSocket receive error: \(error.localizedDescription)")
                    self.handleDisconnect()
                }
            }
        }
    }
    
    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        
        if let event = json["event"] as? String {
            switch event {
            case "registered":
                print("✅ Device registered with server")
            case "pong":
                break
            default:
                print("📩 WS event: \(event) - \(json)")
            }
        }
    }
    
    private func sendWSMessage(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: data, encoding: .utf8) else { return }
        
        webSocketTask?.send(.string(text)) { [weak self] error in
            if let error = error {
                print("⚠️ WS send error: \(error)")
                Task { @MainActor in
                    self?.handleDisconnect()
                }
            }
        }
    }
    
    private func sendWSMessage(_ text: String) {
        webSocketTask?.send(.string(text)) { [weak self] error in
            if let error = error {
                print("⚠️ WS send error: \(error)")
                Task { @MainActor in
                    self?.handleDisconnect()
                }
            }
        }
    }
    
    // MARK: - Connection Management
    
    private func startPing() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { [weak self] _ in
            self?.sendWSMessage(["event": "ping"])
        }
    }
    
    private func handleDisconnect() {
        connectionState = .disconnected
        webSocketTask = nil
        pingTimer?.invalidate()
        startReconnect()
    }
    
    private func startReconnect() {
        guard !isReconnecting else { return }
        isReconnecting = true
        connectionState = .connecting
        
        let delay = min(Double(retryCount) * 2.0 + 1.0, 30.0)
        print("🔄 Reconnecting in \(delay)s (attempt \(retryCount + 1)/\(maxRetries))")
        
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.retryCount < self.maxRetries else {
                    self?.connectionState = .error("Không thể kết nối tới server")
                    self?.isReconnecting = false
                    return
                }
                self.retryCount += 1
                self.isReconnecting = false
                self.connect()
            }
        }
    }
    
    private func stopReconnect() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        isReconnecting = false
        retryCount = 0
    }
    
    // MARK: - Offline Queue
    
    private func addToQueue(_ point: LocationPoint) {
        queueLock.lock()
        offlineQueue.append(point)
        pendingCount = offlineQueue.count
        queueLock.unlock()
    }
    
    private func flushOfflineQueue() {
        queueLock.lock()
        let queue = offlineQueue
        offlineQueue.removeAll()
        pendingCount = 0
        queueLock.unlock()
        
        guard !queue.isEmpty else { return }
        
        Task {
            do {
                let deviceInfo = LocationManager.shared.getDeviceInfo()
                let locations = queue.map { point -> CLLocation in
                    CLLocation(
                        coordinate: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude),
                        altitude: point.altitude ?? 0,
                        horizontalAccuracy: point.horizontalAccuracy ?? -1,
                        verticalAccuracy: point.verticalAccuracy ?? -1,
                        course: point.course ?? -1,
                        speed: point.speed ?? -1,
                        timestamp: ISO8601DateFormatter().date(from: point.timestamp) ?? Date()
                    )
                }
                _ = try await sendLocations(locations, deviceInfo: deviceInfo)
                print("📦 Flushed \(queue.count) offline locations")
            } catch {
                print("⚠️ Failed to flush offline queue: \(error)")
            }
        }
    }
    
    // MARK: - Helpers
    
    private func getBatteryLevel() -> Float? {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        return level >= 0 ? level * 100 : nil
    }
}

// MARK: - Errors
enum NetworkError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case serverError(Int)
    case encodingError
    case decodingError
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "URL không hợp lệ"
        case .invalidResponse: return "Phản hồi từ server không hợp lệ"
        case .unauthorized: return "API Key không đúng"
        case .serverError(let code): return "Lỗi server: \(code)"
        case .encodingError: return "Lỗi mã hoá dữ liệu"
        case .decodingError: return "Lỗi giải mã dữ liệu"
        }
    }
}
