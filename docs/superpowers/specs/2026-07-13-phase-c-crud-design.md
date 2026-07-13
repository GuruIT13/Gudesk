# GuDesk Phase C — Directory/Device CRUD API Design Spec

## Scope

Implement CRUD endpoints for directories and devices:
- `GET/POST/PATCH/DELETE /api/directories`
- `GET/GET:id/PATCH/DELETE /api/devices`
- `requireRole` middleware for admin/owner-only operations
- 13 integration tests (Jest + supertest)

Deferred: `POST /api/devices/enroll` → Phase D

## File Structure

```
src/
  middleware/
    requireRole.js        # new — role IN ('owner','admin') check → 403
  routes/
    directories.js        # new — directory CRUD
    devices.js            # new — device CRUD
tests/
  directories.test.js     # new
  devices.test.js         # new
```

`src/app.js` — mount 2 new routers only, no other changes.

## Middleware

### requireRole

```
requireRole('admin', 'owner')
```

- Reads `req.role` (already injected by `scopeToOrg`)
- If role not in allowed list → 403 `{ error: 'forbidden' }`
- Must be placed after `scopeToOrg` in route chain

## Directories Endpoints

All endpoints require `scopeToOrg`. PATCH/DELETE additionally require `requireRole('admin','owner')`.

### GET /api/directories
- Query: `SELECT * FROM directories WHERE org_id = $orgId ORDER BY parent_id NULLS FIRST`
- Pass flat rows to `buildTree()` helper → return nested structure
- Response: `200 [ { id, name, parent_id, children: [...] } ]`

### POST /api/directories
- Body: `{ name: string, parent_id?: uuid }`
- If `parent_id` provided: verify `SELECT id FROM directories WHERE id=$parent_id AND org_id=$orgId` → 404 if not found
- INSERT directory
- Response: `201 { id, name, parent_id, org_id, created_at }`

### PATCH /api/directories/:id
- Body: `{ name?: string, parent_id?: uuid }`
- Verify `id + org_id` → 404 if not found
- If `parent_id` provided: verify belongs to same org → 404 if not
- UPDATE directory
- Response: `200 { id, name, parent_id, updated_at }`

### DELETE /api/directories/:id
- Verify `id + org_id` → 404 if not found
- Check `SELECT COUNT(*) FROM devices WHERE directory_id = $id` → 409 `{ error: 'directory_has_devices' }` if > 0
- Check `SELECT COUNT(*) FROM directories WHERE parent_id = $id` → 409 `{ error: 'directory_has_children' }` if > 0
- DELETE directory
- Response: `200 { ok: true }`

### buildTree() helper
- Pure function inside `directories.js`
- Input: flat array of rows with `{ id, parent_id, ... }`
- Output: nested array `[ { ...row, children: [...] } ]`
- Roots = rows where `parent_id IS NULL`

## Devices Endpoints

All endpoints require `scopeToOrg`. DELETE additionally requires `requireRole('admin','owner')`.

### GET /api/devices
- Query param: `directory_id` (optional)
- If provided: `WHERE org_id=$orgId AND directory_id=$directory_id`
- If not provided: `WHERE org_id=$orgId`
- Response: `200 [ { id, hostname, status, os_type, directory_id, last_seen_at } ]`

### GET /api/devices/:id
- `WHERE id=$id AND org_id=$orgId` → 404 if not found
- Response: `200 { id, hostname, status, os_type, os_version, directory_id, last_seen_at, last_ip, device_uid }`

### PATCH /api/devices/:id
- Body: `{ hostname?: string, directory_id?: uuid | null }`
- Verify device `id + org_id` → 404 if not found
- If `directory_id` provided (non-null): verify `SELECT id FROM directories WHERE id=$directory_id AND org_id=$orgId` → 404 if not
- UPDATE device
- Response: `200 { id, hostname, directory_id, updated_at }`

### DELETE /api/devices/:id
- Verify `id + org_id` → 404 if not found
- DELETE device (FK CASCADE removes remote_sessions automatically)
- Response: `200 { ok: true }`

## Integration Tests

### tests/directories.test.js

| # | Test | Expected |
|---|------|----------|
| 1 | GET /api/directories — valid token | 200 + nested tree array |
| 2 | POST /api/directories — create root dir | 201 + new dir object |
| 3 | POST /api/directories — parent_id from other org | 404 |
| 4 | PATCH /api/directories/:id — rename | 200 + updated name |
| 5 | PATCH /api/directories/:id — member role | 403 |
| 6 | DELETE /api/directories/:id — has devices | 409 directory_has_devices |
| 7 | DELETE /api/directories/:id — empty dir | 200 |

### tests/devices.test.js

| # | Test | Expected |
|---|------|----------|
| 8 | GET /api/devices — list all in org | 200 + array |
| 9 | GET /api/devices?directory_id=xxx — filtered | 200 + filtered array |
| 10 | GET /api/devices/:id — cross-org device | 404 |
| 11 | PATCH /api/devices/:id — move to different directory | 200 |
| 12 | DELETE /api/devices/:id — member role | 403 |
| 13 | DELETE /api/devices/:id — admin role | 200 |

## Security Notes

- All queries include `AND org_id = $req.orgId` — no cross-org leakage
- 404 (not 403) when resource exists in another org — avoids id enumeration
- `requireRole` reads from JWT payload via `req.role` — not from request body
- `directory_id` cross-org check prevents moving device into another org's directory
