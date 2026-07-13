# Phase B — Auth + JWT + scopeToOrg Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement Express.js auth layer with JWT login, scopeToOrg middleware, and 7 integration tests including cross-org 404.

**Architecture:** Single Express app split across `app.js` (export for supertest) and `server.js` (listen). DB is a `pg` Pool singleton in `db.js`. Auth route and middleware are separate files under `src/routes/` and `src/middleware/`.

**Tech Stack:** Express.js, argon2 (argon2id), jsonwebtoken, pg, Jest, supertest, dotenv

---

### Task 1: Install dependencies

**Files:**
- Modify: `package.json`

- [ ] **Step 1: Install runtime deps**

```bash
cd "C:\Users\Guruit\Documents\Gudesk"
npm install express argon2 jsonwebtoken
```

Expected output: `added N packages`

- [ ] **Step 2: Install dev deps**

```bash
npm install --save-dev jest supertest
```

Expected output: `added N packages`

- [ ] **Step 3: Update test script in package.json**

Open `package.json`, replace the `"test"` script line:

```json
"test": "jest --runInBand"
```

`--runInBand` runs tests serially — required because tests share a real DB.

Also add a `"start"` script:

```json
"start": "node src/server.js"
```

- [ ] **Step 4: Add JWT_SECRET to .env**

Open `.env`, append:

```
JWT_SECRET=gudesk_dev_secret_change_in_production_32chars
PORT=3000
```

- [ ] **Step 5: Commit**

```bash
git add package.json package-lock.json .env
git commit -m "chore: install express, argon2, jsonwebtoken, jest, supertest"
```

---

### Task 2: DB singleton

**Files:**
- Create: `src/db.js`

- [ ] **Step 1: Create src/ directory and db.js**

```bash
mkdir -p "C:\Users\Guruit\Documents\Gudesk\src"
```

Create `src/db.js`:

```js
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const { Pool } = require('pg');

const pool = new Pool({ connectionString: process.env.DATABASE_URL });

module.exports = pool;
```

- [ ] **Step 2: Verify pool connects**

```bash
node -e "const p = require('./src/db'); p.query('SELECT 1').then(() => { console.log('DB OK'); p.end(); }).catch(e => { console.error(e.message); p.end(); })"
```

Expected output: `DB OK`

- [ ] **Step 3: Commit**

```bash
git add src/db.js
git commit -m "feat: add pg pool singleton"
```

---

### Task 3: scopeToOrg middleware

**Files:**
- Create: `src/middleware/scopeToOrg.js`

- [ ] **Step 1: Write the failing test first**

Create `tests/auth.test.js` with only the middleware tests (tests 4 and 5 from spec):

```js
const request = require('supertest');
const app = require('../src/app');
const pool = require('../src/db');

afterAll(async () => {
  await pool.end();
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
```

- [ ] **Step 2: Create src/middleware/ directory**

```bash
mkdir -p "C:\Users\Guruit\Documents\Gudesk\src\middleware"
```

- [ ] **Step 3: Create scopeToOrg.js**

Create `src/middleware/scopeToOrg.js`:

```js
require('dotenv').config({ path: require('path').join(__dirname, '..', '..', '.env') });
const jwt = require('jsonwebtoken');

function scopeToOrg(req, res, next) {
  const header = req.headers['authorization'];
  if (!header || !header.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'unauthorized' });
  }
  const token = header.slice(7);
  try {
    const payload = jwt.verify(token, process.env.JWT_SECRET);
    req.userId = payload.sub;
    req.orgId = payload.org_id;
    req.role = payload.role;
    next();
  } catch {
    return res.status(401).json({ error: 'unauthorized' });
  }
}

module.exports = scopeToOrg;
```

- [ ] **Step 4: Create src/app.js with /api/ping route**

Create `src/app.js`:

```js
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const express = require('express');
const scopeToOrg = require('./middleware/scopeToOrg');

const app = express();
app.use(express.json());

// health check protected by scopeToOrg — used by middleware tests
app.get('/api/ping', scopeToOrg, (req, res) => {
  res.json({ ok: true, userId: req.userId, orgId: req.orgId });
});

module.exports = app;
```

- [ ] **Step 5: Run middleware tests — expect PASS**

```bash
npx jest tests/auth.test.js --runInBand -t "scopeToOrg" 2>&1
```

Expected: both tests PASS

- [ ] **Step 6: Commit**

```bash
git add src/middleware/scopeToOrg.js src/app.js tests/auth.test.js
git commit -m "feat: add scopeToOrg middleware + /api/ping test route"
```

---

### Task 4: POST /api/auth/login route

**Files:**
- Create: `src/routes/auth.js`
- Modify: `src/app.js`

- [ ] **Step 1: Write failing tests for login**

