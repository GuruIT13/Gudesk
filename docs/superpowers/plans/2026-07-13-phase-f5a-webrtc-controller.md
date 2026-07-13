# Phase F.5a — WebRTC Controller Remote View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `RemotePlaceholderScreen` with a real WebRTC video receiver on the controller side — the controller sends an SDP offer, receives the host's video track, and displays it full-screen.

**Architecture:** `flutter_webrtc` handles peer connection and video rendering. `WebRtcNotifier` (Riverpod Notifier) owns the state machine (idle → negotiating → streaming → error/ended) and relays SDP/ICE through the existing Phase E WebSocket channel already stored in `SessionInfo`. `RemoteScreen` is a `ConsumerStatefulWidget` that starts negotiation in `initState` and renders overlays based on notifier state.

**Tech Stack:** Flutter 3.44, flutter_webrtc ^0.9.47, flutter_riverpod ^2.6.1, go_router ^14.6.2, mocktail ^1.0.4, web_socket_channel ^3.0.1

---

### Task 1: Add flutter_webrtc dependency + WebRtcState domain model

**Files:**
- Modify: `flutter/pubspec.yaml`
- Create: `flutter/lib/features/session/domain/webrtc_state.dart`

- [ ] **Step 1: Add dependency to pubspec.yaml**

In `flutter/pubspec.yaml`, under `dependencies:` (after `go_router`), add:

```yaml
  flutter_webrtc: ^0.9.47
```

The `dependencies:` block should now end with:
```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.6.1
  dio: ^5.7.0
  web_socket_channel: ^3.0.1
  flutter_secure_storage: ^9.2.2
  go_router: ^14.6.2
  flutter_webrtc: ^0.9.47
```

- [ ] **Step 2: Run pub get**

```powershell
$env:PATH = "C:\flutter\bin;" + $env:PATH
cd C:\Users\Guruit\Documents\Gudesk\flutter
flutter pub get
```

Expected: resolves flutter_webrtc and its transitive deps, no errors.

- [ ] **Step 3: Create webrtc_state.dart**

Create `flutter/lib/features/session/domain/webrtc_state.dart`:

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

- [ ] **Step 4: Run flutter analyze**

```powershell
$env:PATH = "C:\flutter\bin;" + $env:PATH
cd C:\Users\Guruit\Documents\Gudesk\flutter
flutter analyze lib/features/session/domain/webrtc_state.dart
```

Expected: No issues found.

- [ ] **Step 5: Commit**

```powershell
cd C:\Users\Guruit\Documents\Gudesk
git add flutter/pubspec.yaml flutter/pubspec.lock flutter/lib/features/session/domain/webrtc_state.dart
git commit -m "feat(f5a): add flutter_webrtc dep and WebRtcState domain model"
```

---

### Task 2: WebRtcNotifier — state machine + WS relay + unit tests

**Files:**
- Create: `flutter/lib/features/session/data/webrtc_notifier.dart`
- Create: `flutter/test/features/session/webrtc_notifier_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `flutter/test/features/session/webrtc_notifier_test.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:mocktail/mocktail.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:gudesk_controller/features/session/data/webrtc_notifier.dart';
import 'package:gudesk_controller/features/session/domain/webrtc_state.dart';

class MockRTCPeerConnection extends Mock implements RTCPeerConnection {}
class MockWebSocketChannel extends Mock implements WebSocketChannel {}
class MockWebSocketSink extends Mock implements WebSocketSink {}

WebSocketChannel buildMockChannel({required Stream<dynamic> stream}) {
  final channel = MockWebSocketChannel();
  final sink = MockWebSocketSink();
  when(() => channel.stream).thenAnswer((_) => stream);
  when(() => channel.sink).thenReturn(sink);
  when(() => sink.add(any())).thenAnswer((_) {});
  when(() => sink.close()).thenAnswer((_) async {});
  return channel;
}

