// ===== Cấu hình server GPS Tracking =====
require('dotenv').config();

module.exports = {
  // Cổng server
  port: process.env.PORT || 3000,

  // API key để client xác thực khi gửi dữ liệu
  apiKey: process.env.API_KEY || 'gps-tracker-secret-key-2024',

  // WebSocket config
  ws: {
    pingInterval: 30000,    // 30s ping client
    pingTimeout: 10000,     // timeout 10s
  },

  // Database config
  db: {
    path: process.env.DB_PATH || './data/gps_tracking.db',
  },

  // Khoảng cách tối thiểu (mét) giữa 2 lần ghi location
  // Để tránh ghi quá nhiều khi device đứng yên
  minDistanceMeters: parseInt(process.env.MIN_DISTANCE || '10'),

  // Thời gian tối thiểu (giây) giữa 2 lần ghi location
  minIntervalSeconds: parseInt(process.env.MIN_INTERVAL || '5'),
};
