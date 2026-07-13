# GuDesk Phase D — Device Enrollment Design Spec

## Scope

Implement device enrollment flow:
- `POST /api/enrollment-tokens` — admin creates single-use enrollment token
- `GET /api/enrollment-tokens` — list org tokens
- `DELETE /api/enrollment-tokens/:id` — revoke token
- `POST /api/devices/enroll` — unauthenticated endpoint for device agent
- 8 integration tests (Jest + supertest)

## Database

New migration adds `enrollment_tokens` table:

```
id          uuid PRIMARY KEY DEFAULT gen_random_uuid()
org_id      uuid NOT NULL REFERENCES organizations ON DELETE CASCADE
created_by  uuid NOT NULL REFERENCES users
token_hash  varchar(64) NOT NULL UNIQUE   -- SHA-256 hex of plaintext token
expires_at  timestamptz NOT NULL
used_at     timestamptz                   -- NULL = unused, non-NULL = consumed
created_at  timestamptz NOT NULL DEFAULT now()
```

Indexes:
- `idx_enrollment_tokens_org` ON `(org_id)`
- `idx_enrollment_tokens_hash` ON `(token_hash)` — lookup on enroll

Token generation:
- Plaintext = `crypto.randomBytes(32).toString('hex')` (64 hex chars)
- Stored hash = `SHA-256(plaintext)` as hex string
- Plaintext returned to caller once only — never stored in DB

## File Structure

```
migrations/
  1752371900000_add-enrollment-tokens.js   # new table + indexes
src/routes/
  enrollmentTokens.js                      # POST/GET/DELETE /api/enrollment-tokens
  enroll.js                                # POST /api/devices/enroll (no auth middleware)
src/app.js                                 # mount 2 new routers only, no other changes
tests/
  enrollment.test.js                       # 8 integration tests
```

## Endpoints

### POST /api/enrollment-tokens

Requires: `scopeToOrg` + `requireRole('owner', 'admin')`

Request body:
```json
{ "expires_in_hours": 24 }
```
- `expires_in_hours` optional, default `24`, max `168` (7 days)

Flow:
1. Generate plaintext = `crypto.randomBytes(32).toString('hex')`
2. Compute `token_hash = SHA-256(plaintext)` as hex
3. `INSERT INTO enrollment_tokens (org_id, created_by, token_hash, expires_at)`
4. Return plaintext token — this is the only time it is available

Response `201`:
```json
{ "id": "<uuid>", "token": "<64-char hex>", "expires_at": "<ISO timestamp>" }
```

### GET /api/enrollment-tokens

Requires: `scopeToOrg`

Query: `SELECT id, created_by, expires_at, used_at FROM enrollment_tokens WHERE org_id = $1 ORDER BY created_at DESC`

Response `200`:
```json
[
  {
    "id": "<uuid>",
    "created_by": "<user_uuid>",
    "expires_at": "<ISO timestamp>",
    "used_at": "<ISO timestamp | null>",
    "is_expired": false
  }
]
```

`is_expired` computed in application: `expires_at < now()` — not stored in DB.

### DELETE /api/enrollment-tokens/:id

Requires: `scopeToOrg` + `requireRole('owner', 'admin')`

Flow:
1. `DELETE FROM enrollment_tokens WHERE id = $1 AND org_id = $2 RETURNING id`
2. 404 `{ error: 'not_found' }` if no row deleted

Response `200`:
```json
{ "ok": true }
```

### POST /api/devices/enroll

**No authentication required** — public endpoint for device agent.

Request body:
```json
{
  "token": "<64-char hex>",
  "hostname": "DESKTOP-ABC123",
  "os_type": "windows",
  "os_version": "11"
}
```
- `token` required
- `hostname` required
- `os_type` optional
- `os_version` optional

Flow:
1. Compute `token_hash = SHA-256(req.body.token)`
2. `SELECT id, org_id, expires_at, used_at FROM enrollment_tokens WHERE token_hash = $hash`
3. If not found → `401 { error: 'invalid_token' }`
4. If `used_at IS NOT NULL` → `401 { error: 'invalid_token' }`
5. If `expires_at <= now()` → `401 { error: 'invalid_token' }`
6. In a single transaction:
   - `INSERT INTO devices (org_id, device_uid, public_key, hostname, os_type, os_version, status) VALUES ($org_id, gen_random_uuid(), '', $hostname, $os_type, $os_version, 'offline') RETURNING id, device_uid, org_id`
   - `UPDATE enrollment_tokens SET used_at = now() WHERE id = $token_id`
7. Return device record

Response `201`:
```json
{ "device_id": "<uuid>", "device_uid": "<uuid>", "org_id": "<uuid>" }
```

Note: `public_key` stored as empty string at enrollment — populated in Phase E when device agent establishes WebSocket connection and completes key exchange.

## Security Notes

- `org_id` on enrolled device comes from `enrollment_tokens.org_id` — never from request body
- All three invalid-token cases (not found, used, expired) return identical `401 { error: 'invalid_token' }` — no information leakage
- Token plaintext never logged, never stored in DB
- Device INSERT and token `used_at` update in same transaction — no race condition where two agents use same token simultaneously
- `public_key` field required NOT NULL in schema — stored as `''` at enrollment, updated in Phase E

## Integration Tests

### tests/enrollment.test.js

| # | Test | Expected |
|---|------|----------|
| 1 | POST /api/enrollment-tokens — owner creates token | 201 + `{ id, token, expires_at }` |
| 2 | POST /api/enrollment-tokens — member role | 403 |
| 3 | GET /api/enrollment-tokens — list tokens | 200 + array with `is_expired` field |
| 4 | DELETE /api/enrollment-tokens/:id — revoke unused token | 200 `{ ok: true }` |
| 5 | POST /api/devices/enroll — valid token | 201 + `{ device_id, device_uid, org_id }` |
| 6 | POST /api/devices/enroll — invalid/unknown token | 401 `{ error: 'invalid_token' }` |
| 7 | POST /api/devices/enroll — expired token | 401 `{ error: 'invalid_token' }` |
| 8 | POST /api/devices/enroll — already used token | 401 `{ error: 'invalid_token' }` |

Test setup: seed tokens directly via `pool.query` for tests 7 and 8 (expired/used tokens cannot be created through the API cleanly).
