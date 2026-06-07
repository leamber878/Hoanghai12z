import SwiftUI
import MapKit

// ==========================================
//  MapView - Bản đồ hiển thị vị trí
// ==========================================

struct MapView: View {
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var networkManager: NetworkManager
    
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 10.8231, longitude: 106.6297),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    @State private var showUserLocation = true
    @State private var selectedAnnotation: LocationAnnotation?
    
    var body: some View {
        ZStack {
            // Map
            Map(
                coordinateRegion: $region,
                showsUserLocation: showUserLocation,
                annotationItems: locationAnnotations
            ) { annotation in
                MapAnnotation(coordinate: annotation.coordinate) {
                    LocationAnnotationView(annotation: annotation, isLatest: annotation == locationAnnotations.last)
                        .onTapGesture {
                            selectedAnnotation = annotation
                        }
                }
            }
            .edgesIgnoringSafeArea(.bottom)
            .mapControlVisibility(.visible)
            
            // Info overlay
            VStack {
                Spacer()
                
                // Stats bar
                if case .tracking = locationManager.trackingState {
                    statsBar
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }
            }
        }
        .onChange(of: locationManager.currentLocation) { location in
            if let location = location, showUserLocation {
                withAnimation {
                    region.center = location.coordinate
                }
            }
        }
        .sheet(item: $selectedAnnotation) { annotation in
            LocationDetailView(annotation: annotation)
                .presentationDetents([.height(200)])
        }
    }
    
    // MARK: - Location Annotations
    private var locationAnnotations: [LocationAnnotation] {
        locationManager.lastLocations.enumerated().map { index, location in
            LocationAnnotation(
                id: index,
                coordinate: location.coordinate,
                timestamp: location.timestamp,
                speed: location.speed,
                accuracy: location.horizontalAccuracy,
                altitude: location.altitude,
                index: index
            )
        }
    }
    
    // MARK: - Stats Bar
    private var statsBar: some View {
        HStack(spacing: 20) {
            StatItem(
                icon: "arrow.triangle.swap",
                value: String(format: "%.1f km", locationManager.distanceTraveled / 1000),
                label: "Quãng đường"
            )
            
            Divider()
                .frame(height: 30)
            
            StatItem(
                icon: "speedometer",
                value: String(format: "%.0f km/h", locationManager.averageSpeed),
                label: "Tốc độ TB"
            )
            
            Divider()
                .frame(height: 30)
            
            StatItem(
                icon: "point.topleft.down.curvedto.point.bottomright.up",
                value: "\(locationManager.totalLocations)",
                label: "Điểm GPS"
            )
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 20)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .shadow(radius: 4)
    }
}

// MARK: - Models
struct LocationAnnotation: Identifiable, Equatable {
    let id: Int
    let coordinate: CLLocationCoordinate2D
    let timestamp: Date
    let speed: CLLocationSpeed
    let accuracy: CLLocationAccuracy
    let altitude: CLLocationDistance
    let index: Int
    
    static func == (lhs: LocationAnnotation, rhs: LocationAnnotation) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Annotation View
struct LocationAnnotationView: View {
    let annotation: LocationAnnotation
    let isLatest: Bool
    
    var body: some View {
        VStack(spacing: 2) {
            if isLatest {
                // Pulse animation cho điểm mới nhất
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Circle()
                            .stroke(Color.blue, lineWidth: 2)
                    )
                    .overlay(
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 12, height: 12)
                    )
            } else {
                Circle()
                    .fill(Color.blue.opacity(0.6))
                    .frame(width: 8, height: 8)
            }
        }
    }
}

// MARK: - Location Detail Sheet
struct LocationDetailView: View {
    let annotation: LocationAnnotation
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("📍 Chi tiết vị trí")
                .font(.headline)
            
            Group {
                LabeledContent("Kinh độ", value: String(format: "%.6f", annotation.coordinate.longitude))
                LabeledContent("Vĩ độ", value: String(format: "%.6f", annotation.coordinate.latitude))
                if annotation.altitude != 0 {
                    LabeledContent("Độ cao", value: String(format: "%.0f m", annotation.altitude))
                }
                if annotation.speed >= 0 {
                    LabeledContent("Tốc độ", value: String(format: "%.1f km/h", annotation.speed * 3.6))
                }
                LabeledContent("Độ chính xác", value: String(format: "±%.0f m", annotation.accuracy))
                LabeledContent("Thời gian", value: annotation.timestamp.formatted(date: .omitted, time: .standard))
            }
            .font(.subheadline)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Stat Item Component
struct StatItem: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Preview
#Preview {
    MapView()
        .environmentObject(LocationManager.shared)
        .environmentObject(NetworkManager.shared)
}
