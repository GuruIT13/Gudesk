# GuDesk Phase F.5b — Host-Side Screen Capture and Input Injection Design Spec

## Scope

Build a Flutter desktop host app (`flutter_host/`) that captures the screen, streams it via WebRTC to the controller (F.5a), and receives mouse/keyboard input from the controller via DataChannel and injects it into the OS.

**In scope:**
- New Flutter desktop project at `flutter_host/`
- `HostNotifier` Riverpod state machine (idle → connecting → waiting → streaming → error)
- WebSocket connection to Phase E signaling server using `device_uid`
- WebRTC answer flow: receive `sdp_offer` → `createAnswer` → send `sdp_answer` + `ice_candidates`
- Native screen capture plugin (macOS: AVFoundation/ScreenCaptureKit, Windows: DXGI Desktop Duplication)
- Native input injection plugin (macOS: CGEventPost, Windows: SendInput)
- DataChannel input event receiver
- Host status UI (small status window)
- macOS Screen Recording permission check
- macOS Accessibility permission check (for input injection)
- Unit tests for `HostNotifier` state machine and WS/WebRTC relay logic

**Out of scope:**
- TURN relay (future)
- Reconnect logic (future)
- Audio capture (future)
- Multi-monitor selection UI (future — captures primary monitor only)
- Linux support (future)
- System tray / minimize to tray (future)
- Auto-start on login (future)
- Controller-side DataChannel send (Phase F.5c — controller input UI)

## Architecture

Separate Flutter desktop app at `flutter_host/`. The signaling server (Phase E) already relays all message types pass-through — no server changes needed.

**Stack:**
- Flutter 3.44, flutter_webrtc ^0.9.47, flutter_riverpod ^2.6.1, web_socket_channel ^3.0.1, go_router ^14.6.2
- Native plugins: Swift (macOS), C++ (Windows)
- macOS screen capture: ScreenCaptureKit (`SCStreamConfiguration`, macOS 12.3+) with AVFoundation fallback
- macOS input: `CGEventPost(kCGHIDEventTap, event)` — requires Accessibility permission
- Windows screen capture: DXGI Desktop Duplication (`IDXGIOutputDuplication`)
- Windows input: `SendInput()` Win32 API

**Flow:**

```
Host app launches
  → HostNotifier.start(deviceUid, wsUrl)
  → WebSocket connect ws://<server>/signal?device_uid=<uid>
  → status = waiting

Controller sends sdp_offer (relayed by signaling server)
  → HostNotifier receives sdp_offer
  → createPeerConnection()
  → setRemoteDescription(offer)
  → createAnswer() → setLocalDescription()
  → ws.send({ type: 'sdp_answer', sdp: localDesc.sdp })
  → onIceCandidate → ws.send({ type: 'ice_candidate', ... })
  → ws.stream.listen: ice_candidate → addCandidate()
  → ScreenCaptureService.startCapture()
  → native plugin → RTCVideoSource frames → addTrack to PC
  → status = streaming

DataChannel open (controller side opens it)
  → onDataChannel → listen for input events
  → { type: 'mouse_move', x, y } → InputInjectorService.injectMouseMove(x, y)
  → { type: 'mouse_click', button, x, y } → InputInjectorService.injectMouseClick(...)
  → { type: 'key', keyCode, modifiers, down } → InputInjectorService.injectKey(...)

Controller disconnects
  → ws.send({ type: 'session-end' })
  → peerConnection.close()
  → ScreenCaptureService.stopCapture()
  → status = waiting (ready for next session)
```

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `flutter_host/pubspec.yaml` | Create | Project deps |
| `flutter_host/lib/main.dart` | Create | App entry, ProviderScope, HostScreen |
| `flutter_host/lib/features/host/domain/host_state.dart` | Create | `HostStatus` enum + `HostState` |
| `flutter_host/lib/features/host/data/screen_capture_service.dart` | Create | MethodChannel wrapper for native capture |
| `flutter_host/lib/features/host/data/input_injector_service.dart` | Create | MethodChannel wrapper for native input |
| `flutter_host/lib/features/host/data/host_notifier.dart` | Create | `HostNotifier` + providers |
| `flutter_host/lib/features/host/presentation/host_screen.dart` | Create | Status window UI |
| `flutter_host/macos/Runner/ScreenCapturePlugin.swift` | Create | macOS screen capture (ScreenCaptureKit) |
| `flutter_host/macos/Runner/InputInjectorPlugin.swift` | Create | macOS input injection (CGEventPost) |
| `flutter_host/windows/screen_capture_plugin.cpp` | Create | Windows DXGI Desktop Duplication |
| `flutter_host/windows/input_injector_plugin.cpp` | Create | Windows SendInput |
| `flutter_host/test/features/host/host_notifier_test.dart` | Create | State machine unit tests |

