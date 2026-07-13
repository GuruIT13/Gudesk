# GuDesk Phase F.5a — WebRTC Controller Remote View Design Spec

## Scope

Replace `RemotePlaceholderScreen` with a real WebRTC remote desktop viewer on the controller side (macOS + Windows). The controller receives a video track from the host and displays it full-screen.

**In scope:**
- WebRTC offer/answer/ICE negotiation relayed through the existing Phase E WebSocket channel
- `RTCVideoView` full-screen video display
- `WebRtcNotifier` Riverpod state machine (idle → negotiating → streaming → error/ended)
- Unit tests for state machine and WS relay logic

**Out of scope:**
- Host-side screen capture and input injection (Phase F.5b)
- DataChannel mouse/keyboard input (Phase F.5b)
- TURN relay (future)
- Reconnect logic (future)
- Screen Recording permission handling (host-side concern, Phase F.5b)

## Architecture

Flutter controller app (`flutter/` subfolder). New feature files added under `features/session/`. No changes to the Node.js signaling server — it already relays all message types pass-through.

**Stack addition:** `flutter_webrtc ^0.9.x`

**Flow:**

```
RemoteScreen mounted
  → WebRtcNotifier.start(wsChannel, deviceId)
  → createPeerConnection()
  → createOffer() → setLocalDescription()
  → ws.send({ type: 'sdp_offer', sdp: localDesc.sdp })
  → ws.stream.listen:
      sdp_answer  → setRemoteDescription()
      ice_candidate → addCandidate()
  → onIceCandidate → ws.send({ type: 'ice_candidate', candidate: {...} })
  → onTrack (video) → renderer.srcObject = stream → status = streaming

Disconnect:
  → WebRtcNotifier.disconnect()
  → peerConnection.close()
  → ws.sink.add({ type: 'session-end' })
  → ws.sink.close()
  → navigate /home
```

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `flutter/pubspec.yaml` | Modify | Add flutter_webrtc ^0.9.x |
| `flutter/lib/features/session/domain/webrtc_state.dart` | Create | WebRtcStatus enum + WebRtcState |
| `flutter/lib/features/session/data/webrtc_notifier.dart` | Create | WebRtcNotifier + providers |
| `flutter/lib/features/session/presentation/remote_screen.dart` | Create | Full-screen video view + overlays |
| `flutter/lib/core/router/app_router.dart` | Modify | `/remote` → RemoteScreen |
| `flutter/test/features/session/webrtc_notifier_test.dart` | Create | State machine unit tests |

`remote_placeholder_screen.dart` is no longer referenced by the router but kept in place (not deleted) so git history is preserved.

## WebRtcState

```dart
enum WebRtcStatus { idle, negotiating, streaming, error, ended }

class WebRtcState {
  const WebRtcState({required this.status, this.errorReason});

  final WebRtcStatus status;
  final String? errorReason;

  static const idle = WebRtcState(status: WebRtcStatus.idle);

  WebRtcState copyWith({WebRtcStatus? status, String? errorReason}) =>
      WebRtcState(
        status: status ?? this.status,
        errorReason: errorReason ?? this.errorReason,
      );
}
```

## WebRtcNotifier

```dart
typedef RtcPcFactory = Future<RTCPeerConnection> Function(
  Map<String, dynamic> config,
  Map<String, dynamic> constraints,
);

final rtcPeerConnectionFactoryProvider = Provider<RtcPcFactory>(
  (_) => (config, constraints) => createPeerConnection(config, constraints),
);

class WebRtcNotifier extends Notifier<WebRtcState> {
  RTCPeerConnection? _pc;
  RTCVideoRenderer? _renderer;
  WebSocketChannel? _ws;
  StreamSubscription<dynamic>? _wsSub;

  @override
  WebRtcState build() => WebRtcState.idle;

  RTCVideoRenderer? get renderer => _renderer;

  Future<void> start({
    required WebSocketChannel wsChannel,
    required String deviceId,
  }) async { ... }

  Future<void> disconnect() async { ... }
}

final webRtcNotifierProvider =
    NotifierProvider<WebRtcNotifier, WebRtcState>(WebRtcNotifier.new);
```