Append to `tests/auth.test.js` (inside the file, after the existing describe block):

```js
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
```

- [ ] **Step 2: Run tests — expect FAIL**

```bash
npx jest tests/auth.test.js --runInBand -t "POST /api/auth/login" 2>&1
```

Expected: FAIL (route not defined yet)

- [ ] **Step 3: Update seed to use real argon2id hashes**

The existing seed uses fake `$argon2id$fake$hash` strings — `argon2.verify()` will fail against them. Re-seed with real hashes.

Create `seeds/hash-gen.js`:

```js
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const argon2 = require('argon2');

async function main() {
  const passwords = {
    'alice@alpha.com': 'plaintext_alice',
    'bob@alpha.com': 'plaintext_bob',
    'carol@beta.com': 'plaintext_carol',
    'dave@beta.com': 'plaintext_dave',
  };
  for (const [email, pw] of Object.entries(passwords)) {
    const hash = await argon2.hash(pw, { type: argon2.argon2id });
    console.log(`${email}: ${hash}`);
  }
}
main();
```

Run it:

```bash
node seeds/hash-gen.js
```

Copy the 4 hashes — you will need them in the next step.

- [ ] **Step 4: Update seed.js with real hashes**

Open `seeds/seed.js`. Replace the `INSERT INTO users` block with the real hashes from the previous step:

```js
const { rows: users } = await client.query(`
  INSERT INTO users (email, password_hash, display_name) VALUES
    ('alice@alpha.com',   '<hash_for_alice>',  'Org A - Alice'),
    ('bob@alpha.com',     '<hash_for_bob>',    'Org A - Bob'),
    ('carol@beta.com',    '<hash_for_carol>',  'Org B - Carol'),
    ('dave@beta.com',     '<hash_for_dave>',   'Org B - Dave')
  RETURNING id, display_name
`);
```

Replace `<hash_for_*>` with actual hash strings from Step 3.

- [ ] **Step 5: Re-run seed with real hashes**

```bash
# truncate existing seed data first
$env:PGPASSWORD='postgres'; & "C:\Program Files\PostgreSQL\17\bin\psql.exe" -U postgres -d gudesk -c "TRUNCATE audit_logs, remote_sessions, devices, directories, memberships, users, organizations RESTART IDENTITY CASCADE;"

npm run seed
```

Expected: `Seed completed successfully.`

- [ ] **Step 6: Create src/routes/ directory and auth.js**

```bash
mkdir -p "C:\Users\Guruit\Documents\Gudesk\src\routes"
```

Create `src/routes/auth.js`:

```js
const express = require('express');
const argon2 = require('argon2');
const jwt = require('jsonwebtoken');
const pool = require('../db');

const router = express.Router();

router.post('/login', async (req, res) => {
  const { email, password } = req.body;
  if (!email || !password) {
    return res.status(401).json({ error: 'invalid_credentials' });
  }

  try {
    const { rows: users } = await pool.query(
      'SELECT id, email, password_hash, display_name FROM users WHERE email = $1',
      [email]
    );
    if (!users.length) {
      return res.status(401).json({ error: 'invalid_credentials' });
    }
    const user = users[0];

    const valid = await argon2.verify(user.password_hash, password);
    if (!valid) {
      return res.status(401).json({ error: 'invalid_credentials' });
    }

    const { rows: memberships } = await pool.query(
      `SELECT m.role, o.id AS org_id, o.name, o.slug
       FROM memberships m
       JOIN organizations o ON o.id = m.org_id
       WHERE m.user_id = $1
       ORDER BY m.created_at ASC
       LIMIT 1`,
      [user.id]
    );
    if (!memberships.length) {
      return res.status(401).json({ error: 'invalid_credentials' });
    }
    const membership = memberships[0];

    const token = jwt.sign(
      { sub: user.id, org_id: membership.org_id, role: membership.role },
      process.env.JWT_SECRET,
      { expiresIn: '8h' }
    );

    res.json({
      token,
      user: { id: user.id, email: user.email, display_name: user.display_name },
      org: { id: membership.org_id, name: membership.name, slug: membership.slug },
    });
  } catch (err) {
    console.error('Login error:', err.message);
    res.status(500).json({ error: 'internal_error' });
  }
});

module.exports = router;
```

- [ ] **Step 7: Wire auth route into app.js**

Open `src/app.js`, add after `app.use(express.json())`:

```js
const authRouter = require('./routes/auth');
app.use('/api/auth', authRouter);
```

Full `src/app.js` should look like:

```js
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const express = require('express');
const scopeToOrg = require('./middleware/scopeToOrg');
const authRouter = require('./routes/auth');

const app = express();
app.use(express.json());

app.use('/api/auth', authRouter);

app.get('/api/ping', scopeToOrg, (req, res) => {
  res.json({ ok: true, userId: req.userId, orgId: req.orgId });
});

module.exports = app;
```

