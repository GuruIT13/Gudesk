# Phase D — Device Enrollment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement device enrollment flow — admin creates single-use token, device agent POSTs to unauthenticated endpoint to register itself.

**Architecture:** Three new files: a migration adding `enrollment_tokens` table, a JWT-authenticated router for token management (`enrollmentTokens.js`), and an unauthenticated router for device agent enrollment (`enroll.js`). `app.js` mounts both routers. Token plaintext is generated with `crypto.randomBytes`, stored only as SHA-256 hash. Device INSERT and token `used_at` update happen in a single DB transaction.

**Tech Stack:** Node.js, Express, node-postgres (`pg`), Jest + supertest, node built-in `crypto` module (no new packages needed)

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `migrations/1752371900000_add-enrollment-tokens.js` | Create | Add `enrollment_tokens` table + indexes |
| `src/routes/enrollmentTokens.js` | Create | POST/GET/DELETE `/api/enrollment-tokens` (JWT required) |
| `src/routes/enroll.js` | Create | POST `/api/devices/enroll` (no auth) |
| `src/app.js` | Modify | Mount 2 new routers |
| `tests/enrollment.test.js` | Create | 8 integration tests |

---

### Task 1: Migration — `enrollment_tokens` table

**Files:**
- Create: `migrations/1752371900000_add-enrollment-tokens.js`

**Context:** This project uses `node-pg-migrate`. Migration files export `up` and `down` functions receiving a `pgm` builder. See `migrations/1752371800000_initial-schema.js` for the exact pattern.

- [ ] **Step 1: Write the migration file**

```js
// migrations/1752371900000_add-enrollment-tokens.js
exports.up = (pgm) => {
  pgm.createTable('enrollment_tokens', {
    id: {
      type: 'uuid',
      primaryKey: true,
      default: pgm.func('gen_random_uuid()'),
    },
    org_id: {
      type: 'uuid',
      notNull: true,
      references: '"organizations"',
      onDelete: 'CASCADE',
    },
    created_by: {
      type: 'uuid',
      notNull: true,
      references: '"users"',
    },
    token_hash: { type: 'varchar(64)', notNull: true, unique: true },
    expires_at: { type: 'timestamptz', notNull: true },
    used_at: { type: 'timestamptz' },
    created_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
  });

  pgm.createIndex('enrollment_tokens', ['org_id'], { name: 'idx_enrollment_tokens_org' });
  pgm.createIndex('enrollment_tokens', ['token_hash'], { name: 'idx_enrollment_tokens_hash' });
};

exports.down = (pgm) => {
  pgm.dropTable('enrollment_tokens');
};
```

- [ ] **Step 2: Run the migration**

```bash
npm run migrate up
```

Expected output: `Migrating "1752371900000_add-enrollment-tokens"`

- [ ] **Step 3: Verify table exists**

```bash
$env:PGPASSWORD='postgres'; & "C:\Program Files\PostgreSQL\17\bin\psql.exe" -U postgres -d gudesk -c "\d enrollment_tokens"
```

Expected: table with columns `id, org_id, created_by, token_hash, expires_at, used_at, created_at`

- [ ] **Step 4: Commit**

```bash
git add migrations/1752371900000_add-enrollment-tokens.js
git commit -m "feat: add enrollment_tokens migration"
```

---

### Task 2: Token management router + tests

**Files:**
- Create: `src/routes/enrollmentTokens.js`
- Create: `tests/enrollment.test.js` (partial — tests 1–4 only)
- Modify: `src/app.js`

**Context:** Follow the pattern in `src/routes/devices.js` — `require` pool, scopeToOrg, requireRole at top; use `express.Router()`. `src/middleware/scopeToOrg.js` injects `req.userId`, `req.orgId`, `req.role` from JWT. `requireRole('owner', 'admin')` returns 403 if role not in list.

Token generation uses Node built-in `crypto` — no new packages needed:
```js
const crypto = require('crypto');
const plaintext = crypto.randomBytes(32).toString('hex'); // 64-char hex
const token_hash = crypto.createHash('sha256').update(plaintext).digest('hex');
```

- [ ] **Step 1: Write failing tests 1–4**

