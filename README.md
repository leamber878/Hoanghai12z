# 🛰️ GPS Tracking System

Hệ thống theo dõi định vị thời gian thực gồm **Server** (Node.js) và **iOS Client** (SwiftUI).

## 📦 Cấu trúc

```
gps-tracking/
├── server/                      # Backend server
│   ├── index.js                 # Entry point (Express + Socket.IO)
│   ├── config.js                # Cấu hình
│   ├── .env                     # Biến môi trường
│   ├── package.json
│   ├── middleware/auth.js       # Xác thực API Key
│   ├── models/init.js           # Database SQLite
│   ├── routes/locations.js      # API endpoints
│   └── public/                  # Dashboard web
│       ├── index.html
│       ├── style.css
│       └── app.js
│
└── ios-client/                  # iOS app (SwiftUI)
    └── GPSTracker/
        ├── GPSTrackerApp.swift
        ├── ContentView.swift
        ├── Models/LocationData.swift
        ├── Managers/
        │   ├── LocationManager.swift   # CoreLocation
        │   └── NetworkManager.swift    # REST + WebSocket
        ├── Views/
        │   ├── MapView.swift
        │   ├── StatusView.swift
        │   └── SettingsView.swift
        └── Resources/Info.plist
```

## 🚀 Chạy Server

### Yêu cầu
- Node.js 18+
- npm

### Cài đặt & chạy

```bash
cd server
npm install
npm start
```

Server chạy tại: `http://localhost:3000`
Dashboard: `http://localhost:3000`

### API Endpoints

| Method | Path                | Mô tả                          | Auth     |
|--------|---------------------|--------------------------------|----------|
| GET    | `/api/health`       | Health check                   | ❌       |
| POST   | `/api/locations`    | Gửi dữ liệu location batch     | ✅ API Key |
| GET    | `/api/locations`    | Lấy danh sách locations        | ✅ API Key |
| GET    | `/api/locations/latest/:deviceId` | Location mới nhất | ✅ API Key |
| GET    | `/api/devices`      | Danh sách thiết bị             | ✅ API Key |

### Test bằng curl

```bash
# Health check
curl http://localhost:3000/api/health

# Gửi location test
curl -X POST http://localhost:3000/api/locations \
  -H "Content-Type: application/json" \
  -H "X-API-Key: gps-tracker-secret-key-2024" \
  -H "X-Device-ID: test-iphone-01" \
  -d '{
    "locations": [{
      "latitude": 10.8231,
      "longitude": 106.6297,
      "speed": 5.2,
      "horizontalAccuracy": 10,
      "timestamp": "2024-01-01T00:00:00Z"
    }],
    "deviceInfo": {
      "deviceId": "test-iphone-01",
      "deviceName": "Test iPhone",
      "deviceModel": "iPhone 15 Pro",
      "osVersion": "iOS 17.2",
      "appVersion": "1.0.0"
    }
  }'

# Lấy devices
curl "http://localhost:3000/api/devices?api_key=gps-tracker-secret-key-2024"
```

## 📱 iOS Client

### Yêu cầu
- macOS + Xcode 15+
- iOS 17+ deployment target
- Apple Developer account (cho background modes + build ký tên)

### Cách 1: Dùng XcodeGen (khuyên dùng)

```bash
# Cài XcodeGen (chỉ cần 1 lần)
brew install xcodegen

# Tạo .xcodeproj từ project.yml
cd ios-client
xcodegen generate

# Mở project
open GPSTracker.xcodeproj
```

Sau đó:
1. Điền **Team** trong Signing & Capabilities
2. Chọn thiết bị thật (simulator không hỗ trợ GPS thật)
3. Build & Run (⌘R)

### Cách 2: Dùng build script

```bash
cd ios-client

# Tạo project (nếu chưa có)
brew install xcodegen
xcodegen generate

# Build + chạy trên simulator
./build.sh

# Export IPA (ad-hoc)
./build.sh ipa

# Build Release + IPA
./build.sh release

# Xoá Build/
./build.sh clean
```

### Cách 3: GitHub Actions CI (auto build IPA)

Sau khi push code lên GitHub:
1. Vào repo → Actions → **Build IPA**
2. Click **Run workflow** → chọn **export_method** (development/ad-hoc/app-store)
3. Đợi build xong → download IPA từ artifacts

**Cấu hình GitHub secrets** (nếu cần signing manual):
- `IOS_TEAM_ID` — Apple Team ID
- `IOS_CERTIFICATE_DATA` — base64 của .p12
- `IOS_CERTIFICATE_PASSWORD` — passphrase
- `IOS_PROVISIONING_PROFILE` — base64 của .mobileprovision

### Cấu hình server URL
Vào **Settings** tab trong app → nhập server URL và API Key.

Nếu chạy server local:
- Cùng WiFi: `http://<IP-máy>:3000` (vd: `http://192.168.1.100:3000`)
- Local network: cần tắt firewall port 3000
- Cloud/VPS: URL của server

## 🔐 Security

- **API Key** bảo vệ tất cả API endpoints
- iOS yêu cầu quyền **Always Location Access** cho background tracking
- Dữ liệu location có thể encrypted qua HTTPS nếu deploy với reverse proxy (Nginx/Caddy)

## 🏗 Deploy Production (Gợi ý)

```bash
# Dùng PM2 để chạy persistent
npm install -g pm2
pm2 start index.js --name gps-tracker
pm2 save
pm2 startup

# Nginx reverse proxy + SSL
server {
    listen 443 ssl;
    server_name tracking.yourdomain.com;
    
    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
    }
}
```

## 📊 Features

### Server
- ✅ REST API nhận location
- ✅ WebSocket realtime
- ✅ SQLite database (WAL mode)
- ✅ Dashboard web với bản đồ
- ✅ Device management
- ✅ Filter duplicate locations
- ✅ Batch insert performance

### iOS App
- ✅ CoreLocation foreground + background
- ✅ WebSocket realtime gửi location
- ✅ REST API fallback
- ✅ Bản đồ với path tracking
- ✅ Thống kê tốc độ, quãng đường
- ✅ Offline queue (gửi lại khi có mạng)
- ✅ Tự động reconnect
- ✅ Theo dõi pin, độ chính xác

## 📝 License

MIT
