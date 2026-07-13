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
    const [msg] = await Promise.all([nextMessage(ws), waitClose(ws)]);
    expect(msg).toEqual({ type: 'error', reason: 'device_not_found' });
  });
});
