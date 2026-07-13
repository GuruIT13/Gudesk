# GuDesk Phase F — Flutter Desktop Controller App Design Spec

## Scope

Build a Flutter desktop controller app for macOS and Windows that allows org members to:
- Log in with email/password (JWT stored in secure storage)
- Browse org directory tree and device list
- Connect to a device via WebSocket signaling (Phase E backend)
- Show connecting state, handle errors and timeouts
- Navigate to RustDesk remote-view widget on success (Phase F.5 stub in Phase F)

**Out of scope for Phase F:** remote desktop rendering (Phase F.5), settings screen, user registration, TURN relay.

## Architecture

Flutter 3.x desktop app (`flutter/` subfolder in monorepo). Feature-first folder structure with Riverpod state management.

**Stack:**
- `flutter_riverpod` — state management
- `dio` — HTTP client with JWT interceptor
- `web_socket_channel` — WebSocket signaling client
- `flutter_secure_storage` — JWT persistence
- `go_router` — declarative navigation

**App flow:**
```
cold start → check JWT in secure storage
  → no JWT  → /login
  → has JWT → /home

/home → tap device card → /connecting?deviceId=<id>
  → WebSocket connected + peer-joined → /remote (stub in Phase F)
  → error / timeout → back to /home with error message
```

## Screens

### LoginScreen (`/login`)

- Email + password fields
- Submit → `POST /api/auth/login` → store JWT → navigate to `/home`
- Error: show inline message (invalid credentials)
- No registration link

### HomeScreen (`/home`)

Two-panel desktop layout:

```
┌─────────────────────────────────────────────────┐
│  GuDesk                              [logout]    │
├──────────────┬──────────────────────────────────┤
│ 📁 Root      │  Selected Directory Name          │
│  📁 BKK      │  ┌──────────┐  ┌──────────┐      │
│  📁 HQ       │  │ 🖥 Dev-1  │  │ 🖥 Dev-2  │      │
│              │  │ online   │  │ offline  │      │
│              │  └──────────┘  └──────────┘      │
└──────────────┴──────────────────────────────────┘
```

- Left panel: directory tree, expand/collapse — full tree loaded once via `GET /api/directories` (backend returns nested tree in one call)
- Right panel: device grid for selected directory
- Device card: hostname, status badge (`online` / `offline` / `busy`)
- Tap device card (online only) → navigate to `/connecting`
- Status polling: `GET /api/devices?directory_id=<id>` every 30 seconds
- Logout: clear JWT from secure storage → navigate to `/login`

### ConnectingScreen (`/connecting`)

- Spinner + "Connecting to \<hostname\>..." label
- Cancel button → send `{ type: 'session-end' }` → close WS → back to `/home`
- On `peer-joined` → navigate to `/remote`
- On `{ type: 'error', reason: ... }` → show error message → back to `/home`
- 10-second timeout → show "Connection timed out" → back to `/home`

### RemotePlaceholderScreen (`/remote`)

Stub screen for Phase F. Displays "Remote session active — rendering not yet implemented" with a Disconnect button that sends `session-end` and navigates back to `/home`. Phase F.5 replaces this with the RustDesk remote-view widget.

**Phase F.5 hook point:**
```dart
context.push('/remote', extra: SessionInfo(
  sessionId: room.sessionId,
  deviceId: device.id,
  wsChannel: channel,
));
```

## Signaling State Machine

```
idle → connecting → waiting_for_peer → connected
                                     → error
                                     → timeout (10s)
```

`SignalingNotifier` (Riverpod `AsyncNotifier`):
- Opens `ws://<host>/signal?token=<jwt>&device_id=<id>`
- Receives `peer-joined` → emits `connected`
- Receives `{ type: 'error' }` → emits `error` with reason
- No message within 10s → emits `timeout`
- On dispose / cancel → sends `{ type: 'session-end' }`, closes channel

## File Structure

```
flutter/
  pubspec.yaml
  lib/
    main.dart
    core/
      api/
        api_client.dart         # dio instance + JWT interceptor
      storage/
        secure_storage.dart     # flutter_secure_storage wrapper
      router/
        app_router.dart         # go_router config, auth redirect
    features/
      auth/
        data/
          auth_repository.dart  # POST /api/auth/login
        domain/
          user.dart             # User model (id, email, display_name)
        presentation/
          login_screen.dart
      directories/
        data/
          directories_repository.dart  # GET /api/directories (returns full nested tree)
        domain/
          directory.dart        # Directory model (id, name, parent_id)
        presentation/
          directory_tree.dart   # left-panel tree widget
      devices/
        data/
          devices_repository.dart  # GET /api/devices?directory_id=
        domain/
          device.dart           # Device model (id, hostname, status)
        presentation/
          device_card.dart
          device_grid.dart
      session/
        data/
          signaling_repository.dart   # WebSocket channel management
        domain/
          session_state.dart    # SignalingState enum + SessionInfo
        presentation/
          connecting_screen.dart
          remote_placeholder_screen.dart
  test/
    features/
      auth/
        auth_repository_test.dart
      directories/
        directories_repository_test.dart
      devices/
        devices_repository_test.dart
      session/
        signaling_notifier_test.dart  # state machine unit tests
```

## Riverpod Providers

| Provider | Type | Responsibility |
|---|---|---|
| `authRepositoryProvider` | Provider | Auth API calls |
| `jwtProvider` | StateProvider | Current JWT string (null = logged out) |
| `directoriesProvider` | FutureProvider | Load full directory tree (one call) |
| `selectedDirectoryProvider` | StateProvider | Currently selected directory id |
| `devicesProvider(directoryId)` | StreamProvider.family | Device list with 30s polling |
| `signalingNotifierProvider` | AsyncNotifier | WebSocket signaling state machine |

## API Endpoints Used

| Method | Endpoint | Used by |
|---|---|---|
| POST | `/api/auth/login` | AuthRepository |
| GET | `/api/directories` | DirectoriesRepository (full tree) |
| GET | `/api/devices?directory_id=` | DevicesRepository |
| WS | `/signal?token=&device_id=` | SignalingRepository |

## Tests

Unit tests with mocked HTTP (mockito or mocktail) and mocked WebSocket channel.

| File | Tests |
|---|---|
| `auth_repository_test.dart` | login success, 401 invalid credentials |
| `directories_repository_test.dart` | fetch full tree, empty org |
| `devices_repository_test.dart` | fetch devices by directory, empty list |
| `signaling_notifier_test.dart` | idle→connecting→waiting, peer-joined→connected, error reason, 10s timeout, cancel sends session-end |

## Dependencies (pubspec.yaml)

```yaml
dependencies:
  flutter_riverpod: ^2.6.1
  dio: ^5.7.0
  web_socket_channel: ^3.0.1
  flutter_secure_storage: ^9.2.2
  go_router: ^14.6.2

dev_dependencies:
  mocktail: ^1.0.4
  flutter_test:
    sdk: flutter
```

## Security Notes

- JWT stored in `flutter_secure_storage` (Keychain on macOS, Windows Credential Manager on Windows)
- JWT passed as query param `?token=<jwt>` for WebSocket (same pattern as Phase E spec)
- `org_id` never stored separately — always read from JWT payload by backend
- No token refresh in Phase F — expired JWT → re-login
