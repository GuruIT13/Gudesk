# GuDesk Phase B — Auth + JWT + scopeToOrg Design Spec

## Scope

Implement authentication layer for the GuDesk Node.js API:
- `POST /api/auth/login` — password verify + JWT issue
- `scopeToOrg` middleware — JWT decode + org scoping
- Integration tests: Jest + supertest, including cross-org 404

Deferred: `POST /api/auth/switch-org`

## Stack

- Framework: Express.js
- Password hashing: `argon2` (argon2id)
- JWT: `jsonwebtoken`
- Test: Jest + supertest
- DB: existing `pg` Pool (PostgreSQL 17)

## File Structure

```
src/
  app.js              # Express app export (no listen — for supertest)
  server.js           # import app + listen
  db.js               # pg Pool singleton
  middleware/
    scopeToOrg.js     # decode JWT → inject req.orgId, req.userId, req.role
  routes/
    auth.js           # POST /api/auth/login
tests/
  auth.test.js        # Jest + supertest
```

## Auth Flow

### POST /api/auth/login

Request: `{ email: string, password: string }`

1. Query `users` by email — if not found → 401 `{ error: 'invalid_credentials' }`
2. `argon2.verify(user.password_hash, password)` — if false → 401 `{ error: 'invalid_credentials' }`
3. Query `memberships` for first org this user belongs to (ordered by `created_at ASC`)
4. Sign JWT: `{ sub: user_id, org_id, role }`, expires in 8h, signed with `JWT_SECRET` from env
5. Return `{ token, user: { id, email, display_name }, org: { id, name, slug } }`

Error responses use the same `invalid_credentials` message for both "not found" and "wrong password" — avoids user enumeration.

### scopeToOrg Middleware

- Read `Authorization: Bearer <token>` header — if missing → 401
- `jwt.verify(token, JWT_SECRET)` — if invalid or expired → 401
- Inject `req.userId`, `req.orgId`, `req.role` from token payload
- Never read org identity from `req.body` or `req.query`

## Environment Variables

```
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/gudesk
JWT_SECRET=<random 32+ char string>
PORT=3000
```

## Integration Tests

All tests use supertest against the Express app. DB state comes from the existing seed (Org A / Org B isolation).

| # | Test | Expected |
|---|------|----------|
| 1 | POST /login valid credentials | 200 + JWT |
| 2 | POST /login wrong password | 401 invalid_credentials |
| 3 | POST /login unknown email | 401 invalid_credentials |
| 4 | Authenticated route — no token | 401 |
| 5 | Authenticated route — invalid/expired token | 401 |
| 6 | Authenticated route — valid token | 200 + own org data |
| 7 | Cross-org resource access (Org A token → Org B resource) | 404 |

Test 7 is the critical security boundary: response must be 404, not 403, to avoid leaking resource existence across orgs.

## Security Notes

- JWT payload carries `org_id` and `role` — no DB lookup per request (stateless)
- All resource queries must include `AND org_id = $req.orgId` — enforced by convention, verified by test 7
- 401 responses never reveal whether email exists
