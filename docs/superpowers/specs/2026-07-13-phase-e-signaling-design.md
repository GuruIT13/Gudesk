# GuDesk Phase E — WebSocket Signaling Server Design Spec

## Scope

Implement a WebSocket signaling server for WebRTC peer connection setup:
- Attach `ws` WebSocket server to existing Express HTTP server (same port 3000)
- Room-based routing: `device_id` is the room key
- JWT auth for controllers, `device_uid` lookup for device agents
- Session lifecycle: INSERT `remote_sessions` on room full, UPDATE `ended_at` on disconnect
- 10 integration tests (Jest + `ws` client)

Deferred: TURN relay, device JWT auth (device uses `device_uid` directly for now)

## Architecture

`ws` library attaches to the same `http.Server` instance that Express uses. `server.js` creates an explicit `http.Server`, passes it to both Express and the signaling module.

In-memory room map (process-scoped, resets on restart):
```
rooms: Map<device_id, { device: WebSocket | null, controller: WebSocket | null, sessionId: string | null }>
```

Connection URL patterns:
- **Device agent:** `ws://host/signal?device_uid=<uid>`
- **Controller:** `ws://host/signal?token=<jwt>&device_id=<id>`

Server distinguishes clients by presence of `device_uid` vs `token` query params.

## File Structure

```
src/
  signaling.js      # new — WebSocket server factory, room map, auth, routing, session lifecycle
src/server.js       # modify — create http.Server explicitly, pass to signaling.js
tests/
  signaling.test.js # new — 10 integration tests using ws client
package.json        # add ws dependency
```

No changes to `src/app.js`.

## Connection Flow

### Device Agent

1. Parse `device_uid` from query string → 400/close if missing
2. `SELECT id, org_id FROM devices WHERE device_uid = $1` → close with `device_not_found` if not found
3. Register `rooms.get(device_id).device = ws`
4. If controller already in room → send `{ type: 'peer-joined' }` to controller
5. On message → forward to controller (if present)
6. On close → set `rooms.get(device_id).device = null`, send `{ type: 'peer-left' }` to controller (if present), UPDATE `remote_sessions SET ended_at = now()` if `sessionId` set

### Controller (Flutter app)

1. Parse `token` + `device_id` from query string → close if missing
2. Verify JWT → close with `unauthorized` if invalid
3. `SELECT id, org_id FROM devices WHERE id = $1 AND org_id = $2` → close with `unauthorized` if not found (404 semantics: avoids id enumeration)
4. Check room: if `controller` slot already occupied → close with `device_busy`
5. Register `rooms.get(device_id).controller = ws`
6. INSERT `remote_sessions (org_id, device_id, controller_id, connection_mode)` VALUES `($orgId, $deviceId, $userId, 'p2p')` → store `sessionId` in room
7. If device already in room → send `{ type: 'peer-joined' }` to device
8. On message:
   - `{ type: 'session-end' }` → UPDATE `remote_sessions SET ended_at = now(), end_reason = 'user'`, send `{ type: 'session-end' }` to device, close both
   - Any other message → forward to device (if present)
9. On close → set `rooms.get(device_id).controller = null`, send `{ type: 'peer-left' }` to device (if present), UPDATE `remote_sessions SET ended_at = now(), end_reason = 'disconnect'` if `sessionId` set and `ended_at` not already set

## Message Protocol

All messages are JSON with a `type` field.

### Server-generated messages

```json
{ "type": "peer-joined" }
{ "type": "peer-left" }
{ "type": "error", "reason": "device_not_found" | "unauthorized" | "device_busy" }
```

### Controller-initiated, server-handled

```json
{ "type": "session-end" }
```

### Relayed messages (server forwards without parsing)

```json
{ "type": "offer", "sdp": "..." }
{ "type": "answer", "sdp": "..." }
{ "type": "ice-candidate", "candidate": { ... } }
```

Any message type not listed above is forwarded as-is.

## Session Lifecycle

- Room becomes full (both device + controller present) → INSERT `remote_sessions`, store `sessionId`
- `session-end` message from controller → UPDATE `ended_at` + `end_reason = 'user'`
- Either side disconnects unexpectedly → UPDATE `ended_at` + `end_reason = 'disconnect'` (only if `sessionId` set and `ended_at` IS NULL)
- Partial room (only one side) → no session record created

## Security Notes

- Controllers must present valid JWT — `org_id` and `user_id` read from JWT payload only, never from query params beyond the token itself
- Cross-org: controller can only connect to devices in their own org (`AND org_id = $req.orgId` in device lookup) — returns `unauthorized` (same as missing, avoids enumeration)
- `device_busy`: second controller cannot hijack an active session
- `device_uid` lookup is read-only — device agent has no write access via WebSocket
- Room map is per-process — safe for single-instance deployment; Phase F can add Redis pub/sub for multi-instance

## Integration Tests

### tests/signaling.test.js

Test setup: start the actual HTTP+WS server on a random port, use `ws` npm client to connect. Reuse seed data (alice = owner org A, bob = member org A).

| # | Test | Setup | Expected |
|---|------|-------|----------|
| 1 | Device connects with valid device_uid | seed device_uid | WS stays open |
| 2 | Device connects with invalid device_uid | random uid | receives `{ type:'error', reason:'device_not_found' }`, connection closed |
| 3 | Controller connects with valid JWT + device_id | alice token + org A device | WS stays open |
| 4 | Controller connects with invalid JWT | garbage token | receives `{ type:'error', reason:'unauthorized' }`, connection closed |
| 5 | Controller connects to device in other org | alice token + org B device_id | receives `{ type:'error', reason:'unauthorized' }`, connection closed |
| 6 | Device connects first, controller connects → both receive peer-joined | both connected | controller receives `peer-joined`, device receives `peer-joined` |
| 7 | Controller sends offer → device receives it | room full | device receives `{ type:'offer', sdp:'...' }` verbatim |
| 8 | Controller disconnects → device receives peer-left | room full, controller closes | device receives `{ type:'peer-left' }` |
| 9 | Second controller connects to occupied room | room has controller | second controller receives `{ type:'error', reason:'device_busy' }`, closed |
| 10 | Controller sends session-end → remote_sessions updated | room full, session exists | ended_at set in DB, both connections closed |

## Dependencies

```
npm install ws
```

No other new packages. JWT verification reuses `jsonwebtoken` (already installed). DB reuses `src/db.js` pool.
