import SwiftUI

// ==========================================
//  ContentView - Giao diện chính
// ==========================================

struct ContentView: View {
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var networkManager: NetworkManager
    
    @State private var selectedTab: Tab = .map
    @State private var showSettings = false
    
    enum Tab: String, CaseIterable {
        case map = "🗺️ Bản đồ"
        case status = "📊 Trạng thái"
        case history = "📋 Lịch sử"
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                headerView
                
                // Content
                switch selectedTab {
                case .map:
                    MapView()
                case .status:
                    StatusView()
                case .history:
                    HistoryView()
                }
            }
            .background(Color(.systemGroupedBackground))
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }
    
    // MARK: - Header
    private var headerView: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Text("🛰️ GPS Tracker")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                // Connection indicator
                connectionIndicator
                
                // Settings button
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .padding(.leading, 8)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 4)
            
            // Tracking control bar
            trackingControlBar
                .padding(.horizontal)
                .padding(.bottom, 8)
            
            // Tab selector
            tabSelector
        }
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Connection Indicator
    private var connectionIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(connectionColor)
                .frame(width: 8, height: 8)
            Text(networkManager.connectionState.label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }
    
    private var connectionColor: Color {
        switch networkManager.connectionState {
        case .connected: return .green
        case .connecting: return .yellow
        case .disconnected: return .red
        case .error: return .orange
        }
    }
    
    // MARK: - Tracking Control
    private var trackingControlBar: some View {
        HStack {
            // Tracking state
            HStack(spacing: 6) {
                Image(systemName: trackingIcon)
                    .foregroundColor(trackingColor)
                Text(locationManager.trackingState.label)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Control buttons
            HStack(spacing: 12) {
                switch locationManager.trackingState {
                case .tracking:
                    trackingButton(icon: "pause.fill", color: .orange) {
                        locationManager.togglePause()
                    }
                    trackingButton(icon: "stop.fill", color: .red) {
                        locationManager.stopTracking()
                    }
                case .paused:
                    trackingButton(icon: "play.fill", color: .green) {
                        locationManager.togglePause()
                    }
                    trackingButton(icon: "stop.fill", color: .red) {
                        locationManager.stopTracking()
                    }
                case .stopped, .error:
                    trackingButton(icon: "play.fill", color: .green) {
                        locationManager.startTracking()
                    }
                }
            }
        }
    }
    
    private var trackingIcon: String {
        switch locationManager.trackingState {
        case .tracking: return "location.fill"
        case .paused: return "location.slash"
        case .stopped: return "location.slash.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
    
    private var trackingColor: Color {
        switch locationManager.trackingState {
        case .tracking: return .green
        case .paused: return .orange
        case .stopped: return .secondary
        case .error: return .red
        }
    }
    
    private func trackingButton(icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(color)
                .clipShape(Circle())
        }
    }
    
    // MARK: - Tab Selector
    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Text(tab.rawValue)
                            .font(.caption)
                            .fontWeight(selectedTab == tab ? .semibold : .regular)
                            .foregroundColor(selectedTab == tab ? .primary : .secondary)
                        
                        Rectangle()
                            .fill(selectedTab == tab ? Color.blue : Color.clear)
                            .frame(height: 2)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - History View (placeholder)
struct HistoryView: View {
    @EnvironmentObject var locationManager: LocationManager
    
    var body: some View {
        List {
            if locationManager.lastLocations.isEmpty {
                ContentUnavailableView(
                    "Chưa có dữ liệu",
                    systemImage: "location.slash",
                    description: Text("Bắt đầu theo dõi để thu thập dữ liệu vị trí")
                )
            } else {
                ForEach(locationManager.lastLocations.reversed(), id: \.timestamp) { location in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(location.coordinate.latitude, specifier: "%.6f"), \(location.coordinate.longitude, specifier: "%.6f")")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.primary)
                            
                            HStack(spacing: 12) {
                                if location.speed >= 0 {
                                    Label("\(location.speed * 3.6, specifier: "%.1f") km/h", systemImage: "speedometer")
                                        .font(.caption2)
                                }
                                Label("±\(location.horizontalAccuracy, specifier: "%.0f")m", systemImage: "scope")
                                    .font(.caption2)
                            }
                            .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Text(location.timestamp, style: .time)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.plain)
    }
}

// MARK: - Preview
#Preview {
    ContentView()
        .environmentObject(LocationManager.shared)
        .environmentObject(NetworkManager.shared)
}