## HostState

```dart
enum HostStatus { idle, connecting, waiting, streaming, error }

class HostState {
  const HostState({required this.status, this.errorReason});

  final HostStatus status;
  final String? errorReason;

  static const idle = HostState(status: HostStatus.idle);

  HostState copyWith({HostStatus? status, String? errorReason}) =>
      HostState(
        status: status ?? this.status,
        errorReason: errorReason ?? this.errorReason,
      );
}
```

## ScreenCaptureService

Dart wrapper around the native `screen_capture` MethodChannel.

```dart
class ScreenCaptureService {
  static const _channel = MethodChannel('gudesk/screen_capture');

  Future<void> startCapture() => _channel.invokeMethod('startCapture');
  Future<void> stopCapture() => _channel.invokeMethod('stopCapture');
  Future<bool> hasPermission() async =>
      await _channel.invokeMethod<bool>('hasPermission') ?? false;
  Future<void> requestPermission() =>
      _channel.invokeMethod('requestPermission');
}

final screenCaptureServiceProvider = Provider<ScreenCaptureService>(
  (_) => ScreenCaptureService(),
);
```

The native plugin registers a custom `RTCVideoSource` with flutter_webrtc and pushes frames into it. The Dart side retrieves the video track via `flutter_webrtc`'s `createLocalVideoTrack` after `startCapture()` returns.

## InputInjectorService

```dart
class InputInjectorService {
  static const _channel = MethodChannel('gudesk/input_injector');

  Future<bool> hasPermission() async =>
      await _channel.invokeMethod<bool>('hasPermission') ?? false;
  Future<void> requestPermission() =>
      _channel.invokeMethod('requestPermission');

  Future<void> injectMouseMove(double x, double y) =>
      _channel.invokeMethod('injectMouseMove', {'x': x, 'y': y});

  Future<void> injectMouseClick(String button, double x, double y) =>
      _channel.invokeMethod('injectMouseClick', {'button': button, 'x': x, 'y': y});

  Future<void> injectKey(int keyCode, List<String> modifiers, bool down) =>
      _channel.invokeMethod('injectKey', {
        'keyCode': keyCode,
        'modifiers': modifiers,
        'down': down,
      });
}

final inputInjectorServiceProvider = Provider<InputInjectorService>(
  (_) => InputInjectorService(),
);
```

## HostNotifier

```dart
typedef RtcPcFactory = Future<RTCPeerConnection> Function(
  Map<String, dynamic> config,
  Map<String, dynamic> constraints,
);

final rtcPeerConnectionFactoryProvider = Provider<RtcPcFactory>(
  (_) => (config, constraints) => createPeerConnection(config, constraints),
);

typedef WsChannelFactory = WebSocketChannel Function(Uri uri);

final wsChannelFactoryProvider = Provider<WsChannelFactory>(
  (_) => (uri) => WebSocketChannel.connect(uri),
);

class HostNotifier extends Notifier<HostState> {
  RTCPeerConnection? _pc;
  WebSocketChannel? _ws;
  StreamSubscription<dynamic>? _wsSub;
  RTCDataChannel? _dataChannel;

  @override
  HostState build() => HostState.idle;

  Future<void> start({
    required String deviceUid,
    required String wsUrl,
  }) async { ... }

  Future<void> stop() async { ... }
}

final hostNotifierProvider =
    NotifierProvider<HostNotifier, HostState>(HostNotifier.new);
```

