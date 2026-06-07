// ===== Authentication Middleware =====
const config = require('../config');

// API Key validation
function requireApiKey(req, res, next) {
  const apiKey = req.headers['x-api-key'] || req.query.api_key;

  if (!apiKey) {
    return res.status(401).json({ error: 'Thiếu API key. Gửi trong header X-API-Key' });
  }

  if (apiKey !== config.apiKey) {
    return res.status(403).json({ error: 'API key không hợp lệ' });
  }

  next();
}

// Lấy device ID từ request
function extractDeviceId(req, res, next) {
  const deviceId = req.headers['x-device-id'] || 
                   req.body?.deviceInfo?.deviceId || 
                   req.query.device_id;
  if (deviceId) {
    req.deviceId = deviceId;
  }
  next();
}

module.exports = { requireApiKey, extractDeviceId };