**`start()` responsibilities:**
1. Initialize `RTCVideoRenderer`, call `renderer.initialize()`
2. Call `rtcPeerConnectionFactoryProvider` to create `RTCPeerConnection`
3. Register `onIceCandidate` → send `{ type: 'ice_candidate', candidate: {...} }` over WS
4. Register `onTrack` → on video track, set `renderer.srcObject`, transition to `streaming`
5. Listen to `wsChannel.stream` for `sdp_answer` and `ice_candidate` messages
6. On WS stream close during `negotiating` → transition to `error` with `errorReason: 'connection_closed'`
7. `createOffer()` → `setLocalDescription()` → send `{ type: 'sdp_offer', sdp: ... }` over WS
8. Transition to `negotiating`

**`disconnect()` responsibilities:**
1. Cancel WS subscription
2. Send `{ type: 'session-end' }` over WS sink
3. Close WS sink
4. Call `_pc?.close()`
5. Call `_renderer?.dispose()`
6. Null all handles
7. Transition to `ended`

## RemoteScreen UI

`ConsumerStatefulWidget`. Calls `WebRtcNotifier.start()` in `initState` via `addPostFrameCallback`.

**Layout:**
```
┌──────────────────────────────────────────┐
│ AppBar: "Remote — <hostname>"  [Disconnect] │
├──────────────────────────────────────────┤
│                                          │
│   RTCVideoView(renderer)                 │
│   objectFit: RTCVideoViewObjectFit.cover │
│   mirror: false                          │
│                                          │
│   [overlay when negotiating:]            │
│     CircularProgressIndicator            │
│     "Connecting..."                      │
│                                          │
│   [overlay when error:]                  │
│     error message                        │
│     [Back] button → /home               │
│                                          │
└──────────────────────────────────────────┘
```

**State-driven overlays:**
- `negotiating` → spinner overlay on top of black background
- `streaming` → full RTCVideoView, no overlay
- `error` → error message + Back button, navigate /home on tap
- `ended` → `ref.listen` triggers `context.go('/home')` automatically

**Disconnect button:**
```dart
onPressed: () async {
  final nav = context;
  await ref.read(webRtcNotifierProvider.notifier).disconnect();
  if (mounted) nav.go('/home');
}
```

## Router Change

`app_router.dart` `/remote` route:

```dart
GoRoute(
  path: '/remote',
  builder: (_, state) {
    final info = state.extra;
    if (info is! SessionInfo) return const HomeScreen();
    return RemoteScreen(sessionInfo: info);
  },
),
```

## Tests

**File:** `flutter/test/features/session/webrtc_notifier_test.dart`

Mock `RTCPeerConnection` injected via `rtcPeerConnectionFactoryProvider` override. Mock `WebSocketChannel` via `buildMockChannel()` (same pattern as `signaling_notifier_test.dart`).

| Test | What it checks |
|------|----------------|
| `start()` → negotiating | status == negotiating after start() resolves |
| sdp_answer received → streaming | inject `{type:'sdp_answer', sdp:'...'}` into mock WS stream → status == streaming |
| WS closes during negotiating → error | close mock WS stream → status == error, errorReason == 'connection_closed' |
| `disconnect()` sends session-end | verify `ws.sink.add({type:'session-end'})` called |
| `disconnect()` closes peer connection | verify `pc.close()` called |

`RTCVideoRenderer` is not tested in unit tests — requires native platform. State machine and WS relay logic are fully covered.

## WebRTC Configuration

```dart
final _pcConfig = {
  'iceServers': [
    {'urls': 'stun:stun.l.google.com:19302'},
  ],
};

final _pcConstraints = {
  'mandatory': {},
  'optional': [{'DtlsSrtpKeyAgreement': true}],
};

final _offerConstraints = {
  'mandatory': {
    'OfferToReceiveVideo': true,
    'OfferToReceiveAudio': false,
  },
  'optional': [],
};
```

## SDP/ICE Message Types

All relayed through existing Phase E WebSocket channel (`SessionInfo.wsChannel`). Signaling server forwards them unchanged.

| Direction | Message |
|-----------|---------|
| Controller → Host | `{ type: 'sdp_offer', sdp: String }` |
| Host → Controller | `{ type: 'sdp_answer', sdp: String }` |
| Controller → Host | `{ type: 'ice_candidate', candidate: String, sdpMid: String, sdpMLineIndex: int }` |
| Host → Controller | `{ type: 'ice_candidate', candidate: String, sdpMid: String, sdpMLineIndex: int }` |
| Controller → Host | `{ type: 'session-end' }` (on disconnect) |

## Dependencies

```yaml
dependencies:
  flutter_webrtc: ^0.9.47
```

No other new dependencies. `flutter_webrtc` supports Windows and macOS desktop natively.