void main() {
  late MockRTCPeerConnection mockPc;

  setUp(() {
    mockPc = MockRTCPeerConnection();

    // Default stubs — override per test as needed
    when(() => mockPc.onIceCandidate = any()).thenReturn(null);
    when(() => mockPc.onTrack = any()).thenReturn(null);
    when(() => mockPc.addCandidate(any())).thenAnswer((_) async {});
    when(() => mockPc.close()).thenAnswer((_) async {});

    final fakeDesc = RTCSessionDescription('v=0\r\n', 'offer');
    when(() => mockPc.createOffer(any())).thenAnswer((_) async => fakeDesc);
    when(() => mockPc.setLocalDescription(any())).thenAnswer((_) async {});
    when(() => mockPc.setRemoteDescription(any())).thenAnswer((_) async {});
  });

  ProviderContainer buildContainer({
    required Stream<dynamic> wsStream,
    RTCPeerConnection? pc,
  }) {
    final channel = buildMockChannel(stream: wsStream);
    final effectivePc = pc ?? mockPc;

    return ProviderContainer(
      overrides: [
        rtcPeerConnectionFactoryProvider.overrideWithValue(
          (config, constraints) async => effectivePc,
        ),
      ],
    );
  }

  group('WebRtcNotifier', () {
    test('start() transitions to negotiating', () async {
      final ctrl = StreamController<dynamic>();
      final container = buildContainer(wsStream: ctrl.stream);
      addTearDown(container.dispose);
      addTearDown(ctrl.close);

      final channel = buildMockChannel(stream: ctrl.stream);
      expect(
        container.read(webRtcNotifierProvider).status,
        equals(WebRtcStatus.idle),
      );

      await container
          .read(webRtcNotifierProvider.notifier)
          .start(wsChannel: channel, deviceId: 'dev-1');

      expect(
        container.read(webRtcNotifierProvider).status,
        equals(WebRtcStatus.negotiating),
      );
    });

    test('sdp_answer received transitions to streaming', () async {
      final ctrl = StreamController<dynamic>();
      final container = buildContainer(wsStream: ctrl.stream);
      addTearDown(container.dispose);

      // Capture the onTrack setter so we can fire it
      Function(RTCTrackEvent)? onTrackCb;
      when(() => mockPc.onTrack = any()).thenAnswer((inv) {
        onTrackCb = inv.positionalArguments[0] as Function(RTCTrackEvent)?;
      });

      final channel = buildMockChannel(stream: ctrl.stream);
      await container
          .read(webRtcNotifierProvider.notifier)
          .start(wsChannel: channel, deviceId: 'dev-1');

      // Send sdp_answer from host
      ctrl.add(jsonEncode({'type': 'sdp_answer', 'sdp': 'v=0\r\n'}));
      await Future.delayed(const Duration(milliseconds: 50));

      // Fire onTrack (simulating video track arrival)
      if (onTrackCb != null) {
        final fakeStream = MockMediaStream();
        onTrackCb!(RTCTrackEvent(
          track: MockMediaStreamTrack(),
          streams: [fakeStream],
          transceiver: null,
          receiver: null,
        ));
      }
      await Future.delayed(const Duration(milliseconds: 50));

      expect(
        container.read(webRtcNotifierProvider).status,
        equals(WebRtcStatus.streaming),
      );
      ctrl.close();
    });

    test('WS closes during negotiating transitions to error', () async {
      final ctrl = StreamController<dynamic>();
      final container = buildContainer(wsStream: ctrl.stream);
      addTearDown(container.dispose);

      final channel = buildMockChannel(stream: ctrl.stream);
      await container
          .read(webRtcNotifierProvider.notifier)
          .start(wsChannel: channel, deviceId: 'dev-1');

      await ctrl.close();
      await Future.delayed(const Duration(milliseconds: 50));

      final state = container.read(webRtcNotifierProvider);
      expect(state.status, equals(WebRtcStatus.error));
      expect(state.errorReason, equals('connection_closed'));
    });

    test('disconnect() sends session-end over WS sink', () async {
      final ctrl = StreamController<dynamic>();
      final container = buildContainer(wsStream: ctrl.stream);
      addTearDown(container.dispose);

      final channel = buildMockChannel(stream: ctrl.stream);
      final sink = channel.sink as MockWebSocketSink;

      await container
          .read(webRtcNotifierProvider.notifier)
          .start(wsChannel: channel, deviceId: 'dev-1');

      await container.read(webRtcNotifierProvider.notifier).disconnect();

      verify(() => sink.add(jsonEncode({'type': 'session-end'}))).called(1);
      verify(() => sink.close()).called(1);
      ctrl.close();
    });

    test('disconnect() closes peer connection', () async {
      final ctrl = StreamController<dynamic>();
      final container = buildContainer(wsStream: ctrl.stream);
      addTearDown(container.dispose);

      final channel = buildMockChannel(stream: ctrl.stream);
      await container
          .read(webRtcNotifierProvider.notifier)
          .start(wsChannel: channel, deviceId: 'dev-1');

      await container.read(webRtcNotifierProvider.notifier).disconnect();

      verify(() => mockPc.close()).called(1);
      ctrl.close();
    });
  });
}

