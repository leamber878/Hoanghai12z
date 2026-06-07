// ===== GPS Tracking Dashboard =====
const API_BASE = window.location.origin;
const socket = io(API_BASE, { transports: ['websocket', 'polling'] });

// State
const state = {
  map: null,
  markers: {},       // deviceId -> marker
  polylines: {},     // deviceId -> polyline
  paths: {},         // deviceId -> [{lat, lng}]
  devices: [],
  locations: [],
};

// === Khởi tạo Map ===
function initMap() {
  state.map = L.map('map', {
    center: [10.8231, 106.6297],  // Mặc định: TP.HCM
    zoom: 13,
    zoomControl: true,
    attributionControl: false,
  });

  // Dark tile layer
  L.tileLayer('https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png', {
    maxZoom: 19,
  }).addTo(state.map);

  // Fit to markers when we have data
  state.map.on('layeradd', () => {
    const group = new L.FeatureGroup(Object.values(state.markers));
    if (group.getLayers().length > 0) {
      state.map.fitBounds(group.getBounds().pad(0.1));
    }
  });
}

// === Devices List ===
async function loadDevices() {
  try {
    const apiKey = document.getElementById('api-key').value;
    const res = await fetch(`${API_BASE}/api/devices?api_key=${apiKey}`);
    const devices = await res.json();
    state.devices = devices;

    document.getElementById('device-count').textContent = `📱 ${devices.length} devices`;

    const list = document.getElementById('devices-list');
    if (devices.length === 0) {
      list.innerHTML = '<div class="empty-state">Chưa có thiết bị nào kết nối</div>';
      return;
    }

    // Tính tổng locations
    const totalLocations = devices.reduce((sum, d) => sum + (d.total_locations || 0), 0);
    document.getElementById('location-count').textContent = `📍 ${totalLocations.toLocaleString()} locations`;

    list.innerHTML = devices.map(d => {
      const isOnline = isRecentlyOnline(d.last_seen);
      return `
        <div class="device-item" onclick="focusDevice('${d.device_id}')">
          <div>
            <div class="name">${d.device_name || d.device_id}</div>
            <div class="meta">${d.device_model || ''} • ${d.total_locations || 0} điểm</div>
          </div>
          <div class="status ${isOnline ? 'status-online' : 'status-offline'}"></div>
        </div>
      `;
    }).join('');

    // Load locations cho devices online
    for (const d of devices) {
      if (isRecentlyOnline(d.last_seen)) {
        loadDeviceLocations(d.device_id);
      }
    }
  } catch (err) {
    console.error('Error loading devices:', err);
  }
}

function isRecentlyOnline(lastSeen) {
  if (!lastSeen) return false;
  const diff = Date.now() - new Date(lastSeen).getTime();
  return diff < 5 * 60 * 1000; // 5 phút
}

// === Device Locations ===
async function loadDeviceLocations(deviceId) {
  try {
    const apiKey = document.getElementById('api-key').value;
    const res = await fetch(
      `${API_BASE}/api/locations?device_id=${deviceId}&limit=200&api_key=${apiKey}`
    );
    const data = await res.json();
    const locations = data.data || [];

    if (locations.length === 0) return;

    // Vẽ path
    const pathPoints = locations
      .reverse()
      .map(l => [l.latitude, l.longitude]);

    state.paths[deviceId] = pathPoints;

    // Vẽ polyline
    if (state.polylines[deviceId]) {
      state.map.removeLayer(state.polylines[deviceId]);
    }
    state.polylines[deviceId] = L.polyline(pathPoints, {
      color: getColorForDevice(deviceId),
      weight: 3,
      opacity: 0.7,
    }).addTo(state.map);

    // Marker cho điểm mới nhất
    const latest = pathPoints[pathPoints.length - 1];
    updateMarker(deviceId, latest[0], latest[1], locations[locations.length - 1]);
  } catch (err) {
    console.error(`Error loading locations for ${deviceId}:`, err);
  }
}

