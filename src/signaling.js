require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const { WebSocketServer } = require('ws');
const jwt = require('jsonwebtoken');
const pool = require('./db');

const rooms = new Map();

function getOrCreateRoom(deviceId) {
  if (!rooms.has(deviceId)) {
    rooms.set(deviceId, { device: null, controller: null, sessionId: null });
  }
  return rooms.get(deviceId);
}

function send(ws, obj) {
  if (ws && ws.readyState === ws.OPEN) {
    ws.send(JSON.stringify(obj));
  }
}

function closeWithError(ws, reason) {
  send(ws, { type: 'error', reason });
  ws.close();
}

async function handleDevice(ws, deviceUid) {
  let deviceId;
  try {
    const { rows } = await pool.query(
      'SELECT id, org_id FROM devices WHERE device_uid = $1',
      [deviceUid]
    );
    if (!rows.length) {
      return closeWithError(ws, 'device_not_found');
    }
    deviceId = rows[0].id;
  } catch (err) {
    console.error('Signaling device auth error:', err.message);
    return ws.close();
  }

  const room = getOrCreateRoom(deviceId);
  room.device = ws;

  if (room.controller) {
    send(room.controller, { type: 'peer-joined' });
    send(ws, { type: 'peer-joined' });
  }

  ws.on('message', (data) => {
    if (room.controller) send(room.controller, JSON.parse(data));
  });

  ws.on('close', async () => {
    room.device = null;
    if (room.controller) send(room.controller, { type: 'peer-left' });
    if (room.sessionId) {
      try {
        await pool.query(
          `UPDATE remote_sessions SET ended_at = now(), end_reason = 'disconnect'
           WHERE id = $1 AND ended_at IS NULL`,
          [room.sessionId]
        );
      } catch (err) {
        console.error('Signaling session close error:', err.message);
      }
    }
  });
}

async function handleController(ws, token, deviceId) {
  let userId, orgId;
  try {
    const payload = jwt.verify(token, process.env.JWT_SECRET);
    userId = payload.sub;
    orgId = payload.org_id;
  } catch {
    return closeWithError(ws, 'unauthorized');
  }

  try {
    const { rows } = await pool.query(
      'SELECT id FROM devices WHERE id = $1 AND org_id = $2',
      [deviceId, orgId]
    );
    if (!rows.length) return closeWithError(ws, 'unauthorized');
  } catch (err) {
    console.error('Signaling controller auth error:', err.message);
    return ws.close();
  }

  const room = getOrCreateRoom(deviceId);
  if (room.controller) return closeWithError(ws, 'device_busy');

  room.controller = ws;

  try {
    const { rows } = await pool.query(
      `INSERT INTO remote_sessions (org_id, device_id, controller_id, connection_mode)
       VALUES ($1, $2, $3, 'p2p') RETURNING id`,
      [orgId, deviceId, userId]
    );
    room.sessionId = rows[0].id;
  } catch (err) {
    console.error('Signaling session insert error:', err.message);
  }

  if (room.device) {
    send(room.device, { type: 'peer-joined' });
    send(ws, { type: 'peer-joined' });
  }

  ws.on('message', async (data) => {
    let msg;
    try { msg = JSON.parse(data); } catch { return; }

    if (msg.type === 'session-end') {
      if (room.sessionId) {
        try {
          await pool.query(
            `UPDATE remote_sessions SET ended_at = now(), end_reason = 'user'
             WHERE id = $1 AND ended_at IS NULL`,
            [room.sessionId]
          );
        } catch (err) {
          console.error('Signaling session-end error:', err.message);
        }
      }
      send(room.device, { type: 'session-end' });
      if (room.device) room.device.close();
      ws.close();
      return;
    }

    if (room.device) send(room.device, msg);
  });

  ws.on('close', async () => {
    room.controller = null;
    if (room.device) send(room.device, { type: 'peer-left' });
    if (room.sessionId) {
      try {
        await pool.query(
          `UPDATE remote_sessions SET ended_at = now(), end_reason = 'disconnect'
           WHERE id = $1 AND ended_at IS NULL`,
          [room.sessionId]
        );
      } catch (err) {
        console.error('Signaling disconnect error:', err.message);
      }
    }
  });
}

function attachSignaling(server) {
  const wss = new WebSocketServer({ server, path: '/signal' });

  wss.on('connection', (ws, req) => {
    const params = new URL(req.url, 'http://localhost').searchParams;
    const deviceUid = params.get('device_uid');
    const token = params.get('token');
    const deviceId = params.get('device_id');

    if (deviceUid) {
      handleDevice(ws, deviceUid);
    } else if (token && deviceId) {
      handleController(ws, token, deviceId);
    } else {
      closeWithError(ws, 'unauthorized');
    }
  });
}

module.exports = { attachSignaling };