// Minimal mocks for flutter_webrtc types used in RTCTrackEvent
class MockMediaStream extends Mock implements MediaStream {}
class MockMediaStreamTrack extends Mock implements MediaStreamTrack {}
```

- [ ] **Step 2: Run tests — verify they fail**

```powershell
$env:PATH = "C:\flutter\bin;" + $env:PATH
cd C:\Users\Guruit\Documents\Gudesk\flutter
flutter test test/features/session/webrtc_notifier_test.dart
```

Expected: FAIL — `webrtc_notifier.dart` does not exist yet.

- [ ] **Step 3: Create webrtc_notifier.dart**

Create `flutter/lib/features/session/data/webrtc_notifier.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../domain/webrtc_state.dart';

typedef RtcPcFactory = Future<RTCPeerConnection> Function(
  Map<String, dynamic> config,
  Map<String, dynamic> constraints,
);

final rtcPeerConnectionFactoryProvider = Provider<RtcPcFactory>(
  (_) => (config, constraints) => createPeerConnection(config, constraints),
);

final _pcConfig = {
  'iceServers': [
    {'urls': 'stun:stun.l.google.com:19302'},
  ],
};

final _pcConstraints = {
  'mandatory': {},
  'optional': [
    {'DtlsSrtpKeyAgreement': true},
  ],
};

final _offerConstraints = {
  'mandatory': {
    'OfferToReceiveVideo': true,
    'OfferToReceiveAudio': false,
  },
  'optional': [],
};

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
  }) async {
    _ws = wsChannel;

    _renderer = RTCVideoRenderer();
    await _renderer!.initialize();

    final factory = ref.read(rtcPeerConnectionFactoryProvider);
    _pc = await factory(_pcConfig, _pcConstraints);

    _pc!.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;
      _ws?.sink.add(jsonEncode({
        'type': 'ice_candidate',
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      }));
    };

    _pc!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _renderer?.srcObject = event.streams[0];
        state = state.copyWith(status: WebRtcStatus.streaming);
      }
    };

    _wsSub = wsChannel.stream.listen(
      (raw) {
        final msg = jsonDecode(raw as String) as Map<String, dynamic>;
        switch (msg['type']) {
          case 'sdp_answer':
            _pc?.setRemoteDescription(
              RTCSessionDescription(msg['sdp'] as String, 'answer'),
            );
          case 'ice_candidate':
            _pc?.addCandidate(RTCIceCandidate(
              msg['candidate'] as String?,
              msg['sdpMid'] as String?,
              msg['sdpMLineIndex'] as int?,
            ));
        }
      },
      onDone: () {
        if (state.status == WebRtcStatus.negotiating) {
          state = state.copyWith(
            status: WebRtcStatus.error,
            errorReason: 'connection_closed',
          );
        }
      },
    );

    final offer = await _pc!.createOffer(_offerConstraints);
    await _pc!.setLocalDescription(offer);
    wsChannel.sink.add(jsonEncode({
      'type': 'sdp_offer',
      'sdp': offer.sdp,
    }));

    state = state.copyWith(status: WebRtcStatus.negotiating);
  }

  Future<void> disconnect() async {
    await _wsSub?.cancel();
    _wsSub = null;

    _ws?.sink.add(jsonEncode({'type': 'session-end'}));
    await _ws?.sink.close();
    _ws = null;

    await _pc?.close();
    _pc = null;

    _renderer?.dispose();
    _renderer = null;

    state = state.copyWith(status: WebRtcStatus.ended);
  }
}

final webRtcNotifierProvider =
    NotifierProvider<WebRtcNotifier, WebRtcState>(WebRtcNotifier.new);
