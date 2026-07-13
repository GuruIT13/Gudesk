const request = require('supertest');
const app = require('../src/app');
const pool = require('../src/db');

afterAll(async () => {
  await pool.end();
});

describe('POST /api/auth/login', () => {
  test('returns 200 + JWT for valid credentials', async () => {
    const res = await request(app)
      .post('/api/auth/login')
      .send({ email: 'alice@alpha.com', password: 'plaintext_alice' });
    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty('token');
    expect(res.body.user.email).toBe('alice@alpha.com');
    expect(res.body.org).toHaveProperty('slug');
  });

  test('returns 401 for wrong password', async () => {
    const res = await request(app)
      .post('/api/auth/login')
      .send({ email: 'alice@alpha.com', password: 'wrongpassword' });
    expect(res.status).toBe(401);
    expect(res.body).toEqual({ error: 'invalid_credentials' });
  });

  test('returns 401 for unknown email', async () => {
    const res = await request(app)
      .post('/api/auth/login')
      .send({ email: 'nobody@nowhere.com', password: 'whatever' });
    expect(res.status).toBe(401);
    expect(res.body).toEqual({ error: 'invalid_credentials' });
  });
});

describe('scopeToOrg middleware', () => {
  test('returns 401 when no Authorization header', async () => {
    const res = await request(app).get('/api/ping');
    expect(res.status).toBe(401);
  });

  test('returns 401 when token is invalid', async () => {
    const res = await request(app)
      .get('/api/ping')
      .set('Authorization', 'Bearer not.a.valid.token');
    expect(res.status).toBe(401);
  });
});

describe('Authenticated routes + cross-org isolation', () => {
  let tokenOrgA;
  let tokenOrgB;
  let deviceIdOrgA;
  let deviceIdOrgB;

  beforeAll(async () => {
    const resA = await request(app)
      .post('/api/auth/login')
      .send({ email: 'alice@alpha.com', password: 'plaintext_alice' });
    tokenOrgA = resA.body.token;

    const resB = await request(app)
      .post('/api/auth/login')
      .send({ email: 'carol@beta.com', password: 'plaintext_carol' });
    tokenOrgB = resB.body.token;

    const { rows: devicesA } = await pool.query(
      "SELECT id FROM devices WHERE hostname = 'Org A - Device 1' LIMIT 1"
    );
    deviceIdOrgA = devicesA[0].id;

    const { rows: devicesB } = await pool.query(
      "SELECT id FROM devices WHERE hostname = 'Org B - Device 1' LIMIT 1"
    );
    deviceIdOrgB = devicesB[0].id;
  });

  test('returns 401 when no token provided', async () => {
    const res = await request(app).get('/api/ping');
    expect(res.status).toBe(401);
  });

  test('returns 401 when token is invalid', async () => {
    const res = await request(app)
      .get('/api/ping')
      .set('Authorization', 'Bearer garbage.token.here');
    expect(res.status).toBe(401);
  });

  test('returns 200 with valid token on /api/ping', async () => {
    const res = await request(app)
      .get('/api/ping')
      .set('Authorization', `Bearer ${tokenOrgA}`);
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
  });

  test('Org A token can access Org A device', async () => {
    const res = await request(app)
      .get(`/api/devices/${deviceIdOrgA}`)
      .set('Authorization', `Bearer ${tokenOrgA}`);
    expect(res.status).toBe(200);
    expect(res.body.hostname).toBe('Org A - Device 1');
  });

  test('cross-org: Org A token gets 404 when accessing Org B device', async () => {
    const res = await request(app)
      .get(`/api/devices/${deviceIdOrgB}`)
      .set('Authorization', `Bearer ${tokenOrgA}`);
    expect(res.status).toBe(404);
    expect(res.body).toEqual({ error: 'not_found' });
  });
});