- [ ] **Step 8: Run login tests — expect PASS**

```bash
npx jest tests/auth.test.js --runInBand -t "POST /api/auth/login" 2>&1
```

Expected: all 3 login tests PASS

- [ ] **Step 9: Commit**

```bash
git add src/routes/auth.js src/app.js seeds/seed.js seeds/hash-gen.js
git commit -m "feat: implement POST /api/auth/login with argon2id + JWT"
```

---

### Task 5: Authenticated route tests + cross-org 404

**Files:**
- Modify: `tests/auth.test.js`
- Modify: `src/app.js` (add `/api/devices/:id` test route)

- [ ] **Step 1: Add /api/devices/:id route to app.js for testing**

This is a minimal route used only to verify scopeToOrg + cross-org 404 behavior. Real device CRUD comes in Phase C.

Open `src/app.js`, add before `module.exports = app`:

```js
const pool = require('./db');

app.get('/api/devices/:id', scopeToOrg, async (req, res) => {
  const { rows } = await pool.query(
    'SELECT id, hostname, status FROM devices WHERE id = $1 AND org_id = $2',
    [req.params.id, req.orgId]
  );
  if (!rows.length) return res.status(404).json({ error: 'not_found' });
  res.json(rows[0]);
});
```

Full `src/app.js`:

```js
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const express = require('express');
const scopeToOrg = require('./middleware/scopeToOrg');
const authRouter = require('./routes/auth');
const pool = require('./db');

const app = express();
app.use(express.json());

app.use('/api/auth', authRouter);

app.get('/api/ping', scopeToOrg, (req, res) => {
  res.json({ ok: true, userId: req.userId, orgId: req.orgId });
});

app.get('/api/devices/:id', scopeToOrg, async (req, res) => {
  const { rows } = await pool.query(
    'SELECT id, hostname, status FROM devices WHERE id = $1 AND org_id = $2',
    [req.params.id, req.orgId]
  );
  if (!rows.length) return res.status(404).json({ error: 'not_found' });
  res.json(rows[0]);
});

module.exports = app;
```

- [ ] **Step 2: Write failing tests for authenticated routes + cross-org 404**

Append to `tests/auth.test.js`:

```js
const jwt = require('jsonwebtoken');
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });

describe('Authenticated routes + cross-org isolation', () => {
  let tokenOrgA;
  let tokenOrgB;
  let deviceIdOrgA;
  let deviceIdOrgB;

  beforeAll(async () => {
    // Login as alice (Org A) to get token
    const resA = await request(app)
      .post('/api/auth/login')
      .send({ email: 'alice@alpha.com', password: 'plaintext_alice' });
    tokenOrgA = resA.body.token;

    // Login as carol (Org B) to get token
    const resB = await request(app)
      .post('/api/auth/login')
      .send({ email: 'carol@beta.com', password: 'plaintext_carol' });
    tokenOrgB = resB.body.token;

    // Fetch a device from Org A
    const { rows: devicesA } = await pool.query(
      "SELECT id FROM devices WHERE hostname = 'Org A - Device 1' LIMIT 1"
    );
    deviceIdOrgA = devicesA[0].id;

    // Fetch a device from Org B
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
```

- [ ] **Step 3: Run all tests — expect PASS**

```bash
npx jest tests/auth.test.js --runInBand 2>&1
```

Expected: all 7 tests PASS. Confirm output shows:
```
✓ returns 401 when no Authorization header
✓ returns 401 when token is invalid
✓ returns 200 + JWT for valid credentials
✓ returns 401 for wrong password
✓ returns 401 for unknown email
✓ returns 401 when no token provided
✓ returns 401 when token is invalid
✓ returns 200 with valid token on /api/ping
✓ Org A token can access Org A device
✓ cross-org: Org A token gets 404 when accessing Org B device
```

- [ ] **Step 4: Commit**

```bash
git add tests/auth.test.js src/app.js
git commit -m "test: add authenticated route + cross-org 404 integration tests"
```

---

### Task 6: Create server.js + final wiring

**Files:**
- Create: `src/server.js`

- [ ] **Step 1: Create server.js**

Create `src/server.js`:

```js
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const app = require('./app');

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`GuDesk API listening on port ${PORT}`);
});
```

- [ ] **Step 2: Verify server starts**

```bash
node src/server.js
```

Expected output: `GuDesk API listening on port 3000`

Press Ctrl+C to stop.

- [ ] **Step 3: Run full test suite one final time**

```bash
npm test 2>&1
```

Expected: all tests PASS, 0 failures.

- [ ] **Step 4: Commit**

```bash
git add src/server.js
git commit -m "feat: add server.js entry point — Phase B complete"
```
