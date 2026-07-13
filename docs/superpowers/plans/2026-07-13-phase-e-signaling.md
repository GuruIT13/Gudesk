# Phase E — WebSocket Signaling Server Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a WebSocket signaling server to the existing Express HTTP server so Flutter controllers and device agents can exchange WebRTC offer/answer/ICE candidates through room-based routing.

**Architecture:** `ws` library attaches to the same `http.Server` that Express uses (port 3000). `signaling.js` owns the in-memory room map and all WebSocket logic. `server.js` is updated to create an explicit `http.Server` and wire both Express and the signaling module to it. No changes to `app.js`.

**Tech Stack:** Node.js, `ws` npm package, `jsonwebtoken` (already installed), `pg` pool (already installed), Jest + `ws` client for tests

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `package.json` | Modify | Add `ws` dependency |
| `src/signaling.js` | Create | Room map, auth, routing, session lifecycle |
| `src/server.js` | Modify | Create `http.Server`, attach signaling |
| `tests/signaling.test.js` | Create | 10 integration tests |

---

### Task 1: Install `ws` and wire `http.Server`

**Files:**
- Modify: `package.json`
- Modify: `src/server.js`

**Context:** Currently `server.js` calls `app.listen()` which creates an implicit HTTP server. We need an explicit `http.Server` so we can attach the WebSocket server to it. The signaling module will be created as a stub in this task (replaced in Task 2).

- [ ] **Step 1: Install `ws`**

```bash
npm install ws
```

Expected: `ws` appears in `package.json` dependencies.

- [ ] **Step 2: Create stub `src/signaling.js`**

```js
// src/signaling.js
function attachSignaling(server) {
  // stub — implemented in Task 2
}

module.exports = { attachSignaling };
```

- [ ] **Step 3: Update `src/server.js`**

Replace the entire file with:

```js
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const http = require('http');
const app = require('./app');
const { attachSignaling } = require('./signaling');

const PORT = process.env.PORT || 3000;
const server = http.createServer(app);
attachSignaling(server);

server.listen(PORT, () => {
  console.log(`GuDesk API listening on port ${PORT}`);
});
```

- [ ] **Step 4: Verify existing tests still pass**

```bash
npm test
```

