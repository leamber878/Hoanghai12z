// ==========================================
//  🛰️ GPS Tracking Server
//  Nhận dữ liệu định vị từ iOS client
//  Node.js + Express + Socket.IO + SQLite
// ==========================================

const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const cors = require('cors');
const path = require('path');
const config = require('./config');
const { getDb } = require('./models/init');
const { requireApiKey } = require('./middleware/auth');
const locationsRouter = require('./routes/locations');

// === Khởi tạo app ===
const app = express();
const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: '*',
    methods: ['GET', 'POST'],
  },
  pingInterval: config.ws.pingInterval,
  pingTimeout: config.ws.pingTimeout,
});

// === Middleware ===
app.use(cors());
app.use(express.json({ limit: '10mb' }));
app.use(express.static(path.join(__dirname, 'public')));
app.use(express.urlencoded({ extended: true }));

// Request logging
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    const duration = Date.now() - start;
    if (req.path.startsWith('/api')) {
      console.log(
        `[${new Date().toISOString()}] ${req.method} ${req.path} → ${res.statusCode} (${duration}ms)`
      );
    }
  });
  next();
});

// === Routes ===
// Health check (không cần auth) — đặt TRƯỚC auth middleware
app.get('/api/health', (req, res) => {
  const db = getDb();
  const locCount = db.prepare('SELECT COUNT(*) as count FROM locations').get();
  const deviceCount = db.prepare('SELECT COUNT(*) as count FROM devices').get();
  res.json({
    status: '🟢 online',
    uptime: process.uptime(),
    locations: locCount?.count || 0,
    devices: deviceCount?.count || 0,
    version: '1.0.0',
  });
});

// API (yêu cầu API key)
app.use('/api/locations', requireApiKey, locationsRouter);
app.use('/api/locations/latest', requireApiKey, locationsRouter);

// GET /api/devices — handler riêng (ko qua locationsRouter để tránh route conflict)
app.get('/api/devices', requireApiKey, (req, res) => {
  try {
    const db = getDb();
    const devices = db.prepare(`
      SELECT d.*, 
        (SELECT COUNT(*) FROM locations WHERE device_id = d.device_id) as total_locations,
        (SELECT MAX(timestamp) FROM locations WHERE device_id = d.device_id) as last_location_time
      FROM devices d
      ORDER BY d.last_seen DESC
    `).all();
    res.json(devices);
  } catch (err) {
    console.error('❌ Lỗi lấy devices:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Dashboard
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// === WebSocket ===
io.on('connection', (socket) => {
  console.log(`🔌 WebSocket connected: ${socket.id}`);

  // Client đăng ký device của nó
  socket.on('register:device', (deviceId) => {
    if (deviceId) {
      socket.join(deviceId);
      socket.deviceId = deviceId;
      console.log(`📱 Device registered: ${deviceId}`);
      socket.emit('registered', { deviceId, success: true });
    }
  });

  // Admin theo dõi tất cả devices
  socket.on('register:admin', (secret) => {
    if (secret === config.apiKey) {
      socket.join('admin');
      console.log(`🛡️ Admin joined: ${socket.id}`);
      socket.emit('admin:registered', { success: true });
    }
  });

  // Client gửi location realtime qua WebSocket
  socket.on('location:send', (data) => {
    const deviceId = data?.deviceId || socket.deviceId || 'unknown';
    // Forward to admin room
    socket.to('admin').emit('location:realtime', {
      deviceId,
      latitude: data?.latitude,
      longitude: data?.longitude,
      speed: data?.speed,
      batteryLevel: data?.batteryLevel,
      timestamp: data?.timestamp || new Date().toISOString(),
    });
  });

  socket.on('disconnect', () => {
    console.log(`🔌 WebSocket disconnected: ${socket.id} ${socket.deviceId || ''}`);
  });
});

// Gắn io vào app để dùng trong routes
app.set('socketio', io);

// === Error handling ===
app.use((err, req, res, next) => {
  console.error('❌ Unhandled error:', err);
  res.status(500).json({ error: 'Internal server error', message: err.message });
});

// === Start server ===
server.listen(config.port, '0.0.0.0', () => {
  const db = getDb();
  console.log(`
╔══════════════════════════════════════╗
║   🛰️  GPS Tracking Server            ║
║   📡 Online on port ${config.port.toString().padEnd(18)}║
║   📊 Dashboard: http://0.0.0.0:${config.port}  ║
║   🏓 API Health: /api/health         ║
╚══════════════════════════════════════╝
  `);
});