```js
// tests/enrollment.test.js
const request = require('supertest');
const app = require('../src/app');
const pool = require('../src/db');

let tokenAlice;  // Org A owner
let tokenBob;    // Org A member
let orgAId;
let createdTokenId;

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
    createdTokenId = res.body.id;
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
    expect(res.body[0]).toHaveProperty('is_expired');
    expect(res.body[0]).toHaveProperty('expires_at');
    expect(res.body[0]).toHaveProperty('created_by');
  });
});

describe('DELETE /api/enrollment-tokens/:id', () => {
  test('revokes unused token — returns 200', async () => {
    // Create a fresh token to delete (don't delete createdTokenId — tests 5/8 need it)
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
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
npx jest tests/enrollment.test.js --runInBand 2>&1 | head -30
```

Expected: FAIL — `Cannot find module '../src/routes/enrollmentTokens'` or 404 errors

- [ ] **Step 3: Write `src/routes/enrollmentTokens.js`**

```js
const express = require('express');
const crypto = require('crypto');
const pool = require('../db');
const scopeToOrg = require('../middleware/scopeToOrg');
const requireRole = require('../middleware/requireRole');

const router = express.Router();

// POST /api/enrollment-tokens
router.post('/', scopeToOrg, requireRole('owner', 'admin'), async (req, res) => {
  try {
    const expiresInHours = Math.min(Number(req.body.expires_in_hours) || 24, 168);
    const plaintext = crypto.randomBytes(32).toString('hex');
    const token_hash = crypto.createHash('sha256').update(plaintext).digest('hex');
    const expiresAt = new Date(Date.now() + expiresInHours * 60 * 60 * 1000);

    const { rows } = await pool.query(
      `INSERT INTO enrollment_tokens (org_id, created_by, token_hash, expires_at)
       VALUES ($1, $2, $3, $4)
       RETURNING id, expires_at`,
      [req.orgId, req.userId, token_hash, expiresAt]
    );
    res.status(201).json({ id: rows[0].id, token: plaintext, expires_at: rows[0].expires_at });
  } catch (err) {
    res.status(500).json({ error: 'internal_error' });
  }
});

// GET /api/enrollment-tokens
router.get('/', scopeToOrg, async (req, res) => {
  try {
    const { rows } = await pool.query(
      `SELECT id, created_by, expires_at, used_at
       FROM enrollment_tokens WHERE org_id = $1 ORDER BY created_at DESC`,
      [req.orgId]
    );
    const now = new Date();
    res.json(rows.map(r => ({ ...r, is_expired: new Date(r.expires_at) < now })));
  } catch (err) {
    res.status(500).json({ error: 'internal_error' });
  }
});

// DELETE /api/enrollment-tokens/:id
router.delete('/:id', scopeToOrg, requireRole('owner', 'admin'), async (req, res) => {
  try {
    const { rows } = await pool.query(
      'DELETE FROM enrollment_tokens WHERE id = $1 AND org_id = $2 RETURNING id',
      [req.params.id, req.orgId]
    );
    if (!rows.length) return res.status(404).json({ error: 'not_found' });
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: 'internal_error' });
  }
});

module.exports = router;
```

- [ ] **Step 4: Mount router in `src/app.js`**

Add after line `const devicesRouter = require('./routes/devices');`:
```js
const enrollmentTokensRouter = require('./routes/enrollmentTokens');
```

Add after `app.use('/api/devices', devicesRouter);`:
```js
app.use('/api/enrollment-tokens', enrollmentTokensRouter);
```

Full updated `src/app.js`:
```js
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const express = require('express');
const scopeToOrg = require('./middleware/scopeToOrg');
const authRouter = require('./routes/auth');
const directoriesRouter = require('./routes/directories');
const devicesRouter = require('./routes/devices');
const enrollmentTokensRouter = require('./routes/enrollmentTokens');
const enrollRouter = require('./routes/enroll');

const app = express();
app.use(express.json());

app.use('/api/auth', authRouter);
app.use('/api/directories', directoriesRouter);
app.use('/api/devices', devicesRouter);
app.use('/api/enrollment-tokens', enrollmentTokensRouter);
app.use('/api/devices/enroll', enrollRouter);

app.get('/api/ping', scopeToOrg, (req, res) => {
  res.json({ ok: true, userId: req.userId, orgId: req.orgId });
});

module.exports = app;
```

