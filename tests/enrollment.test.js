const request = require('supertest');
const app = require('../src/app');
const pool = require('../src/db');

let tokenAlice;  // Org A owner
let tokenBob;    // Org A member
let tokenCarol;  // Org B owner
let orgAId;
let createdTokenId;
let validToken;

beforeAll(async () => {
  const resA = await request(app)
    .post('/api/auth/login')
    .send({ email: 'alice@alpha.com', password: 'plaintext_alice' });
  tokenAlice = resA.body.token;
  orgAId = resA.body.org.id;

  const resB = await request(app)
    .post('/api/auth/login')
    .send({ email: 'bob@alpha.com', password: 'plaintext_bob' });
  tokenBob = resB.body.token;

  const resC = await request(app)
    .post('/api/auth/login')
    .send({ email: 'carol@beta.com', password: 'plaintext_carol' });
  tokenCarol = resC.body.token;
});

afterAll(async () => {
  await pool.end();
});

describe('POST /api/enrollment-tokens', () => {
  test('owner creates token — returns 201 with token string', async () => {
    const res = await request(app)
      .post('/api/enrollment-tokens')
      .set('Authorization', `Bearer ${tokenAlice}`)
      .send({ expires_in_hours: 24 });
    expect(res.status).toBe(201);
    expect(res.body).toHaveProperty('id');
    expect(res.body).toHaveProperty('token');
    expect(res.body).toHaveProperty('expires_at');
    expect(typeof res.body.token).toBe('string');
    expect(res.body.token).toHaveLength(64);
    expect(new Date(res.body.expires_at).getTime()).toBeGreaterThan(Date.now());
    expect(res.body).not.toHaveProperty('token_hash');
    createdTokenId = res.body.id;
    validToken = res.body.token;
  });

  test('member role returns 403', async () => {
    const res = await request(app)
      .post('/api/enrollment-tokens')
      .set('Authorization', `Bearer ${tokenBob}`)
      .send({ expires_in_hours: 24 });
    expect(res.status).toBe(403);
  });
});

describe('GET /api/enrollment-tokens', () => {
  test('returns 200 and array with is_expired field', async () => {
    const res = await request(app)
      .get('/api/enrollment-tokens')
      .set('Authorization', `Bearer ${tokenAlice}`);
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
    expect(res.body.length).toBeGreaterThan(0);
    const created = res.body.find(r => r.id === createdTokenId);
    expect(created).toBeDefined();
    expect(created).toHaveProperty('is_expired');
    expect(created).toHaveProperty('expires_at');
    expect(created).toHaveProperty('created_by');
    expect(created).not.toHaveProperty('token_hash');
  });
});

describe('DELETE /api/enrollment-tokens/:id', () => {
  test('revokes unused token — returns 200', async () => {
    const createRes = await request(app)
      .post('/api/enrollment-tokens')
      .set('Authorization', `Bearer ${tokenAlice}`)
      .send({ expires_in_hours: 1 });
    const idToDelete = createRes.body.id;

    const res = await request(app)
      .delete(`/api/enrollment-tokens/${idToDelete}`)
      .set('Authorization', `Bearer ${tokenAlice}`);
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
  });
});

describe('Cross-org isolation for enrollment-tokens', () => {
  test('GET /api/enrollment-tokens does not return Org A tokens to Org B user', async () => {
    const res = await request(app)
      .get('/api/enrollment-tokens')
      .set('Authorization', `Bearer ${tokenCarol}`);
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
    // Org B user should not see any Org A tokens
    expect(res.body.every(r => r.id !== createdTokenId)).toBe(true);
  });

  test('DELETE /api/enrollment-tokens/:id returns 404 for cross-org token', async () => {
    const res = await request(app)
      .delete(`/api/enrollment-tokens/${createdTokenId}`)
      .set('Authorization', `Bearer ${tokenCarol}`);
    expect(res.status).toBe(404);
    expect(res.body.error).toBe('not_found');
  });
});

describe('POST /api/devices/enroll', () => {
  test('valid token enrolls device — returns 201 with device_id, device_uid, org_id', async () => {
    const res = await request(app)
      .post('/api/devices/enroll')
      .send({
        token: validToken,
        hostname: 'TEST-DEVICE-01',
        os_type: 'linux',
        os_version: '22.04',
      });
    expect(res.status).toBe(201);
    expect(res.body).toHaveProperty('device_id');
    expect(res.body).toHaveProperty('device_uid');
    expect(res.body).toHaveProperty('org_id');
    expect(res.body.org_id).toBe(orgAId);

    // verify the token is now consumed — reusing it returns 401
    const reuse = await request(app)
      .post('/api/devices/enroll')
      .send({ token: validToken, hostname: 'REUSE-ATTEMPT' });
    expect(reuse.status).toBe(401);
    expect(reuse.body.error).toBe('invalid_token');
  });

  test('invalid/unknown token returns 401', async () => {
    const res = await request(app)
      .post('/api/devices/enroll')
      .send({ token: 'a'.repeat(64), hostname: 'FAKE-DEVICE' });
    expect(res.status).toBe(401);
    expect(res.body.error).toBe('invalid_token');
  });

  test('expired token returns 401', async () => {
    const crypto = require('crypto');
    const expiredPlaintext = 'expired_token_test_value'.padEnd(64, '0');
    const expiredHash = crypto.createHash('sha256').update(expiredPlaintext).digest('hex');
    const { rows: orgRows } = await pool.query(
      "SELECT id FROM organizations WHERE slug = 'alpha-corp' LIMIT 1"
    );
    const { rows: userRows } = await pool.query(
      "SELECT id FROM users WHERE email = 'alice@alpha.com' LIMIT 1"
    );
    await pool.query(
      `INSERT INTO enrollment_tokens (org_id, created_by, token_hash, expires_at)
       VALUES ($1, $2, $3, now() - interval '1 hour')
       ON CONFLICT (token_hash) DO NOTHING`,
      [orgRows[0].id, userRows[0].id, expiredHash]
    );
    const res = await request(app)
      .post('/api/devices/enroll')
      .send({ token: expiredPlaintext, hostname: 'FAKE' });
    expect(res.status).toBe(401);
    expect(res.body.error).toBe('invalid_token');
  });

  test('already used token returns 401', async () => {
    const crypto = require('crypto');
    const usedPlaintext = 'used_token_test_value_here'.padEnd(64, '0');
    const usedHash = crypto.createHash('sha256').update(usedPlaintext).digest('hex');
    const { rows: orgRows } = await pool.query(
      "SELECT id FROM organizations WHERE slug = 'alpha-corp' LIMIT 1"
    );
    const { rows: userRows } = await pool.query(
      "SELECT id FROM users WHERE email = 'alice@alpha.com' LIMIT 1"
    );
    await pool.query(
      `INSERT INTO enrollment_tokens (org_id, created_by, token_hash, expires_at, used_at)
       VALUES ($1, $2, $3, now() + interval '1 hour', now() - interval '5 minutes')
       ON CONFLICT (token_hash) DO NOTHING`,
      [orgRows[0].id, userRows[0].id, usedHash]
    );
    const res = await request(app)
      .post('/api/devices/enroll')
      .send({ token: usedPlaintext, hostname: 'FAKE' });
    expect(res.status).toBe(401);
    expect(res.body.error).toBe('invalid_token');
  });

  test('missing token/hostname returns 400', async () => {
    const res = await request(app)
      .post('/api/devices/enroll')
      .send({});
    expect(res.status).toBe(400);
  });
});
