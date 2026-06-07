import SwiftUI

// ==========================================
//  SettingsView - Cài đặt ứng dụng
// ==========================================

struct SettingsView: View {
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var networkManager: NetworkManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var serverURL: String = ""
    @State private var apiKey: String = ""
    @State private var showHealthCheck = false
    @State private var healthStatus: String = ""
    
    var body: some View {
        NavigationStack {
            Form {
                // MARK: Server Settings
                Section("🖥️ Server") {
                    HStack {
                        Image(systemName: "server.rack")
                            .foregroundColor(.secondary)
                        TextField("Server URL", text: $serverURL)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .font(.system(.body, design: .monospaced))
                    }
                    
                    HStack {
                        Image(systemName: "key.fill")
                            .foregroundColor(.secondary)
                        SecureField("API Key", text: $apiKey)
                            .font(.system(.body, design: .monospaced))
                    }
                    
                    // Test connection
                    Button {
                        testConnection()
                    } label: {
                        HStack {
                            Image(systemName: "bolt.fill")
                                .foregroundColor(.yellow)
                            Text("Kiểm tra kết nối")
                        }
                    }
                    
                    if !healthStatus.isEmpty {
                        Label(healthStatus, systemImage: healthIcon)
                            .font(.caption)
                            .foregroundColor(healthColor)
                    }
                }
                
                // MARK: Tracking Settings
                Section("📍 Tracking") {
                    // Auto-start
                    Toggle(isOn: $autoStartTracking) {
                        Label("Tự động theo dõi", systemImage: "play.circle")
                    }
                    
                    // Background tracking
                    Toggle(isOn: $backgroundTracking) {
                        Label("Theo dõi nền", systemImage: "square.and.arrow.down")
                    }
                    
                    // Interval
                    VStack(spacing: 8) {
                        HStack {
                            Label("Khoảng cách tối thiểu", systemImage: "ruler")
                            Spacer()
                            Text("\(Int(minDistance))m")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $minDistance, in: 5...100, step: 5)
                    }
                    
                    VStack(spacing: 8) {
                        HStack {
                            Label("Thời gian tối thiểu", systemImage: "timer")
                            Spacer()
                            Text("\(Int(minInterval))s")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $minInterval, in: 1...60, step: 1)
                    }
                }
                
                // MARK: Data Management
                Section("💾 Dữ liệu") {
                    Button(role: .destructive) {
                        locationManager.resetTrackingData()
                    } label: {
                        Label("Xoá dữ liệu tracking", systemImage: "trash")
                    }
                    
                    Button {
                        networkManager.disconnect()
                        networkManager.connect()
                    } label: {
                        Label("Kết nối lại", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                
                // MARK: Info
                Section("ℹ️ Thông tin") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    Link(destination: URL(string: "https://github.com/your-repo/gps-tracker")!) {
                        Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                }
            }
            .navigationTitle("Cài đặt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") {
                        saveSettings()
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadSettings()
            }
        }
    }
    
    // MARK: - Settings State
    @AppStorage("serverURL") private var storedServerURL = "http://localhost:3000"
    @AppStorage("apiKey") private var storedApiKey = "gps-tracker-secret-key-2024"
    @AppStorage("autoStartTracking") private var autoStartTracking = false
    @AppStorage("backgroundTracking") private var backgroundTracking = true
    @AppStorage("minDistance") private var minDistance: Double = 10
    @AppStorage("minInterval") private var minInterval: Double = 5
    
    private func loadSettings() {
        serverURL = storedServerURL
        apiKey = storedApiKey
    }
    
    private func saveSettings() {
        storedServerURL = serverURL
        storedApiKey = apiKey
        networkManager.serverURL = serverURL
        networkManager.apiKey = apiKey
    }
    
    // MARK: - Test Connection
    private func testConnection() {
        saveSettings()
        healthStatus = "Đang kiểm tra..."
        
        Task {
            if let health = await networkManager.checkHealth() {
                await MainActor.run {
                    healthStatus = "✅ Server online — \(health.locations) locations, \(health.devices) devices"
                    networkManager.connect()
                }
            } else {
                await MainActor.run {
                    healthStatus = "❌ Không thể kết nối tới server"
                }
            }
        }
    }
    
    private var healthIcon: String {
        healthStatus.hasPrefix("✅") ? "checkmark.circle.fill" : "xmark.circle.fill"
    }
    
    private var healthColor: Color {
        healthStatus.hasPrefix("✅") ? .green : .red
    }
}

// MARK: - Preview
#Preview {
    SettingsView()
        .environmentObject(LocationManager.shared)
        .environmentObject(NetworkManager.shared)
}