**Important:** `enrollRouter` is mounted at `/api/devices/enroll` — this must be mounted BEFORE `devicesRouter` would handle `/:id` — but since it's a separate router at a distinct path, Express routes it correctly. Create `src/routes/enroll.js` as a stub now so app.js doesn't crash:

```js
// src/routes/enroll.js  — STUB, completed in Task 3
const express = require('express');
const router = express.Router();
module.exports = router;
```

- [ ] **Step 5: Run tests 1–4 to confirm they pass**

```bash
npx jest tests/enrollment.test.js --runInBand 2>&1
```

Expected: 4 tests pass (POST 201, POST 403, GET 200, DELETE 200)

- [ ] **Step 6: Run full suite to confirm no regressions**

```bash
npm test
```

Expected: all tests pass (27 existing + 4 new = 31 total)

- [ ] **Step 7: Commit**

```bash
git add src/routes/enrollmentTokens.js src/routes/enroll.js src/app.js tests/enrollment.test.js
git commit -m "feat: add enrollment token management endpoints"
```

---

### Task 3: Enroll endpoint + remaining tests

**Files:**
- Modify: `src/routes/enroll.js` (replace stub)
- Modify: `tests/enrollment.test.js` (add tests 5–8)

**Context:** `POST /api/devices/enroll` has NO auth middleware — it's a public endpoint. `org_id` comes exclusively from the token record found in DB. The device INSERT and token `used_at` update must happen in a single DB transaction using `pool.connect()` → `client.query('BEGIN')` pattern.

The SHA-256 hash of the incoming plaintext token must match what was stored at creation time:
```js
const token_hash = crypto.createHash('sha256').update(req.body.token).digest('hex');
```

- [ ] **Step 1: Add failing tests 5–8 to `tests/enrollment.test.js`**

Add these describe blocks at the end of `tests/enrollment.test.js`, after the existing DELETE block. `createdTokenId` is set in test 1 and holds a valid unused token's id. `validToken` is the plaintext returned from test 1 — store it too.

First update the POST test to also save `validToken`:

Replace the POST test body `createdTokenId = res.body.id;` line with:
```js
    createdTokenId = res.body.id;
    validToken = res.body.token;
```

And add `let validToken;` to the top-level variable declarations alongside `let createdTokenId;`.

Then add these new describe blocks:

```js
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
  });

  test('invalid/unknown token returns 401', async () => {
    const res = await request(app)
      .post('/api/devices/enroll')
      .send({ token: 'a'.repeat(64), hostname: 'FAKE-DEVICE' });
    expect(res.status).toBe(401);
    expect(res.body.error).toBe('invalid_token');
  });

  test('expired token returns 401', async () => {
    // Insert an already-expired token directly via pool
    const expiredHash = require('crypto')
      .createHash('sha256').update('expired_plaintext_token_x'.padEnd(64, '0')).digest('hex');
    const { rows: orgRows } = await pool.query(
      "SELECT id FROM organizations WHERE slug = 'alpha-corp' LIMIT 1"
    );
    const { rows: userRows } = await pool.query(
      "SELECT id FROM users WHERE email = 'alice@alpha.com' LIMIT 1"
    );
    await pool.query(
      `INSERT INTO enrollment_tokens (org_id, created_by, token_hash, expires_at)
       VALUES ($1, $2, $3, now() - interval '1 hour')`,
      [orgRows[0].id, userRows[0].id, expiredHash]
    );
    const res = await request(app)
      .post('/api/devices/enroll')
      .send({ token: 'expired_plaintext_token_x'.padEnd(64, '0'), hostname: 'FAKE' });
    expect(res.status).toBe(401);
    expect(res.body.error).toBe('invalid_token');
  });

  test('already used token returns 401', async () => {
    // Insert a used token directly via pool
    const usedHash = require('crypto')
      .createHash('sha256').update('used_plaintext_token_xx'.padEnd(64, '0')).digest('hex');
    const { rows: orgRows } = await pool.query(
      "SELECT id FROM organizations WHERE slug = 'alpha-corp' LIMIT 1"
    );
    const { rows: userRows } = await pool.query(
      "SELECT id FROM users WHERE email = 'alice@alpha.com' LIMIT 1"
    );
    await pool.query(
      `INSERT INTO enrollment_tokens (org_id, created_by, token_hash, expires_at, used_at)
       VALUES ($1, $2, $3, now() + interval '1 hour', now() - interval '5 minutes')`,
      [orgRows[0].id, userRows[0].id, usedHash]
    );
    const res = await request(app)
      .post('/api/devices/enroll')
      .send({ token: 'used_plaintext_token_xx'.padEnd(64, '0'), hostname: 'FAKE' });
    expect(res.status).toBe(401);
    expect(res.body.error).toBe('invalid_token');
  });
});
```