// === Marker Management ===
function updateMarker(deviceId, lat, lng, data = {}) {
  const color = getColorForDevice(deviceId);

  if (state.markers[deviceId]) {
    state.markers[deviceId].setLatLng([lat, lng]);
    state.markers[deviceId].setPopupContent(getPopupContent(deviceId, data));
  } else {
    const marker = L.circleMarker([lat, lng], {
      radius: 8,
      fillColor: color,
      color: '#fff',
      weight: 2,
      opacity: 1,
      fillOpacity: 0.9,
    }).addTo(state.map);

    marker.bindPopup(getPopupContent(deviceId, data));
    state.markers[deviceId] = marker;
  }

  // Thêm vào path
  if (state.paths[deviceId]) {
    state.paths[deviceId].push([lat, lng]);
    if (state.polylines[deviceId]) {
      state.polylines[deviceId].setLatLngs(state.paths[deviceId]);
    }
  }
}

function getPopupContent(deviceId, data) {
  return `
    <div style="font-size:13px; min-width:180px;">
      <strong>📱 ${data.device_name || deviceId}</strong><br>
      🗺️ ${data.latitude?.toFixed(6)}, ${data.longitude?.toFixed(6)}<br>
      ${data.speed !== undefined && data.speed !== null ? `🚗 ${(data.speed * 3.6).toFixed(1)} km/h<br>` : ''}
      ${data.altitude ? `🏔️ ${data.altitude.toFixed(0)}m<br>` : ''}
      ${data.battery_level !== null ? `🔋 ${data.battery_level}%<br>` : ''}
      ⏱️ ${data.timestamp ? new Date(data.timestamp).toLocaleString('vi-VN') : ''}
    </div>
  `;
}

// === WebSocket Realtime ===
socket.on('connect', () => {
  console.log('✅ WebSocket connected');
  document.getElementById('status-badge').textContent = '🟢 Online';
  document.getElementById('status-badge').className = 'badge badge-online';

  // Register as admin
  const apiKey = document.getElementById('api-key').value;
  socket.emit('register:admin', apiKey);
});

socket.on('disconnect', () => {
  console.log('❌ WebSocket disconnected');
  document.getElementById('status-badge').textContent = '🔴 Offline';
  document.getElementById('status-badge').className = 'badge badge-offline';
});

socket.on('location:realtime', (data) => {
  if (data?.latitude && data?.longitude) {
    updateMarker(data.deviceId, data.latitude, data.longitude, data);
    addLogEntry(data);
  }
});

socket.on('location:batch', (data) => {
  addLogEntry({ ...data.latest, deviceId: data.deviceId, batch: true });
});

// === Realtime Log ===
function addLogEntry(data) {
  const log = document.getElementById('realtime-log');
  const time = new Date().toLocaleTimeString('vi-VN');
  const speed = data.speed ? (data.speed * 3.6).toFixed(1) : '?';

  // Xoá empty state
  const empty = log.querySelector('.empty-state');
  if (empty) empty.remove();

  const entry = document.createElement('div');
  entry.className = 'log-entry';
  entry.innerHTML = `
    <span class="time">[${time}]</span>
    <strong>${data.deviceId?.slice(0, 8) || '???'}</strong>
    → <span class="coord">${(data.latitude || 0).toFixed(4)}, ${(data.longitude || 0).toFixed(4)}</span>
    ${data.batch ? '📦' : ''}
    <span class="speed">${speed}km/h</span>
  `;
  log.insertBefore(entry, log.firstChild);

  // Giới hạn log entries
  while (log.children.length > 100) {
    log.removeChild(log.lastChild);
  }
}

// === Helpers ===
function focusDevice(deviceId) {
  const marker = state.markers[deviceId];
  if (marker) {
    state.map.setView(marker.getLatLng(), 15);
    marker.openPopup();
  }
}

const DEVICE_COLORS = [
  '#00d4ff', '#00ff88', '#ff6b6b', '#ffd93d', '#6c5ce7',
  '#fd79a8', '#00cec9', '#e17055', '#0984e3', '#fdcb6e',
];

function getColorForDevice(deviceId) {
  let hash = 0;
  for (let i = 0; i < (deviceId || '').length; i++) {
    hash = deviceId.charCodeAt(i) + ((hash << 5) - hash);
  }
  return DEVICE_COLORS[Math.abs(hash) % DEVICE_COLORS.length];
}

// === Init ===
document.addEventListener('DOMContentLoaded', () => {
  document.getElementById('server-url').value = API_BASE;
  initMap();
  loadDevices();

  // Refresh devices mỗi 10s
  setInterval(loadDevices, 10000);

  // API Key change handler
  document.getElementById('api-key').addEventListener('change', () => {
    loadDevices();
  });
});
