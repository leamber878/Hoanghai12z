// ===== Khởi tạo Database SQLite (Node 22+ built-in) =====
const { DatabaseSync } = require('node:sqlite');
const path = require('path');
const fs = require('fs');
const config = require('../config');

// Tạo thư mục data nếu chưa tồn tại
const dataDir = path.dirname(config.db.path);
if (!fs.existsSync(dataDir)) {
  fs.mkdirSync(dataDir, { recursive: true });
}

let db;

function getDb() {
  if (!db) {
    db = new DatabaseSync(config.db.path);
    db.exec('PRAGMA journal_mode = WAL');
    db.exec('PRAGMA foreign_keys = ON');
    initTables();
  }
  return db;
}

function initTables() {
  db.exec(`
    -- Devices: thông tin thiết bị
    CREATE TABLE IF NOT EXISTS devices (
      device_id TEXT PRIMARY KEY,
      device_name TEXT,
      device_model TEXT,
      os_version TEXT,
      app_version TEXT,
      first_seen DATETIME DEFAULT (datetime('now')),
      last_seen DATETIME DEFAULT (datetime('now'))
    );

    -- Users: tài khoản người dùng (optional)
    CREATE TABLE IF NOT EXISTS users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      username TEXT UNIQUE NOT NULL,
      display_name TEXT,
      created_at DATETIME DEFAULT (datetime('now'))
    );

    -- Locations: dữ liệu định vị
    CREATE TABLE IF NOT EXISTS locations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      device_id TEXT NOT NULL,
      user_id INTEGER,
      latitude REAL NOT NULL,
      longitude REAL NOT NULL,
      altitude REAL,
      horizontal_accuracy REAL,
      vertical_accuracy REAL,
      speed REAL,
      course REAL,
      timestamp DATETIME NOT NULL,
      battery_level REAL,
      is_moving INTEGER DEFAULT 0,
      created_at DATETIME DEFAULT (datetime('now')),
      FOREIGN KEY (device_id) REFERENCES devices(device_id),
      FOREIGN KEY (user_id) REFERENCES users(id)
    );

    -- Indexes
    CREATE INDEX IF NOT EXISTS idx_locations_device_time 
      ON locations(device_id, timestamp DESC);
    CREATE INDEX IF NOT EXISTS idx_locations_timestamp 
      ON locations(timestamp DESC);
    CREATE INDEX IF NOT EXISTS idx_devices_last_seen 
      ON devices(last_seen DESC);

    -- Tracking Sessions
    CREATE TABLE IF NOT EXISTS tracking_sessions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      device_id TEXT NOT NULL,
      user_id INTEGER,
      session_name TEXT,
      started_at DATETIME NOT NULL,
      ended_at DATETIME,
      distance_traveled REAL DEFAULT 0,
      is_active INTEGER DEFAULT 1,
      FOREIGN KEY (device_id) REFERENCES devices(device_id)
    );
  `);
}

module.exports = { getDb };
