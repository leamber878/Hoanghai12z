import SwiftUI

// ==========================================
//  StatusView - Trạng thái theo dõi
// ==========================================

struct StatusView: View {
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var networkManager: NetworkManager
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // GPS Status Card
                gpsStatusCard
                
                // Connection Card
                connectionCard
                
                // Stats Grid
                statsGrid
                
                // Device Info
                deviceInfoCard
            }
            .padding()
        }
    }
    
    // MARK: - GPS Status
    private var gpsStatusCard: some View {
        CardView(icon: "location.fill", title: "GPS", color: .blue) {
            VStack(spacing: 12) {
                if let location = locationManager.currentLocation {
                    // Coordinates lớn
                    VStack(spacing: 4) {
                        Text("\(location.coordinate.latitude, specifier: "%.6f")")
                            .font(.system(.title3, design: .monospaced, weight: .medium))
                            .foregroundColor(.primary)
                        + Text(" , ")
                            .foregroundColor(.secondary)
                        + Text("\(location.coordinate.longitude, specifier: "%.6f")")
                            .font(.system(.title3, design: .monospaced, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    
                    Divider()
                    
                    InfoRow(label: "Độ chính xác", value: "±\(String(format: "%.0f", location.horizontalAccuracy))m", icon: "scope")
                    if location.altitude != 0 {
                        InfoRow(label: "Độ cao", value: String(format: "%.0f m", location.altitude), icon: "water.levels")
                    }
                    InfoRow(label: "Hướng", value: location.course >= 0 ? "\(String(format: "%.0f", location.course))°" : "---", icon: "arrow.up.right")
                } else {
                    ContentUnavailableView(
                        "Đang chờ tín hiệu GPS...",
                        systemImage: "antenna.radiowaves.left.and.right",
                        description: Text("Hãy đảm bảo bạn đang ở ngoài trời")
                    )
                }
                
                // Tracking info
                if case .tracking = locationManager.trackingState {
                    Divider()
                    HStack {
                        Label("Đã theo dõi", systemImage: "clock")
                        Spacer()
                        Text(formattedDuration)
                            .fontWeight(.medium)
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var formattedDuration: String {
        guard let first = locationManager.lastLocations.first else { return "00:00:00"
        }
        let duration = Date().timeIntervalSince(first.timestamp)
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
    
    // MARK: - Connection Status
    private var connectionCard: some View {
        CardView(icon: "antenna.radiowaves.left.and.right", title: "Kết nối", color: .green) {
            VStack(spacing: 12) {
                HStack {
                    Label(networkManager.connectionState.label, systemImage: connectionIcon)
                        .foregroundColor(connectionColor)
                    Spacer()
                }
                
                Divider()
                
                InfoRow(label: "Server", value: networkManager.serverURL, icon: "server.rack")
                InfoRow(label: "Đã gửi", value: "\(networkManager.totalSent) location", icon: "arrow.up.circle")
                InfoRow(label: "Chờ gửi", value: "\(networkManager.pendingCount)", icon: "clock.badge")
                if let lastSync = networkManager.lastSyncTime {
                    InfoRow(label: "Đồng bộ", value: lastSync.formatted(date: .abbreviated, time: .shortened), icon: "arrow.triangle.2.circlepath")
                }
            }
        }
    }
    
    private var connectionIcon: String {
        switch networkManager.connectionState {
        case .connected: return "checkmark.icloud.fill"
        case .connecting: return "arrow.triangle.2.circlepath"
        case .disconnected: return "xmark.icloud.fill"
        case .error: return "exclamationmark.icloud.fill"
        }
    }
    
    private var connectionColor: Color {
        switch networkManager.connectionState {
        case .connected: return .green
        case .connecting: return .yellow
        case .disconnected: return .red
        case .error: return .orange
        }
    }
    
    // MARK: - Stats Grid
    private var statsGrid: some View {
        CardView(icon: "chart.bar.fill", title: "Thống kê", color: .purple) {
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                StatCell(
                    value: String(format: "%.2f", locationManager.distanceTraveled / 1000),
                    unit: "km",
                    label: "Quãng đường",
                    icon: "arrow.triangle.swap"
                )
                
                StatCell(
                    value: String(format: "%.0f", locationManager.averageSpeed),
                    unit: "km/h",
                    label: "Tốc độ TB",
                    icon: "speedometer"
                )
                
                StatCell(
                    value: String(format: "%.0f", locationManager.maxSpeed),
                    unit: "km/h",
                    label: "Tốc độ max",
                    icon: "bolt.fill"
                )
                
                StatCell(
                    value: "\(locationManager.totalLocations)",
                    unit: "điểm",
                    label: "GPS",
                    icon: "point.topleft.down.curvedto.point.bottomright.up"
                )
                
                StatCell(
                    value: "\(locationManager.lastLocations.count)",
                    unit: "đã lưu",
                    label: "Trong bộ nhớ",
                    icon: "memorychip"
                )
                
                let battery = getBattery()
                StatCell(
                    value: battery >= 0 ? String(format: "%.0f", battery) : "---",
                    unit: "%",
                    label: "Pin",
                    icon: "battery.\(battery > 50 ? "75" : battery > 20 ? "25" : "0")"
                )
            }
        }
    }
    
    private func getBattery() -> Float {
        UIDevice.current.isBatteryMonitoringEnabled = true
        return UIDevice.current.batteryLevel >= 0 ? UIDevice.current.batteryLevel * 100 : -1
    }
    
    // MARK: - Device Info
    private var deviceInfoCard: some View {
        CardView(icon: "iphone.gen3", title: "Thiết bị", color: .gray) {
            let info = locationManager.getDeviceInfo()
            VStack(spacing: 12) {
                InfoRow(label: "Tên", value: info.deviceName, icon: "tag")
                InfoRow(label: "Model", value: info.deviceModel, icon: "ipad.and.iphone")
                InfoRow(label: "OS", value: info.osVersion, icon: "gear")
                InfoRow(label: "Device ID", value: String(info.deviceId.prefix(16)) + "...", icon: "qrcode")
                InfoRow(label: "Version", value: info.appVersion, icon: "doc.text")
            }
        }
    }
}

// MARK: - Reusable Components

struct CardView<Content: View>: View {
    let icon: String
    let title: String
    let color: Color
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.headline)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            
            Divider()
                .padding(.horizontal)
            
            // Content
            content
                .padding()
        }
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 16)
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .foregroundColor(.primary)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }
}

struct StatCell: View {
    let value: String
    let unit: String
    let label: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(unit)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Preview
#Preview {
    StatusView()
        .environmentObject(LocationManager.shared)
        .environmentObject(NetworkManager.shared)
}
