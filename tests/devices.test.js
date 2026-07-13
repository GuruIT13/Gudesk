const request = require('supertest');
const app = require('../src/app');
const pool = require('../src/db');

let tokenAlice;    // Org A owner
let tokenBob;      // Org A member
let deviceIdOrgA;  // Org A - Device 2 (no active session, safe to patch/delete)
let deviceIdOrgB;  // Org B - Device 1
let dirABkkId;     // Org A - Bangkok Office directory

beforeAll(async () => {
  const resA = await request(app)
    .post('/api/auth/login')
    .send({ email: 'alice@alpha.com', password: 'plaintext_alice' });
  tokenAlice = resA.body.token;

  const resB = await request(app)
    .post('/api/auth/login')
    .send({ email: 'bob@alpha.com', password: 'plaintext_bob' });
  tokenBob = resB.body.token;

  const { rows: devA } = await pool.query(
    "SELECT id FROM devices WHERE hostname = 'Org A - Device 2' LIMIT 1"
  );
  deviceIdOrgA = devA[0].id;

  const { rows: devB } = await pool.query(
    "SELECT id FROM devices WHERE hostname = 'Org B - Device 1' LIMIT 1"
  );
  deviceIdOrgB = devB[0].id;

  const { rows: dir } = await pool.query(
    "SELECT id FROM directories WHERE name = 'Org A - Bangkok Office' LIMIT 1"
  );
  dirABkkId = dir[0].id;
});

afterAll(async () => {
  await pool.end();
});

describe('GET /api/devices', () => {
  test('returns 200 and array of all org devices', async () => {
    const res = await request(app)
      .get('/api/devices')
      .set('Authorization', `Bearer ${tokenAlice}`);
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
    expect(res.body.length).toBeGreaterThan(0);
    // all devices belong to org A
    res.body.forEach(d => expect(d).toHaveProperty('hostname'));
  });

  test('returns filtered devices by directory_id', async () => {
    const res = await request(app)
      .get(`/api/devices?directory_id=${dirABkkId}`)
      .set('Authorization', `Bearer ${tokenAlice}`);
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
    res.body.forEach(d => expect(d.directory_id).toBe(dirABkkId));
  });
});

describe('GET /api/devices/:id', () => {
  test('returns 404 when device belongs to another org', async () => {
    const res = await request(app)
      .get(`/api/devices/${deviceIdOrgB}`)
      .set('Authorization', `Bearer ${tokenAlice}`);
    expect(res.status).toBe(404);
    expect(res.body.error).toBe('not_found');
  });
});

describe('PATCH /api/devices/:id', () => {
  test('moves device to a different directory and returns 200', async () => {
    const res = await request(app)
      .patch(`/api/devices/${deviceIdOrgA}`)
      .set('Authorization', `Bearer ${tokenAlice}`)
      .send({ directory_id: dirABkkId });
    expect(res.status).toBe(200);
    expect(res.body.directory_id).toBe(dirABkkId);
  });
});

describe('DELETE /api/devices/:id', () => {
  test('returns 403 when role is member', async () => {
    const res = await request(app)
      .delete(`/api/devices/${deviceIdOrgA}`)
      .set('Authorization', `Bearer ${tokenBob}`);
    expect(res.status).toBe(403);
  });

  test('deletes device as admin/owner and returns 200', async () => {
    const res = await request(app)
      .delete(`/api/devices/${deviceIdOrgA}`)
      .set('Authorization', `Bearer ${tokenAlice}`);
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
  });
});
