const request = require('supertest');
const app = require('../src/app');
const pool = require('../src/db');

let tokenAlice;  // Org A owner
let tokenBob;    // Org A member
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