**`start()` responsibilities:**
1. Guard: `if (state.status != HostStatus.idle) return`
2. Connect WebSocket: `ws://<wsUrl>/signal?device_uid=<deviceUid>`
3. Transition to `connecting`, then `waiting` on WS open
4. Listen to WS stream:
   - `sdp_offer` → createPeerConnection → setRemoteDescription → createAnswer → setLocalDescription → send `sdp_answer` → `ScreenCaptureService.startCapture()` → add video track → transition to `streaming`
   - `ice_candidate` → `addCandidate()`
   - `session-end` → `_cleanup()` → transition to `waiting` (ready for next session)
5. Register `onIceCandidate` → send `{ type: 'ice_candidate', ... }` over WS
6. Register `onDataChannel` → listen for input events → route to `InputInjectorService`
7. WS close during `waiting` or `streaming` → transition to `error` with `errorReason: 'connection_closed'`

**`stop()` responsibilities:**
1. Send `{ type: 'session-end' }` if streaming
2. Call `_cleanup()`
3. Cancel WS subscription, close WS sink, null all handles
4. Transition to `idle`

**`_cleanup()` (internal, called on session-end or stop):**
1. `ScreenCaptureService.stopCapture()`
2. `_dataChannel?.close()`
3. `_pc?.close()`
4. Null `_pc`, `_dataChannel`
5. Transition to `waiting` (unless stop() called, which goes to idle)

## HostScreen UI

```
┌─────────────────────────────────┐
│  GuDesk Host                    │
│                                 │
│  ● Waiting for connection...    │  ← status text
│  DESKTOP-1                      │  ← device name (hostname)
│                                 │
│  [Stop Hosting]                 │
└─────────────────────────────────┘
```

State-driven status text:
- `idle` — "Not connected"
- `connecting` — "Connecting..." + CircularProgressIndicator
- `waiting` — "● Waiting for connection..." (green dot)
- `streaming` — "● Streaming" (green dot) + controller hostname if available
- `error` — "✕ Error: <errorReason>" + [Retry] button

`HostScreen` is a `ConsumerStatefulWidget`. Calls `HostNotifier.start()` in `initState` via `addPostFrameCallback`. Device UID read from secure storage (same `flutter_secure_storage` pattern as controller).

## Native Plugin: macOS Screen Capture

**File:** `flutter_host/macos/Runner/ScreenCapturePlugin.swift`

- Registers MethodChannel `gudesk/screen_capture`
- `hasPermission()` → `CGPreflightScreenCaptureAccess()`
- `requestPermission()` → `CGRequestScreenCaptureAccess()`
- `startCapture()`:
  - Creates `SCStreamConfiguration` (1920×1080, 30fps, pixel format `BGRA8888`)
  - Creates `SCStream` capturing `SCDisplay.main`
  - Implements `SCStreamOutput` — `stream(_:didOutputSampleBuffer:of:)` receives `CMSampleBuffer`
  - Converts `CVPixelBuffer` → `RTCVideoFrame` (via `RTCCVPixelBuffer`)
  - Pushes frame into `RTCVideoSource` obtained from flutter_webrtc's `videoSource` registry
- `stopCapture()` → `stream.stopCapture()`

**Permission note:** macOS requires Screen Recording permission granted in System Settings → Privacy & Security → Screen Recording. Without it, `startCapture()` returns empty frames silently — must check `hasPermission()` first.

## Native Plugin: macOS Input Injection

**File:** `flutter_host/macos/Runner/InputInjectorPlugin.swift`

- Registers MethodChannel `gudesk/input_injector`
- `hasPermission()` → `AXIsProcessTrusted()`
- `requestPermission()` → `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])`
- `injectMouseMove(x, y)` → `CGEventCreateMouseEvent(nil, .mouseMoved, CGPoint(x,y), .left)` → `CGEventPost(.cghidEventTap, event)`
- `injectMouseClick(button, x, y)` → mouseDown + mouseUp events
- `injectKey(keyCode, modifiers, down)` → `CGEventCreateKeyboardEvent` with modifier flags

## Native Plugin: Windows Screen Capture

**File:** `flutter_host/windows/screen_capture_plugin.cpp`