- [ ] **Step 2: Run tests to confirm 5–8 fail**

```bash
npx jest tests/enrollment.test.js --runInBand 2>&1 | tail -20
```

Expected: tests 5–8 fail (enroll route is still a stub returning nothing)

- [ ] **Step 3: Implement `src/routes/enroll.js`**

```js
const express = require('express');
const crypto = require('crypto');
const pool = require('../db');

const router = express.Router();

// POST /api/devices/enroll  — no auth required
router.post('/', async (req, res) => {
  const { token, hostname, os_type, os_version } = req.body;
  if (!token || !hostname) {
    return res.status(400).json({ error: 'token_and_hostname_required' });
  }

  const token_hash = crypto.createHash('sha256').update(token).digest('hex');

  try {
    const { rows } = await pool.query(
      `SELECT id, org_id, expires_at, used_at
       FROM enrollment_tokens WHERE token_hash = $1`,
      [token_hash]
    );

    if (!rows.length) return res.status(401).json({ error: 'invalid_token' });
    const record = rows[0];
    if (record.used_at !== null) return res.status(401).json({ error: 'invalid_token' });
    if (new Date(record.expires_at) <= new Date()) return res.status(401).json({ error: 'invalid_token' });

    const client = await pool.connect();
    try {
      await client.query('BEGIN');

      const { rows: deviceRows } = await client.query(
        `INSERT INTO devices (org_id, device_uid, public_key, hostname, os_type, os_version, status)
         VALUES ($1, gen_random_uuid(), '', $2, $3, $4, 'offline')
         RETURNING id, device_uid, org_id`,
        [record.org_id, hostname, os_type || null, os_version || null]
      );

      await client.query(
        'UPDATE enrollment_tokens SET used_at = now() WHERE id = $1',
        [record.id]
      );

      await client.query('COMMIT');
      res.status(201).json({
        device_id: deviceRows[0].id,
        device_uid: deviceRows[0].device_uid,
        org_id: deviceRows[0].org_id,
      });
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  } catch (err) {
    res.status(500).json({ error: 'internal_error' });
  }
});

module.exports = router;
```

- [ ] **Step 4: Run tests 5–8 to confirm they pass**

```bash
npx jest tests/enrollment.test.js --runInBand 2>&1
```

Expected: all 8 tests pass

- [ ] **Step 5: Run full suite to confirm no regressions**

```bash
npm test
```

Expected: all tests pass (27 existing + 8 new = 35 total)

- [ ] **Step 6: Commit**

```bash
git add src/routes/enroll.js tests/enrollment.test.js
git commit -m "feat: add device enrollment endpoint and integration tests"
```

---

## Spec Coverage Self-Check

| Spec requirement | Task |
|-----------------|------|
| `enrollment_tokens` table + indexes | Task 1 |
| `POST /api/enrollment-tokens` — 201 + plaintext token | Task 2 |
| `GET /api/enrollment-tokens` — list with `is_expired` | Task 2 |
| `DELETE /api/enrollment-tokens/:id` — 200/404 | Task 2 |
| `POST /api/devices/enroll` — valid token → 201 | Task 3 |
| invalid/expired/used token → 401 `invalid_token` | Task 3 |
| Transaction: device INSERT + token `used_at` atomic | Task 3 |
| `org_id` from token record, never from request body | Task 3 |
| 8 integration tests | Tasks 2+3 |
| Token plaintext never stored in DB | Task 2 |
