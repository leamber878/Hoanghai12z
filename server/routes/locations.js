// ===== API Routes: Xử lý dữ liệu location =====
const express = require('express');
const router = express.Router();
const { getDb } = require('../models/init');
const config = require('../config');

// POST /api/locations - Nhận location từ client
router.post('/', (req, res) => {
  try {
    const { locations, deviceInfo } = req.body;
    const db = getDb();

    if (!locations || !Array.isArray(locations) || locations.length === 0) {
      return res.status(400).json({ error: 'Thiếu dữ liệu locations' });
    }

    const deviceId = deviceInfo?.deviceId || req.headers['x-device-id'] || 'unknown';
    const results = [];

    // Upsert device info
    const upsertDevice = db.prepare(`
      INSERT INTO devices (device_id, device_name, device_model, os_version, app_version, last_seen)
      VALUES (?, ?, ?, ?, ?, datetime('now'))
      ON CONFLICT(device_id) DO UPDATE SET
        last_seen = datetime('now'),
        device_name = COALESCE(?, device_name),
        device_model = COALESCE(?, device_model),
        os_version = COALESCE(?, os_version),
        app_version = COALESCE(?, app_version)
    `);

    upsertDevice.run(
      deviceId,
      deviceInfo?.deviceName || null,
      deviceInfo?.deviceModel || null,
      deviceInfo?.osVersion || null,
      deviceInfo?.appVersion || null,
      deviceInfo?.deviceName || null,
      deviceInfo?.deviceModel || null,
      deviceInfo?.osVersion || null,
      deviceInfo?.appVersion || null,
    );

    // Batch insert locations
    const insertLocation = db.prepare(`
      INSERT INTO locations 
        (device_id, latitude, longitude, altitude, horizontal_accuracy, 
         vertical_accuracy, speed, course, timestamp, battery_level, is_moving)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `);

    // Lấy location cuối cùng để filter
    const lastRow = db.prepare(`
      SELECT latitude, longitude, timestamp FROM locations 
      WHERE device_id = ? ORDER BY timestamp DESC LIMIT 1
    `).get(deviceId);

    // Transaction: dùng exec với BEGIN/COMMIT
    db.exec('BEGIN');
    try {
      for (const loc of locations) {
        if (lastRow && shouldSkip(loc, lastRow)) continue;

        insertLocation.run(
          deviceId,
          loc.latitude,
          loc.longitude,
          loc.altitude ?? null,
          loc.horizontalAccuracy ?? null,
          loc.verticalAccuracy ?? null,
          loc.speed ?? null,
          loc.course ?? null,
          loc.timestamp || new Date().toISOString(),
          loc.batteryLevel !== undefined ? loc.batteryLevel : null,
          loc.isMoving ? 1 : 0
        );
        results.push({ 
          latitude: loc.latitude, 
          longitude: loc.longitude, 
          timestamp: loc.timestamp 
        });
      }
      db.exec('COMMIT');
    } catch (txErr) {
      db.exec('ROLLBACK');
      throw txErr;
    }

    // Emit realtime qua WebSocket
    const io = req.app.get('socketio');
    if (io) {
      io.to(deviceId).emit('location:update', {
        deviceId,
        deviceInfo: deviceInfo || {},
        locations: results
      });
      io.to('admin').emit('location:batch', {
        deviceId,
        count: results.length,
        latest: results[results.length - 1]
      });
    }

    res.json({
      success: true,
      received: locations.length,
      stored: results.length,
      skipped: locations.length - results.length
    });

  } catch (err) {
    console.error('❌ Lỗi xử lý location:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// GET /api/locations - Lấy danh sách locations (có filter)
router.get('/', (req, res) => {
  try {
    const db = getDb();
    const { 
      device_id, 
      from, to, 
      limit = 100, 
      offset = 0,
      page = 1,
      per_page = 100
    } = req.query;

    const actualLimit = Math.min(parseInt(limit) || parseInt(per_page) || 100, 1000);
    const actualOffset = parseInt(offset) || ((parseInt(page) - 1) * actualLimit);

    let whereClauses = [];
    const params = [];

    if (device_id) {
      whereClauses.push(`device_id = ?`);
      params.push(device_id);
    }
    if (from) {
      whereClauses.push(`timestamp >= ?`);
      params.push(from);
    }
    if (to) {
      whereClauses.push(`timestamp <= ?`);
      params.push(to);
    }

    const whereSQL = whereClauses.length ? `WHERE ${whereClauses.join(' AND ')}` : '';

    // Count
    const countRow = db.prepare(`SELECT COUNT(*) as total FROM locations ${whereSQL}`).get(...params);
    const total = countRow?.total || 0;

    // Data
    const rows = db.prepare(`
      SELECT * FROM locations ${whereSQL} 
      ORDER BY timestamp DESC LIMIT ? OFFSET ?
    `).all(...params, actualLimit, actualOffset);

    res.json({
      data: rows,
      pagination: {
        total,
        page: parseInt(page),
        perPage: actualLimit,
        totalPages: Math.ceil(total / actualLimit)
      }
    });

  } catch (err) {
    console.error('❌ Lỗi lấy locations:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// GET /api/locations/latest/:deviceId - Location mới nhất
router.get('/latest/:deviceId', (req, res) => {
  try {
    const db = getDb();
    const row = db.prepare(`
      SELECT l.*, d.device_name, d.device_model 
      FROM locations l
      JOIN devices d ON d.device_id = l.device_id
      WHERE l.device_id = ?
      ORDER BY l.timestamp DESC LIMIT 1
    `).get(req.params.deviceId);

    if (!row) {
      return res.status(404).json({ error: 'Không tìm thấy location cho device này' });
    }
    res.json(row);
  } catch (err) {
    console.error('❌ Lỗi lấy latest location:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ===== Helpers =====
function shouldSkip(loc, lastLoc) {
  if (!lastLoc) return false;

  const lastTime = new Date(lastLoc.timestamp).getTime();
  const curTime = new Date(loc.timestamp || Date.now()).getTime();
  const timeDiff = (curTime - lastTime) / 1000;

  if (timeDiff < config.minIntervalSeconds) return true;

  const dist = haversineDistance(
    lastLoc.latitude, lastLoc.longitude,
    loc.latitude, loc.longitude
  );

  if (dist < config.minDistanceMeters && timeDiff < 60) return true;

  return false;
}

function haversineDistance(lat1, lon1, lat2, lon2) {
  const R = 6371000;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a = Math.sin(dLat/2) * Math.sin(dLat/2) +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
    Math.sin(dLon/2) * Math.sin(dLon/2);
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
}

function toRad(deg) {
  return deg * Math.PI / 180;
}

module.exports = router;
