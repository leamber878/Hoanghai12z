import SwiftUI

// ==========================================
//  🛰️ GPS Tracker - iOS App
//  Theo dõi định vị realtime
// ==========================================

@main
struct GPSTrackerApp: App {
    @StateObject private var locationManager = LocationManager.shared
    @StateObject private var networkManager = NetworkManager.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(locationManager)
                .environmentObject(networkManager)
                .onAppear {
                    setupApp()
                }
        }
    }
    
    private func setupApp() {
        // Yêu cầu quyền location ngay khi app mở
        locationManager.requestPermission()
        
        // Kết nối WebSocket tới server
        networkManager.connect()
        
        // Khi có location mới, gửi lên server
        locationManager.onNewLocation = { location in
            // Gửi realtime qua WebSocket
            networkManager.sendLocationRealtime(location)
        }
    }
}