Expected: all 38 tests pass (stub signaling doesn't break anything)

- [ ] **Step 5: Commit**

```bash
git add package.json package-lock.json src/server.js src/signaling.js
git commit -m "feat: install ws, wire http.Server for signaling attachment"
```

---

### Task 2: Signaling core — auth, room map, device flow

**Files:**
- Modify: `src/signaling.js` (replace stub)
- Create: `tests/signaling.test.js` (tests 1–2 only, device auth)

**Context:**

JWT structure (from `src/routes/auth.js`): `{ sub: userId, org_id, role }` signed with `process.env.JWT_SECRET`.

Room map structure:
```js
// key: device_id (uuid string)
// value: { device: WebSocket|null, controller: WebSocket|null, sessionId: string|null }
const rooms = new Map();
```

WebSocket upgrade path: client connects to `ws://host/signal?...`. The `ws` `WebSocketServer` with `{ server, path: '/signal' }` intercepts upgrades to `/signal` only.

Query string parsing: use Node built-in `new URL(req.url, 'http://localhost').searchParams`.

Sending a close-with-error pattern:
```js
ws.send(JSON.stringify({ type: 'error', reason: 'device_not_found' }));
ws.close();
```

- [ ] **Step 1: Write failing tests 1–2**

```js
// tests/signaling.test.js
const http = require('http');
const WebSocket = require('ws');
const app = require('../src/app');
const { attachSignaling } = require('../src/signaling');
const pool = require('../src/db');

let server;
let baseUrl;
let deviceUidOrgA;
let deviceIdOrgA;
let tokenAlice;

function wsConnect(url) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(url);
    ws.on('open', () => resolve(ws));
    ws.on('error', reject);
  });
}

function nextMessage(ws) {
  return new Promise((resolve) => {
    ws.once('message', (data) => resolve(JSON.parse(data)));
  });
}

function waitClose(ws) {
  return new Promise((resolve) => ws.once('close', resolve));
}

beforeAll(async () => {
  server = http.createServer(app);
  attachSignaling(server);
  await new Promise((resolve) => server.listen(0, resolve));
  const { port } = server.address();
  baseUrl = `ws://localhost:${port}/signal`;

  const { rows: devRows } = await pool.query(
    "SELECT id, device_uid FROM devices WHERE hostname = 'Org A - Device 1' LIMIT 1"
  );
  deviceIdOrgA = devRows[0].id;
  deviceUidOrgA = devRows[0].device_uid;

  const resA = await fetch(`http://localhost:${port}/api/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: 'alice@alpha.com', password: 'plaintext_alice' }),
  });
  const body = await resA.json();
  tokenAlice = body.token;
});

afterAll(async () => {
  await new Promise((resolve) => server.close(resolve));
  await pool.end();
});

describe('Device agent auth', () => {
  test('connects with valid device_uid — connection stays open', async () => {
    const ws = await wsConnect(`${baseUrl}?device_uid=${deviceUidOrgA}`);
    expect(ws.readyState).toBe(WebSocket.OPEN);
    ws.close();
    await waitClose(ws);
  });

  test('connects with invalid device_uid — receives error and connection closes', async () => {
    const ws = new WebSocket(`${baseUrl}?device_uid=00000000-0000-0000-0000-000000000000`);
    const msg = await nextMessage(ws);
    expect(msg).toEqual({ type: 'error', reason: 'device_not_found' });
    await waitClose(ws);
  });
});
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
npx jest tests/signaling.test.js --runInBand 2>&1 | tail -20
```

Expected: FAIL — stub `attachSignaling` does nothing

- [ ] **Step 3: Implement `src/signaling.js` — device agent flow**

```js
// src/signaling.js
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const { WebSocketServer } = require('ws');
const jwt = require('jsonwebtoken');
const pool = require('./db');

// rooms: Map<device_id, { device: WebSocket|null, controller: WebSocket|null, sessionId: string|null }>
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

  // INSERT session
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
```

- [ ] **Step 4: Run tests 1–2**

```bash
npx jest tests/signaling.test.js --runInBand 2>&1
```

Expected: 2 tests pass

- [ ] **Step 5: Run full suite**

```bash
npm test
```

Expected: all 38 + 2 = 40 tests pass (reseed if dirty DB)

- [ ] **Step 6: Commit**

```bash
git add src/signaling.js tests/signaling.test.js
git commit -m "feat: implement signaling server — device agent auth and room registration"
```

---

### Task 3: Controller auth + room routing + session lifecycle + remaining tests

**Files:**
- Modify: `tests/signaling.test.js` (add tests 3–10)

**Context:** `signaling.js` already implements controller flow (handleController). This task adds tests 3–10 that exercise controller auth, room pairing, message relay, session lifecycle, and error cases. The `fetch` global is available in Node 18+; if not, use `require('node-fetch')` — but Node 18 is used here so `fetch` is global.

- [ ] **Step 1: Add tests 3–10 to `tests/signaling.test.js`**

Add these describe blocks after the existing `Device agent auth` describe block:

```js
describe('Controller auth', () => {
  test('connects with valid JWT + device_id — connection stays open', async () => {
    const ws = await wsConnect(`${baseUrl}?token=${tokenAlice}&device_id=${deviceIdOrgA}`);
    expect(ws.readyState).toBe(WebSocket.OPEN);
    ws.close();
    await waitClose(ws);
  });

  test('connects with invalid JWT — receives error and connection closes', async () => {
    const ws = new WebSocket(`${baseUrl}?token=garbage.token.here&device_id=${deviceIdOrgA}`);
    const msg = await nextMessage(ws);
    expect(msg).toEqual({ type: 'error', reason: 'unauthorized' });
    await waitClose(ws);
  });

  test('connects to device in other org — receives error unauthorized', async () => {
    const { rows } = await pool.query(
      "SELECT id FROM devices WHERE hostname = 'Org B - Device 1' LIMIT 1"
    );
    const orgBDeviceId = rows[0].id;
    const ws = new WebSocket(`${baseUrl}?token=${tokenAlice}&device_id=${orgBDeviceId}`);
    const msg = await nextMessage(ws);
    expect(msg).toEqual({ type: 'error', reason: 'unauthorized' });
    await waitClose(ws);
  });
});

describe('Room routing', () => {
  test('device connects first, then controller — both receive peer-joined', async () => {
    const { rows } = await pool.query(
      "SELECT id, device_uid FROM devices WHERE hostname = 'Org A - Device 2' LIMIT 1"
    );
    const devId = rows[0].id;
    const devUid = rows[0].device_uid;

    const deviceWs = await wsConnect(`${baseUrl}?device_uid=${devUid}`);
    const controllerWs = await wsConnect(`${baseUrl}?token=${tokenAlice}&device_id=${devId}`);

    const [devMsg, ctrlMsg] = await Promise.all([
      nextMessage(deviceWs),
      nextMessage(controllerWs),
    ]);
    expect(devMsg).toEqual({ type: 'peer-joined' });
    expect(ctrlMsg).toEqual({ type: 'peer-joined' });

    deviceWs.close();
    controllerWs.close();
    await Promise.all([waitClose(deviceWs), waitClose(controllerWs)]);
  });

  test('controller sends offer — device receives it verbatim', async () => {
    const { rows } = await pool.query(
      "SELECT id, device_uid FROM devices WHERE hostname = 'Org A - Device 3 (BKK)' LIMIT 1"
    );
    const devId = rows[0].id;
    const devUid = rows[0].device_uid;

    const deviceWs = await wsConnect(`${baseUrl}?device_uid=${devUid}`);
    const controllerWs = await wsConnect(`${baseUrl}?token=${tokenAlice}&device_id=${devId}`);

    // drain peer-joined messages
    await Promise.all([nextMessage(deviceWs), nextMessage(controllerWs)]);

    const offer = { type: 'offer', sdp: 'v=0\r\n...' };
    controllerWs.send(JSON.stringify(offer));
    const received = await nextMessage(deviceWs);
    expect(received).toEqual(offer);

    deviceWs.close();
    controllerWs.close();
    await Promise.all([waitClose(deviceWs), waitClose(controllerWs)]);
  });

  test('controller disconnects — device receives peer-left', async () => {
    const { rows } = await pool.query(
      "SELECT id, device_uid FROM devices WHERE hostname = 'Org A - Device 1' LIMIT 1"
    );
    const devId = rows[0].id;
    const devUid = rows[0].device_uid;

    const deviceWs = await wsConnect(`${baseUrl}?device_uid=${devUid}`);
    const controllerWs = await wsConnect(`${baseUrl}?token=${tokenAlice}&device_id=${devId}`);

    // drain peer-joined
    await Promise.all([nextMessage(deviceWs), nextMessage(controllerWs)]);

    controllerWs.close();
    const msg = await nextMessage(deviceWs);
    expect(msg).toEqual({ type: 'peer-left' });

    deviceWs.close();
    await waitClose(deviceWs);
  });

  test('second controller connects to occupied room — receives device_busy', async () => {
    const { rows } = await pool.query(
      "SELECT id, device_uid FROM devices WHERE hostname = 'Org A - Device 2' LIMIT 1"
    );
    const devId = rows[0].id;
    const devUid = rows[0].device_uid;

    const deviceWs = await wsConnect(`${baseUrl}?device_uid=${devUid}`);
    const ctrl1 = await wsConnect(`${baseUrl}?token=${tokenAlice}&device_id=${devId}`);
    // drain peer-joined
    await Promise.all([nextMessage(deviceWs), nextMessage(ctrl1)]);

    const ctrl2 = new WebSocket(`${baseUrl}?token=${tokenAlice}&device_id=${devId}`);
    const msg = await nextMessage(ctrl2);
    expect(msg).toEqual({ type: 'error', reason: 'device_busy' });
    await waitClose(ctrl2);

    deviceWs.close();
    ctrl1.close();
    await Promise.all([waitClose(deviceWs), waitClose(ctrl1)]);
  });
});

describe('Session lifecycle', () => {
  test('session-end from controller — remote_sessions.ended_at set in DB', async () => {
    const { rows } = await pool.query(
      "SELECT id, device_uid FROM devices WHERE hostname = 'Org A - Device 3 (BKK)' LIMIT 1"
    );
    const devId = rows[0].id;
    const devUid = rows[0].device_uid;

    const deviceWs = await wsConnect(`${baseUrl}?device_uid=${devUid}`);
    const controllerWs = await wsConnect(`${baseUrl}?token=${tokenAlice}&device_id=${devId}`);

    // drain peer-joined
    await Promise.all([nextMessage(deviceWs), nextMessage(controllerWs)]);

    controllerWs.send(JSON.stringify({ type: 'session-end' }));

    // both connections should close
    await Promise.all([waitClose(deviceWs), waitClose(controllerWs)]);

    // verify DB
    const { rows: sessions } = await pool.query(
      `SELECT ended_at, end_reason FROM remote_sessions
       WHERE device_id = $1 AND ended_at IS NOT NULL
       ORDER BY started_at DESC LIMIT 1`,
      [devId]
    );
    expect(sessions.length).toBeGreaterThan(0);
    expect(sessions[0].end_reason).toBe('user');
    expect(sessions[0].ended_at).not.toBeNull();
  });
});
```

- [ ] **Step 2: Run all signaling tests**

```bash
npx jest tests/signaling.test.js --runInBand 2>&1
```

Expected: all 10 tests pass

- [ ] **Step 3: Run full suite**

```bash
npm test
```

If dirty DB (devices/directories tests fail with `Cannot read properties of undefined`), reseed:
```powershell
$env:PGPASSWORD='postgres'; & "C:\Program Files\PostgreSQL\17\bin\psql.exe" -U postgres -d gudesk -c "TRUNCATE organizations CASCADE;"
$env:PGPASSWORD='postgres'; & "C:\Program Files\PostgreSQL\17\bin\psql.exe" -U postgres -d gudesk -c "TRUNCATE users CASCADE;"
node seeds/seed.js
```

Expected: all 48 tests pass (38 existing + 10 signaling)

- [ ] **Step 4: Commit**

```bash
git add tests/signaling.test.js
git commit -m "test: add signaling integration tests — controller auth, room routing, session lifecycle"
```

---

## Spec Coverage Self-Check

| Spec requirement | Task |
|-----------------|------|
| `ws` attached to same HTTP server | Task 1 |
| `server.js` uses explicit `http.Server` | Task 1 |
| Stub `signaling.js` so existing tests pass | Task 1 |
| Device auth: `device_uid` DB lookup | Task 2 |
| Device close → `peer-left` + session update | Task 2 |
| Controller auth: JWT verify + org-scoped device lookup | Task 2 |
| `device_busy` for second controller | Task 2 |
| INSERT `remote_sessions` when room full | Task 2 |
| Message relay: offer/answer/ice-candidate forwarded | Task 3 |
| `session-end` → UPDATE `ended_at`, close both | Task 3 |
| Cross-org controller → `unauthorized` | Task 3 |
| 10 integration tests | Tasks 2+3 |
| Security: org_id from JWT only | Task 2 |