```

- [ ] **Step 4: Run tests — verify they pass**

```powershell
$env:PATH = "C:\flutter\bin;" + $env:PATH
cd C:\Users\Guruit\Documents\Gudesk\flutter
flutter test test/features/session/webrtc_notifier_test.dart --reporter=expanded
```

Expected: 5/5 PASS.

Note: `RTCVideoRenderer` is not instantiated in unit tests (requires native platform). The notifier only calls `initialize()` and `dispose()` on it — if tests fail due to platform channel issues from `RTCVideoRenderer()`, wrap the renderer init in a try/catch or skip renderer creation when the factory is overridden. The test's mock PC doesn't trigger `onTrack` through platform channels.

If tests fail due to `RTCVideoRenderer` platform unavailability, add an optional `rendererFactory` param to `start()` and stub it in tests — but try without first.

- [ ] **Step 5: Run full test suite**

```powershell
$env:PATH = "C:\flutter\bin;" + $env:PATH
cd C:\Users\Guruit\Documents\Gudesk\flutter
flutter test
```

Expected: All 13 existing tests + 5 new = 18 tests pass.

- [ ] **Step 6: Run flutter analyze**

```powershell
$env:PATH = "C:\flutter\bin;" + $env:PATH
cd C:\Users\Guruit\Documents\Gudesk\flutter
flutter analyze
```

Expected: No issues found.

- [ ] **Step 7: Commit**

```powershell
cd C:\Users\Guruit\Documents\Gudesk
git add flutter/lib/features/session/data/webrtc_notifier.dart flutter/test/features/session/webrtc_notifier_test.dart
git commit -m "feat(f5a): add WebRtcNotifier state machine with WS relay and unit tests"
```

---

### Task 3: RemoteScreen UI

**Files:**
- Create: `flutter/lib/features/session/presentation/remote_screen.dart`

- [ ] **Step 1: Create remote_screen.dart**

Create `flutter/lib/features/session/presentation/remote_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';
import '../data/webrtc_notifier.dart';
import '../domain/session_state.dart';
import '../domain/webrtc_state.dart';

class RemoteScreen extends ConsumerStatefulWidget {
  const RemoteScreen({super.key, required this.sessionInfo});

  final SessionInfo sessionInfo;

