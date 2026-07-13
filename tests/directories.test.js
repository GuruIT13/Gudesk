const request = require('supertest');
const app = require('../src/app');
const pool = require('../src/db');

let tokenAlice;   // Org A owner
let tokenBob;     // Org A member
let tokenCarol;   // Org B owner
let orgBDirId;    // a directory belonging to Org B
let newDirId;     // created during test 2, used in test 4 and 7

beforeAll(async () => {
  const resA = await request(app)
    .post('/api/auth/login')
    .send({ email: 'alice@alpha.com', password: 'plaintext_alice' });
  tokenAlice = resA.body.token;

  const resB = await request(app)
    .post('/api/auth/login')
    .send({ email: 'bob@alpha.com', password: 'plaintext_bob' });
  tokenBob = resB.body.token;

  const resC = await request(app)
    .post('/api/auth/login')
    .send({ email: 'carol@beta.com', password: 'plaintext_carol' });
  tokenCarol = resC.body.token;

  // get a directory that belongs to Org B
  const { rows } = await pool.query(
    "SELECT id FROM directories WHERE name = 'Org B - Root' LIMIT 1"
  );
  orgBDirId = rows[0].id;
});

afterAll(async () => {
  await pool.end();
});

describe('GET /api/directories', () => {
  test('returns 200 and nested tree for valid token', async () => {
    const res = await request(app)
      .get('/api/directories')
      .set('Authorization', `Bearer ${tokenAlice}`);
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
    // each root node has a children array
    res.body.forEach(node => expect(Array.isArray(node.children)).toBe(true));
  });
});

describe('POST /api/directories', () => {
  test('creates a root directory and returns 201', async () => {
    const res = await request(app)
      .post('/api/directories')
      .set('Authorization', `Bearer ${tokenAlice}`)
      .send({ name: 'Test Dir Phase C' });
    expect(res.status).toBe(201);
    expect(res.body.name).toBe('Test Dir Phase C');
    expect(res.body.parent_id).toBeNull();
    newDirId = res.body.id;
  });

  test('returns 404 when parent_id belongs to another org', async () => {
    const res = await request(app)
      .post('/api/directories')
      .set('Authorization', `Bearer ${tokenAlice}`)
      .send({ name: 'Should Fail', parent_id: orgBDirId });
    expect(res.status).toBe(404);
  });
});

describe('PATCH /api/directories/:id', () => {
  test('renames a directory and returns 200', async () => {
    const res = await request(app)
      .patch(`/api/directories/${newDirId}`)
      .set('Authorization', `Bearer ${tokenAlice}`)
      .send({ name: 'Renamed Dir' });
    expect(res.status).toBe(200);
    expect(res.body.name).toBe('Renamed Dir');
  });

  test('returns 403 when role is member', async () => {
    const res = await request(app)
      .patch(`/api/directories/${newDirId}`)
      .set('Authorization', `Bearer ${tokenBob}`)
      .send({ name: 'Should Not Work' });
    expect(res.status).toBe(403);
  });
});

describe('DELETE /api/directories/:id', () => {
  test('returns 409 when directory has devices', async () => {
    // Org A - Root has devices in seed data
    const { rows } = await pool.query(
      "SELECT id FROM directories WHERE name = 'Org A - Root' LIMIT 1"
    );
    const rootId = rows[0].id;
    const res = await request(app)
      .delete(`/api/directories/${rootId}`)
      .set('Authorization', `Bearer ${tokenAlice}`);
    expect(res.status).toBe(409);
    expect(res.body.error).toBe('directory_has_devices');
  });

  test('returns 409 when directory has children', async () => {
    // Create a parent directory
    const parentRes = await request(app)
      .post('/api/directories')
      .set('Authorization', `Bearer ${tokenAlice}`)
      .send({ name: 'Parent With Child' });
    const parentId = parentRes.body.id;

    // Create a child directory under it
    await request(app)
      .post('/api/directories')
      .set('Authorization', `Bearer ${tokenAlice}`)
      .send({ name: 'Child Dir', parent_id: parentId });

    // Try to delete parent — should 409
    const res = await request(app)
      .delete(`/api/directories/${parentId}`)
      .set('Authorization', `Bearer ${tokenAlice}`);
    expect(res.status).toBe(409);
    expect(res.body.error).toBe('directory_has_children');

    // Cleanup: delete child then parent
    const { rows: children } = await pool.query(
      "SELECT id FROM directories WHERE name = 'Child Dir' LIMIT 1"
    );
    await pool.query('DELETE FROM directories WHERE id = $1', [children[0].id]);
    await pool.query('DELETE FROM directories WHERE id = $1', [parentId]);
  });

  test('deletes an empty directory and returns 200', async () => {
    const res = await request(app)
      .delete(`/api/directories/${newDirId}`)
      .set('Authorization', `Bearer ${tokenAlice}`);
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
  });
});