- Registers MethodChannel `gudesk/screen_capture`
- `startCapture()`:
  - `D3D11CreateDevice` → `IDXGIDevice` → `IDXGIAdapter` → `IDXGIOutput` → `IDXGIOutput1`
  - `DuplicateOutput()` → `IDXGIOutputDuplication`
  - Capture loop thread: `AcquireNextFrame(timeout)` → `ID3D11Texture2D` → convert to I420 → push `RTCVideoFrame`
- `stopCapture()` → signal capture thread, release `IDXGIOutputDuplication`
- No permission check required on Windows for DXGI (runs as user)

## Native Plugin: Windows Input Injection

**File:** `flutter_host/windows/input_injector_plugin.cpp`

- Registers MethodChannel `gudesk/input_injector`
- `hasPermission()` → returns `true` (SendInput needs no special permission)
- `injectMouseMove(x, y)` → `INPUT{ type=INPUT_MOUSE, mi={ dx, dy, MOUSEEVENTF_MOVE|MOUSEEVENTF_ABSOLUTE } }` → `SendInput(1, &input, sizeof(INPUT))`
- `injectMouseClick(button, x, y)` → MOUSEEVENTF_LEFTDOWN + MOUSEEVENTF_LEFTUP (or RIGHT variants)
- `injectKey(keyCode, modifiers, down)` → `INPUT{ type=INPUT_KEYBOARD, ki={ wVk=keyCode, dwFlags=down?0:KEYEVENTF_KEYUP } }` → `SendInput`

## DataChannel Input Event Format

Controller sends JSON over DataChannel (to be implemented in Phase F.5c). Host parses:

```json
{ "type": "mouse_move", "x": 1024.0, "y": 768.0 }
{ "type": "mouse_click", "button": "left", "x": 512.0, "y": 400.0 }
{ "type": "mouse_scroll", "dx": 0.0, "dy": -3.0 }
{ "type": "key", "keyCode": 65, "modifiers": ["shift"], "down": true }
```

Coordinates are in screen pixels (absolute). Host maps directly to OS inject calls.

## SDP/ICE Message Types

Same channel as F.5a — signaling server relays all unchanged.

| Direction | Message |
|-----------|---------|
| Controller → Host | `{ type: 'sdp_offer', sdp: String }` |
| Host → Controller | `{ type: 'sdp_answer', sdp: String }` |
| Controller → Host | `{ type: 'ice_candidate', candidate: String, sdpMid: String, sdpMLineIndex: int }` |
| Host → Controller | `{ type: 'ice_candidate', candidate: String, sdpMid: String, sdpMLineIndex: int }` |
| Either → Either | `{ type: 'session-end' }` |

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

final _answerConstraints = {
  'mandatory': {
    'OfferToReceiveVideo': false,
    'OfferToReceiveAudio': false,
  },
  'optional': [],
};
```

Host does NOT receive video (it sends). `OfferToReceiveVideo: false`.

## Unit Tests

**File:** `flutter_host/test/features/host/host_notifier_test.dart`

Mock pattern: same as `webrtc_notifier_test.dart` — `MockRTCPeerConnection` injected via `rtcPeerConnectionFactoryProvider` override. Mock `WebSocketChannel` via `buildMockChannel()`. Mock `ScreenCaptureService` and `InputInjectorService` via Riverpod provider overrides.

| Test | What it checks |
|------|----------------|
| `start()` → waiting | status == waiting after WS connects |
| `sdp_offer` received → sdp_answer sent | inject `{type:'sdp_offer',sdp:'...'}` → verify `ws.sink.add({type:'sdp_answer',...})` called |
| `sdp_offer` received → screen capture started | verify `ScreenCaptureService.startCapture()` called |
| `sdp_offer` received → status == streaming | status == streaming after offer processed |
| WS closes during waiting → error | close mock WS stream → status == error, errorReason == 'connection_closed' |
| DataChannel message → InputInjectorService called | verify inject method called with correct args |
| `stop()` transitions to idle | status == idle, WS closed |

`RTCVideoRenderer` and native plugins not tested in unit tests — require native platform.

## Dependencies

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.6.1
  flutter_webrtc: ^0.9.47
  web_socket_channel: ^3.0.1
  flutter_secure_storage: ^9.2.2
  go_router: ^14.6.2

dev_dependencies:
  flutter_test:
    sdk: flutter
  mocktail: ^1.0.4
  flutter_lints: ^3.0.0
```