  @override
  ConsumerState<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends ConsumerState<RemoteScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startSession());
  }

  Future<void> _startSession() async {
    await ref.read(webRtcNotifierProvider.notifier).start(
          wsChannel: widget.sessionInfo.wsChannel,
          deviceId: widget.sessionInfo.deviceId,
        );
  }

  Future<void> _disconnect() async {
    await ref.read(webRtcNotifierProvider.notifier).disconnect();
    if (mounted) context.go('/home'); // ignore: use_build_context_synchronously
  }

  @override
  Widget build(BuildContext context) {
    final webRtcState = ref.watch(webRtcNotifierProvider);
    final renderer = ref.read(webRtcNotifierProvider.notifier).renderer;

    ref.listen(webRtcNotifierProvider, (_, next) {
      if (!mounted) return;
      if (next.status == WebRtcStatus.ended) {
        context.go('/home');
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text('Remote — ${widget.sessionInfo.hostname}'),
        actions: [
          TextButton(
            onPressed: _disconnect,
            child: const Text('Disconnect'),
          ),
        ],
      ),
      body: _buildBody(webRtcState, renderer),
    );
  }

  Widget _buildBody(WebRtcState webRtcState, RTCVideoRenderer? renderer) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Video layer (always present — black when no stream)
        if (renderer != null)
          RTCVideoView(
            renderer,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            mirror: false,
          )
        else
          const ColoredBox(color: Colors.black),

        // Overlay layer
        if (webRtcState.status == WebRtcStatus.negotiating)
          const ColoredBox(
            color: Colors.black,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text(
                    'Connecting...',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ],
              ),
            ),
          )
        else if (webRtcState.status == WebRtcStatus.error)
          ColoredBox(
            color: Colors.black87,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    webRtcState.errorReason ?? 'Connection failed',
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => context.go('/home'),
                    child: const Text('Back'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
```

- [ ] **Step 2: Run flutter analyze on the new file**

```powershell
$env:PATH = "C:\flutter\bin;" + $env:PATH
cd C:\Users\Guruit\Documents\Gudesk\flutter
flutter analyze lib/features/session/presentation/remote_screen.dart
```

Expected: No issues found.

- [ ] **Step 3: Commit**

```powershell
cd C:\Users\Guruit\Documents\Gudesk
git add flutter/lib/features/session/presentation/remote_screen.dart
git commit -m "feat(f5a): add RemoteScreen with RTCVideoView and state overlays"
```

---

### Task 4: Router update + final analyze + full test run

**Files:**
- Modify: `flutter/lib/core/router/app_router.dart`

- [ ] **Step 1: Update app_router.dart**

In `flutter/lib/core/router/app_router.dart`:

1. Add import for `RemoteScreen` (remove `RemotePlaceholderScreen` import):
```dart
// Remove this line:
import '../../features/session/presentation/remote_placeholder_screen.dart';

// Add this line:
import '../../features/session/presentation/remote_screen.dart';
```

2. Update the `/remote` route builder — change `RemotePlaceholderScreen` to `RemoteScreen`:
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

The full updated file should look like:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/session/presentation/connecting_screen.dart';
import '../../features/session/presentation/remote_screen.dart';
import '../../features/session/domain/session_state.dart';
import '../storage/secure_storage.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) async {
      try {
        final jwt = await secureStorage.readJwt();
        final isLoggedIn = jwt != null;
        final isLoggingIn = state.matchedLocation == '/login';
        if (!isLoggedIn && !isLoggingIn) return '/login';
        if (isLoggedIn && isLoggingIn) return '/home';
        return null;
      } catch (_) {
        return '/login';
      }
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
      GoRoute(
        path: '/connecting',
        builder: (_, state) {
          final deviceId = state.uri.queryParameters['deviceId'] ?? '';
          final hostname = state.uri.queryParameters['hostname'] ?? deviceId;
          return ConnectingScreen(deviceId: deviceId, hostname: hostname);
        },
      ),
      GoRoute(
        path: '/remote',
        builder: (_, state) {
          final info = state.extra;
          if (info is! SessionInfo) return const HomeScreen();
          return RemoteScreen(sessionInfo: info);
        },
      ),
    ],
  );
});
```

- [ ] **Step 2: Run flutter analyze — full project**

```powershell
$env:PATH = "C:\flutter\bin;" + $env:PATH
cd C:\Users\Guruit\Documents\Gudesk\flutter
flutter analyze
```

Expected: No issues found. `remote_placeholder_screen.dart` is still present but unreferenced — that is intentional per spec (kept for git history, not deleted).

If analyzer complains about `remote_placeholder_screen.dart` being unused, that is fine — it is a standalone file not referenced anywhere, not a Dart error.

- [ ] **Step 3: Run full test suite**

```powershell
$env:PATH = "C:\flutter\bin;" + $env:PATH
cd C:\Users\Guruit\Documents\Gudesk\flutter
flutter test --reporter=expanded
```

Expected: 18/18 tests pass (13 existing + 5 WebRtcNotifier).

- [ ] **Step 4: Commit**

```powershell
cd C:\Users\Guruit\Documents\Gudesk
git add flutter/lib/core/router/app_router.dart
git commit -m "feat(f5a): wire RemoteScreen into router, replacing placeholder"
```

- [ ] **Step 5: Push to GitHub**

```powershell
cd C:\Users\Guruit\Documents\Gudesk
git push
```

---

## Self-Review

**Spec coverage:**

| Spec requirement | Task |
|-----------------|------|
| `flutter_webrtc ^0.9.47` in pubspec | Task 1 |
| `WebRtcStatus` enum + `WebRtcState` class with `copyWith` + `idle` constant | Task 1 |
| `RtcPcFactory` typedef + `rtcPeerConnectionFactoryProvider` | Task 2 |
| `WebRtcNotifier` with `start()` and `disconnect()` | Task 2 |
| `onIceCandidate` → send `ice_candidate` over WS | Task 2 |
| `onTrack` → `renderer.srcObject` + transition to `streaming` | Task 2 |
| WS stream listens for `sdp_answer` → `setRemoteDescription` | Task 2 |
| WS stream listens for `ice_candidate` → `addCandidate` | Task 2 |
| WS close during `negotiating` → `error` with `connection_closed` | Task 2 |
| `createOffer` → `setLocalDescription` → send `sdp_offer` | Task 2 |
| `disconnect()`: cancel sub, send `session-end`, close sink, `pc.close()`, `renderer.dispose()`, transition to `ended` | Task 2 |
| `webRtcNotifierProvider` | Task 2 |
| 5 unit tests (negotiating, streaming, error, session-end, pc.close) | Task 2 |
| `RemoteScreen` ConsumerStatefulWidget | Task 3 |
| `start()` called in `initState` via `addPostFrameCallback` | Task 3 |
| AppBar with hostname + Disconnect button | Task 3 |
| `RTCVideoView` with `cover` fit and `mirror: false` | Task 3 |
| Spinner overlay when `negotiating` | Task 3 |
| Error overlay + Back button when `error` | Task 3 |
| `ended` → `ref.listen` → `context.go('/home')` | Task 3 |
| Router `/remote` → `RemoteScreen` | Task 4 |
| `remote_placeholder_screen.dart` kept (not deleted) | ✅ None of the tasks delete it |

All spec requirements covered. No gaps found.
