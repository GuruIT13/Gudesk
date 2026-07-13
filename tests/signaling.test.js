const http = require('http');
const WebSocket = require('ws');
const app = require('../src/app');
const { attachSignaling } = require('../src/signaling');
const pool = require('../src/db');

let server;
let baseUrl;
let deviceUidOrgA;
let deviceIdOrgA;
let deviceUidBkk;
let deviceIdBkk;
let orgBDeviceId;
let tokenAlice;

function wsConnect(url) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(url);
    ws.on('open', () => resolve(ws));
    ws.on('error', reject);
  });
}

function nextMessage(ws, timeoutMs = 3000) {
  return new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(new Error('nextMessage timed out')), timeoutMs);
    ws.once('message', (data) => { clearTimeout(t); resolve(JSON.parse(data)); });
  });
}

function waitClose(ws) {
  return new Promise((resolve) => ws.once('close', resolve));
}

beforeAll(async () => {
  // Close any active sessions from seed data so INSERT doesn't conflict
  await pool.query(
    `UPDATE remote_sessions SET ended_at = now(), end_reason = 'disconnect'
     WHERE ended_at IS NULL`
  );

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

  const { rows: bkkRows } = await pool.query(
    "SELECT id, device_uid FROM devices WHERE hostname = 'Org A - Device 3 (BKK)' LIMIT 1"
  );
  deviceIdBkk = bkkRows[0].id;
  deviceUidBkk = bkkRows[0].device_uid;

  const { rows: orgBRows } = await pool.query(
    "SELECT id FROM devices WHERE hostname = 'Org B - Device 1' LIMIT 1"
  );
  orgBDeviceId = orgBRows[0].id;

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
    const [msg] = await Promise.all([nextMessage(ws), waitClose(ws)]);
    expect(msg).toEqual({ type: 'error', reason: 'device_not_found' });
  });
});

describe('Controller auth', () => {
  test('connects with valid JWT + device_id — connection stays open', async () => {
    const ws = await wsConnect(`${baseUrl}?token=${tokenAlice}&device_id=${deviceIdOrgA}`);
    expect(ws.readyState).toBe(WebSocket.OPEN);
    ws.close();
    await waitClose(ws);
  });

  test('connects with invalid JWT — receives error and connection closes', async () => {
    const ws = new WebSocket(`${baseUrl}?token=garbage.token.here&device_id=${deviceIdOrgA}`);
    const [msg] = await Promise.all([nextMessage(ws), waitClose(ws)]);
    expect(msg).toEqual({ type: 'error', reason: 'unauthorized' });
  });

  test('connects to device in other org — receives error unauthorized', async () => {
    const ws = new WebSocket(`${baseUrl}?token=${tokenAlice}&device_id=${orgBDeviceId}`);
    const [msg] = await Promise.all([nextMessage(ws), waitClose(ws)]);
    expect(msg).toEqual({ type: 'error', reason: 'unauthorized' });
  });
});

describe('Room routing', () => {
  test('device connects first, then controller — both receive peer-joined', async () => {
    const deviceWs = await wsConnect(`${baseUrl}?device_uid=${deviceUidOrgA}`);
    const controllerWs = await wsConnect(`${baseUrl}?token=${tokenAlice}&device_id=${deviceIdOrgA}`);

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

  test('controller connects first, then device — both receive peer-joined', async () => {
    const controllerWs = await wsConnect(`${baseUrl}?token=${tokenAlice}&device_id=${deviceIdBkk}`);
    const deviceWs = await wsConnect(`${baseUrl}?device_uid=${deviceUidBkk}`);

    const [ctrlMsg, devMsg] = await Promise.all([
      nextMessage(controllerWs),
      nextMessage(deviceWs),
    ]);
    expect(ctrlMsg).toEqual({ type: 'peer-joined' });
    expect(devMsg).toEqual({ type: 'peer-joined' });

    deviceWs.close();
    controllerWs.close();
    await Promise.all([waitClose(deviceWs), waitClose(controllerWs)]);
  });

  test('controller sends offer — device receives it verbatim', async () => {
    const deviceWs = await wsConnect(`${baseUrl}?device_uid=${deviceUidOrgA}`);
    const controllerWs = await wsConnect(`${baseUrl}?token=${tokenAlice}&device_id=${deviceIdOrgA}`);

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
    const deviceWs = await wsConnect(`${baseUrl}?device_uid=${deviceUidBkk}`);
    const controllerWs = await wsConnect(`${baseUrl}?token=${tokenAlice}&device_id=${deviceIdBkk}`);

    // drain peer-joined
    await Promise.all([nextMessage(deviceWs), nextMessage(controllerWs)]);

    controllerWs.close();
    const msg = await nextMessage(deviceWs);
    expect(msg).toEqual({ type: 'peer-left' });

    deviceWs.close();
    await waitClose(deviceWs);
  });

  test('second controller connects to occupied room — receives device_busy', async () => {
    const deviceWs = await wsConnect(`${baseUrl}?device_uid=${deviceUidOrgA}`);
    const ctrl1 = await wsConnect(`${baseUrl}?token=${tokenAlice}&device_id=${deviceIdOrgA}`);
    // drain peer-joined
    await Promise.all([nextMessage(deviceWs), nextMessage(ctrl1)]);

    const ctrl2 = new WebSocket(`${baseUrl}?token=${tokenAlice}&device_id=${deviceIdOrgA}`);
    const [msg] = await Promise.all([nextMessage(ctrl2), waitClose(ctrl2)]);
    expect(msg).toEqual({ type: 'error', reason: 'device_busy' });

    deviceWs.close();
    ctrl1.close();
    await Promise.all([waitClose(deviceWs), waitClose(ctrl1)]);
  });
});

describe('Session lifecycle', () => {
  test('session-end from controller — remote_sessions.ended_at set in DB', async () => {
    const deviceWs = await wsConnect(`${baseUrl}?device_uid=${deviceUidBkk}`);
    const controllerWs = await wsConnect(`${baseUrl}?token=${tokenAlice}&device_id=${deviceIdBkk}`);

    // drain peer-joined
    await Promise.all([nextMessage(deviceWs), nextMessage(controllerWs)]);

    controllerWs.send(JSON.stringify({ type: 'session-end' }));

    // both connections close
    await Promise.all([waitClose(deviceWs), waitClose(controllerWs)]);

    const { rows: sessions } = await pool.query(
      `SELECT ended_at, end_reason FROM remote_sessions
       WHERE device_id = $1 AND ended_at IS NOT NULL
       ORDER BY started_at DESC LIMIT 1`,
      [deviceIdBkk]
    );
    expect(sessions.length).toBeGreaterThan(0);
    expect(sessions[0].end_reason).toBe('user');
    expect(sessions[0].ended_at).not.toBeNull();
  });
});
