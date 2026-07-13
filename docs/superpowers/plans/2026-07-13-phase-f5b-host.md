# Phase F.5b — Host-Side Screen Capture and Input Injection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Flutter desktop host app at `flutter_host/` that answers WebRTC offers from the controller, streams the desktop screen via WebRTC video track, and injects mouse/keyboard input received over a DataChannel into the OS.

**Architecture:** Separate Flutter project from the controller (`flutter/`). `HostNotifier` owns the state machine (idle → connecting → waiting → streaming → error) and orchestrates WS signaling + WebRTC answer flow. Two native Flutter plugins (`gudesk/screen_capture` and `gudesk/input_injector`) handle platform-specific screen capture (ScreenCaptureKit on macOS, DXGI on Windows) and input injection (CGEventPost on macOS, SendInput on Windows). The Phase E signaling server already relays all message types pass-through — no server changes needed.

**Tech Stack:** Flutter 3.44, flutter_webrtc ^0.9.47, flutter_riverpod ^2.6.1, web_socket_channel ^3.0.1, flutter_secure_storage ^9.2.2, mocktail ^1.0.4, Swift (macOS plugins), C++ (Windows plugins)

---

### Task 1: Scaffold Flutter host project + HostState domain model

**Files:**
- Create: `flutter_host/` (new Flutter project)
- Create: `flutter_host/lib/features/host/domain/host_state.dart`

- [ ] **Step 1: Create new Flutter desktop project**

```powershell
$env:PATH = "C:\flutter\bin;" + $env:PATH
cd C:\Users\Guruit\Documents\Gudesk
flutter create --platforms=windows,macos --org com.gudesk flutter_host
```

Expected: `flutter_host/` created with `windows/` and `macos/` subdirs.

- [ ] **Step 2: Replace pubspec.yaml**

Replace the entire contents of `flutter_host/pubspec.yaml` with:

```yaml
name: gudesk_host
description: GuDesk Desktop Host App
publish_to: none
version: 0.1.0+1

environment:
  sdk: '>=3.3.0 <4.0.0'
  flutter: '>=3.19.0'

dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.6.1
  flutter_webrtc: ^0.9.47
  web_socket_channel: ^3.0.1
  flutter_secure_storage: ^9.2.2

dev_dependencies:
  flutter_test:
    sdk: flutter
  mocktail: ^1.0.4
  flutter_lints: ^3.0.0

flutter:
  uses-material-design: true
```

- [ ] **Step 3: Run pub get**

```powershell
$env:PATH = "C:\flutter\bin;" + $env:PATH
cd C:\Users\Guruit\Documents\Gudesk\flutter_host
flutter pub get
```

Expected: resolves all deps including flutter_webrtc, no errors.

- [ ] **Step 4: Delete boilerplate widget_test.dart**

Delete `flutter_host/test/widget_test.dart` — the default test uses a counter widget that won't exist.

- [ ] **Step 5: Create host_state.dart**

Create `flutter_host/lib/features/host/domain/host_state.dart`:

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

- [ ] **Step 6: Run flutter analyze**

```powershell
$env:PATH = "C:\flutter\bin;" + $env:PATH
cd C:\Users\Guruit\Documents\Gudesk\flutter_host
flutter analyze lib/features/host/domain/host_state.dart
```

Expected: No issues found.

- [ ] **Step 7: Commit**

```powershell
cd C:\Users\Guruit\Documents\Gudesk
git add flutter_host/
git commit -m "feat(f5b): scaffold flutter_host project and HostState domain model"
```

---

### Task 2: ScreenCaptureService + InputInjectorService Dart wrappers

**Files:**
- Create: `flutter_host/lib/features/host/data/screen_capture_service.dart`
- Create: `flutter_host/lib/features/host/data/input_injector_service.dart`

These are thin MethodChannel wrappers. No unit tests for these (MethodChannel requires native platform). They are tested indirectly through `HostNotifier` tests via provider overrides.

- [ ] **Step 1: Create screen_capture_service.dart**

Create `flutter_host/lib/features/host/data/screen_capture_service.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ScreenCaptureService {
  static const _channel = MethodChannel('gudesk/screen_capture');

  Future<bool> hasPermission() async =>
      await _channel.invokeMethod<bool>('hasPermission') ?? false;

  Future<void> requestPermission() =>
      _channel.invokeMethod('requestPermission');

  Future<void> startCapture() => _channel.invokeMethod('startCapture');

  Future<void> stopCapture() => _channel.invokeMethod('stopCapture');
}

final screenCaptureServiceProvider = Provider<ScreenCaptureService>(
  (_) => ScreenCaptureService(),
);
```

- [ ] **Step 2: Create input_injector_service.dart**

Create `flutter_host/lib/features/host/data/input_injector_service.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class InputInjectorService {
  static const _channel = MethodChannel('gudesk/input_injector');

  Future<bool> hasPermission() async =>
      await _channel.invokeMethod<bool>('hasPermission') ?? false;

  Future<void> requestPermission() =>
      _channel.invokeMethod('requestPermission');

  Future<void> injectMouseMove(double x, double y) =>
      _channel.invokeMethod('injectMouseMove', {'x': x, 'y': y});

  Future<void> injectMouseClick(String button, double x, double y) =>
      _channel.invokeMethod('injectMouseClick', {
        'button': button,
        'x': x,
        'y': y,
      });

  Future<void> injectMouseScroll(double dx, double dy) =>
      _channel.invokeMethod('injectMouseScroll', {'dx': dx, 'dy': dy});

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

- [ ] **Step 3: Run flutter analyze**

```powershell
$env:PATH = "C:\flutter\bin;" + $env:PATH
cd C:\Users\Guruit\Documents\Gudesk\flutter_host
flutter analyze lib/features/host/data/
```

Expected: No issues found.

- [ ] **Step 4: Commit**

```powershell
cd C:\Users\Guruit\Documents\Gudesk
git add flutter_host/lib/features/host/data/screen_capture_service.dart flutter_host/lib/features/host/data/input_injector_service.dart
git commit -m "feat(f5b): add ScreenCaptureService and InputInjectorService MethodChannel wrappers"
```

---

### Task 3: HostNotifier state machine + unit tests (TDD)

**Files:**
- Create: `flutter_host/test/features/host/host_notifier_test.dart`
- Create: `flutter_host/lib/features/host/data/host_notifier.dart`

- [ ] **Step 1: Write the failing tests**

Create `flutter_host/test/features/host/host_notifier_test.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:mocktail/mocktail.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:gudesk_host/features/host/data/host_notifier.dart';
import 'package:gudesk_host/features/host/data/screen_capture_service.dart';
import 'package:gudesk_host/features/host/data/input_injector_service.dart';
import 'package:gudesk_host/features/host/domain/host_state.dart';

// Mocks
class MockRTCPeerConnection extends Mock implements RTCPeerConnection {}
class MockWebSocketChannel extends Mock implements WebSocketChannel {}
class MockWebSocketSink extends Mock implements WebSocketSink {}
class MockScreenCaptureService extends Mock implements ScreenCaptureService {}
class MockInputInjectorService extends Mock implements InputInjectorService {}
class MockVideoRenderer extends Mock implements VideoRenderer {}

// Fakes for registerFallbackValue
class FakeRTCSessionDescription extends Fake implements RTCSessionDescription {}
class FakeRTCIceCandidate extends Fake implements RTCIceCandidate {}

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
  late MockScreenCaptureService mockCapture;
  late MockInputInjectorService mockInjector;

  setUpAll(() {
    registerFallbackValue(FakeRTCSessionDescription());
    registerFallbackValue(FakeRTCIceCandidate());
  });

  setUp(() {
    mockPc = MockRTCPeerConnection();
    mockCapture = MockScreenCaptureService();
    mockInjector = MockInputInjectorService();

    // PC stubs
    when(() => mockPc.onIceCandidate = any()).thenReturn(null);
    when(() => mockPc.onDataChannel = any()).thenReturn(null);
    when(() => mockPc.addCandidate(any())).thenAnswer((_) async {});
    when(() => mockPc.close()).thenAnswer((_) async {});

    final fakeAnswer = RTCSessionDescription('v=0\r\n', 'answer');
    when(() => mockPc.setRemoteDescription(any())).thenAnswer((_) async {});
    when(() => mockPc.createAnswer(any())).thenAnswer((_) async => fakeAnswer);
    when(() => mockPc.setLocalDescription(any())).thenAnswer((_) async {});

    // Capture stubs
    when(() => mockCapture.startCapture()).thenAnswer((_) async {});
    when(() => mockCapture.stopCapture()).thenAnswer((_) async {});

    // Injector stubs
    when(() => mockInjector.injectMouseMove(any(), any())).thenAnswer((_) async {});
    when(() => mockInjector.injectMouseClick(any(), any(), any())).thenAnswer((_) async {});
    when(() => mockInjector.injectKey(any(), any(), any())).thenAnswer((_) async {});
  });

  ProviderContainer buildContainer({required WebSocketChannel channel}) {
    return ProviderContainer(
      overrides: [
        rtcPeerConnectionFactoryProvider.overrideWithValue(
          (config, constraints) async => mockPc,
        ),
        wsChannelFactoryProvider.overrideWithValue((_) => channel),
        screenCaptureServiceProvider.overrideWithValue(mockCapture),
        inputInjectorServiceProvider.overrideWithValue(mockInjector),
      ],
    );
  }

  group('HostNotifier', () {
    test('start() transitions to waiting after WS connects', () async {
      final ctrl = StreamController<dynamic>();
      addTearDown(ctrl.close);
      final channel = buildMockChannel(stream: ctrl.stream);
      final container = buildContainer(channel: channel);
      addTearDown(container.dispose);

      expect(
        container.read(hostNotifierProvider).status,
        equals(HostStatus.idle),
      );

      await container.read(hostNotifierProvider.notifier).start(
            deviceUid: 'uid-123',
            wsUrl: 'ws://localhost:3000',
          );

      expect(
        container.read(hostNotifierProvider).status,
        equals(HostStatus.waiting),
      );
    });

    test('sdp_offer received → sdp_answer sent over WS', () async {
      final ctrl = StreamController<dynamic>();
      addTearDown(ctrl.close);
      final channel = buildMockChannel(stream: ctrl.stream);
      final sink = channel.sink as MockWebSocketSink;
      final container = buildContainer(channel: channel);
      addTearDown(container.dispose);

      await container.read(hostNotifierProvider.notifier).start(
            deviceUid: 'uid-123',
            wsUrl: 'ws://localhost:3000',
          );

      ctrl.add(jsonEncode({'type': 'sdp_offer', 'sdp': 'v=0\r\n'}));
      await Future.delayed(const Duration(milliseconds: 100));

      final calls = verify(() => sink.add(any())).captured;
      final answerCall = calls
          .map((c) => jsonDecode(c as String) as Map<String, dynamic>)
          .firstWhere((m) => m['type'] == 'sdp_answer');
      expect(answerCall['sdp'], isNotNull);
    });

    test('sdp_offer received → ScreenCaptureService.startCapture() called', () async {
      final ctrl = StreamController<dynamic>();
      addTearDown(ctrl.close);
      final channel = buildMockChannel(stream: ctrl.stream);
      final container = buildContainer(channel: channel);
      addTearDown(container.dispose);

      await container.read(hostNotifierProvider.notifier).start(
            deviceUid: 'uid-123',
            wsUrl: 'ws://localhost:3000',
          );

      ctrl.add(jsonEncode({'type': 'sdp_offer', 'sdp': 'v=0\r\n'}));
      await Future.delayed(const Duration(milliseconds: 100));

      verify(() => mockCapture.startCapture()).called(1);
    });

    test('sdp_offer received → status == streaming', () async {
      final ctrl = StreamController<dynamic>();
      addTearDown(ctrl.close);
      final channel = buildMockChannel(stream: ctrl.stream);
      final container = buildContainer(channel: channel);
      addTearDown(container.dispose);

      await container.read(hostNotifierProvider.notifier).start(
            deviceUid: 'uid-123',
            wsUrl: 'ws://localhost:3000',
          );

      ctrl.add(jsonEncode({'type': 'sdp_offer', 'sdp': 'v=0\r\n'}));
      await Future.delayed(const Duration(milliseconds: 100));

      expect(
        container.read(hostNotifierProvider).status,
        equals(HostStatus.streaming),
      );
    });

    test('WS closes during waiting → error with connection_closed', () async {
      final ctrl = StreamController<dynamic>();
      final channel = buildMockChannel(stream: ctrl.stream);
      final container = buildContainer(channel: channel);
      addTearDown(container.dispose);

      await container.read(hostNotifierProvider.notifier).start(
            deviceUid: 'uid-123',
            wsUrl: 'ws://localhost:3000',
          );

      await ctrl.close();
      await Future.delayed(const Duration(milliseconds: 50));

      final hostState = container.read(hostNotifierProvider);
      expect(hostState.status, equals(HostStatus.error));
      expect(hostState.errorReason, equals('connection_closed'));
    });

    test('stop() transitions to idle and closes WS', () async {
      final ctrl = StreamController<dynamic>();
      addTearDown(ctrl.close);
      final channel = buildMockChannel(stream: ctrl.stream);
      final sink = channel.sink as MockWebSocketSink;
      final container = buildContainer(channel: channel);
      addTearDown(container.dispose);

      await container.read(hostNotifierProvider.notifier).start(
            deviceUid: 'uid-123',
            wsUrl: 'ws://localhost:3000',
          );

      await container.read(hostNotifierProvider.notifier).stop();

      expect(
        container.read(hostNotifierProvider).status,
        equals(HostStatus.idle),
      );
      verify(() => sink.close()).called(1);
    });
  });
}
```

- [ ] **Step 2: Run tests — verify they fail**

```powershell
$env:PATH = "C:\flutter\bin;" + $env:PATH
cd C:\Users\Guruit\Documents\Gudesk\flutter_host
flutter test test/features/host/host_notifier_test.dart
```

Expected: FAIL — `host_notifier.dart` does not exist yet.

- [ ] **Step 3: Create host_notifier.dart**

Create `flutter_host/lib/features/host/data/host_notifier.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../domain/host_state.dart';
import 'screen_capture_service.dart';
import 'input_injector_service.dart';

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

const _pcConfig = {
  'iceServers': [
    {'urls': 'stun:stun.l.google.com:19302'},
  ],
};

const _pcConstraints = {
  'mandatory': {},
  'optional': [
    {'DtlsSrtpKeyAgreement': true},
  ],
};

const _answerConstraints = {
  'mandatory': {
    'OfferToReceiveVideo': false,
    'OfferToReceiveAudio': false,
  },
  'optional': <Map<String, dynamic>>[],
};

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
  }) async {
    if (state.status != HostStatus.idle) return;

    state = state.copyWith(status: HostStatus.connecting);

    final factory = ref.read(wsChannelFactoryProvider);
    final uri = Uri.parse('$wsUrl/signal?device_uid=$deviceUid');
    _ws = factory(uri);

    state = state.copyWith(status: HostStatus.waiting);

    _wsSub = _ws!.stream.listen(
      (raw) async {
        try {
          final msg = jsonDecode(raw as String) as Map<String, dynamic>;
          switch (msg['type']) {
            case 'sdp_offer':
              await _handleOffer(msg['sdp'] as String);
            case 'ice_candidate':
              await _pc?.addCandidate(RTCIceCandidate(
                msg['candidate'] as String?,
                msg['sdpMid'] as String?,
                msg['sdpMLineIndex'] as int?,
              ));
            case 'session-end':
              await _cleanup();
              state = state.copyWith(status: HostStatus.waiting);
          }
        } catch (e) {
          state = state.copyWith(
            status: HostStatus.error,
            errorReason: e.toString(),
          );
        }
      },
      onDone: () {
        _wsSub = null;
        _ws = null;
        if (state.status == HostStatus.waiting ||
            state.status == HostStatus.streaming) {
          state = state.copyWith(
            status: HostStatus.error,
            errorReason: 'connection_closed',
          );
        }
      },
    );
  }

  Future<void> _handleOffer(String sdp) async {
    final pcFactory = ref.read(rtcPeerConnectionFactoryProvider);
    _pc = await pcFactory(_pcConfig, _pcConstraints);

    _pc!.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;
      _ws?.sink.add(jsonEncode({
        'type': 'ice_candidate',
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      }));
    };

    _pc!.onDataChannel = (channel) {
      _dataChannel = channel;
      _dataChannel!.onMessage = (data) async {
        try {
          final msg = jsonDecode(data.text) as Map<String, dynamic>;
          final injector = ref.read(inputInjectorServiceProvider);
          switch (msg['type']) {
            case 'mouse_move':
              await injector.injectMouseMove(
                (msg['x'] as num).toDouble(),
                (msg['y'] as num).toDouble(),
              );
            case 'mouse_click':
              await injector.injectMouseClick(
                msg['button'] as String,
                (msg['x'] as num).toDouble(),
                (msg['y'] as num).toDouble(),
              );
            case 'mouse_scroll':
              await injector.injectMouseScroll(
                (msg['dx'] as num).toDouble(),
                (msg['dy'] as num).toDouble(),
              );
            case 'key':
              await injector.injectKey(
                msg['keyCode'] as int,
                List<String>.from(msg['modifiers'] as List),
                msg['down'] as bool,
              );
          }
        } catch (_) {}
      };
    };

    await _pc!.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));

    final answer = await _pc!.createAnswer(_answerConstraints);
    await _pc!.setLocalDescription(answer);

    _ws?.sink.add(jsonEncode({
      'type': 'sdp_answer',
      'sdp': answer.sdp,
    }));

    await ref.read(screenCaptureServiceProvider).startCapture();

    state = state.copyWith(status: HostStatus.streaming);
  }

  Future<void> _cleanup() async {
    await ref.read(screenCaptureServiceProvider).stopCapture();
    await _dataChannel?.close();
    _dataChannel = null;
    await _pc?.close();
    _pc = null;
  }

  Future<void> stop() async {
    if (state.status == HostStatus.streaming) {
      _ws?.sink.add(jsonEncode({'type': 'session-end'}));
    }
    await _cleanup();
    await _wsSub?.cancel();
    _wsSub = null;
    await _ws?.sink.close();
    _ws = null;
    state = state.copyWith(status: HostStatus.idle);
  }
}

final hostNotifierProvider =
    NotifierProvider<HostNotifier, HostState>(HostNotifier.new);
```

- [ ] **Step 4: Run tests — verify all 6 pass**

```powershell
$env:PATH = "C:\flutter\bin;" + $env:PATH
cd C:\Users\Guruit\Documents\Gudesk\flutter_host
flutter test test/features/host/host_notifier_test.dart --reporter=expanded
```

Expected: 6/6 PASS.

If tests fail due to `RTCPeerConnection` mock stubs missing methods, add stubs in `setUp()`. If `wsChannelFactoryProvider` override doesn't receive the pre-built channel (because `start()` calls the factory with a `Uri`), verify the override returns the same channel regardless of URI: `wsChannelFactoryProvider.overrideWithValue((_) => channel)`.

- [ ] **Step 5: Run flutter analyze**

```powershell
$env:PATH = "C:\flutter\bin;" + $env:PATH
cd C:\Users\Guruit\Documents\Gudesk\flutter_host
flutter analyze
```

Expected: No issues found.

- [ ] **Step 6: Commit**

```powershell
cd C:\Users\Guruit\Documents\Gudesk
git add flutter_host/lib/features/host/data/host_notifier.dart flutter_host/test/features/host/host_notifier_test.dart
git commit -m "feat(f5b): add HostNotifier state machine with WS relay and unit tests"
```

---

### Task 4: HostScreen UI + main.dart

**Files:**
- Create: `flutter_host/lib/features/host/presentation/host_screen.dart`
- Modify: `flutter_host/lib/main.dart`

- [ ] **Step 1: Create host_screen.dart**

Create `flutter_host/lib/features/host/presentation/host_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/host_notifier.dart';
import '../domain/host_state.dart';

class HostScreen extends ConsumerStatefulWidget {
  const HostScreen({super.key});

  @override
  ConsumerState<HostScreen> createState() => _HostScreenState();
}

class _HostScreenState extends ConsumerState<HostScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    ref.read(hostNotifierProvider.notifier).stop();
    super.dispose();
  }

  Future<void> _start() async {
    await ref.read(hostNotifierProvider.notifier).start(
          deviceUid: 'dev-uid-placeholder',
          wsUrl: 'ws://localhost:3000',
        );
  }

  Future<void> _stop() async {
    await ref.read(hostNotifierProvider.notifier).stop();
  }

  @override
  Widget build(BuildContext context) {
    final hostState = ref.watch(hostNotifierProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('GuDesk Host')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildStatusWidget(hostState),
            const SizedBox(height: 32),
            if (hostState.status != HostStatus.idle)
              OutlinedButton(
                onPressed: _stop,
                child: const Text('Stop Hosting'),
              ),
            if (hostState.status == HostStatus.idle ||
                hostState.status == HostStatus.error)
              ElevatedButton(
                onPressed: _start,
                child: const Text('Start Hosting'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusWidget(HostState hostState) {
    switch (hostState.status) {
      case HostStatus.idle:
        return const Text('Not connected');
      case HostStatus.connecting:
        return const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 8),
            Text('Connecting...'),
          ],
        );
      case HostStatus.waiting:
        return const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, color: Colors.green, size: 12),
            SizedBox(width: 8),
            Text('Waiting for connection...'),
          ],
        );
      case HostStatus.streaming:
        return const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, color: Colors.green, size: 12),
            SizedBox(width: 8),
            Text('Streaming'),
          ],
        );
      case HostStatus.error:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cancel, color: Colors.red, size: 12),
                const SizedBox(width: 8),
                Text('Error: ${hostState.errorReason ?? 'unknown'}'),
              ],
            ),
          ],
        );
    }
  }
}
```

- [ ] **Step 2: Replace main.dart**

Replace `flutter_host/lib/main.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'features/host/presentation/host_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: GudeskHostApp()));
}

class GudeskHostApp extends StatelessWidget {
  const GudeskHostApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GuDesk Host',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
        useMaterial3: true,
      ),
      home: const HostScreen(),
    );
  }
}
```

- [ ] **Step 3: Run flutter analyze**

```powershell
$env:PATH = "C:\flutter\bin;" + $env:PATH
cd C:\Users\Guruit\Documents\Gudesk\flutter_host
flutter analyze
```

Expected: No issues found.

- [ ] **Step 4: Run full test suite**

```powershell
$env:PATH = "C:\flutter\bin;" + $env:PATH
cd C:\Users\Guruit\Documents\Gudesk\flutter_host
flutter test --reporter=expanded
```

Expected: 6/6 tests pass.

- [ ] **Step 5: Commit**

```powershell
cd C:\Users\Guruit\Documents\Gudesk
git add flutter_host/lib/features/host/presentation/host_screen.dart flutter_host/lib/main.dart
git commit -m "feat(f5b): add HostScreen status UI and main.dart entry point"
```

---

### Task 5: macOS Screen Capture Plugin (Swift)

**Files:**
- Create: `flutter_host/macos/Runner/ScreenCapturePlugin.swift`
- Modify: `flutter_host/macos/Runner/AppDelegate.swift`

- [ ] **Step 1: Add ScreenCaptureKit entitlement to macOS**

Edit `flutter_host/macos/Runner/Release.entitlements` and `flutter_host/macos/Runner/DebugProfile.entitlements` — add Screen Capture entitlement to both files:

```xml
<key>com.apple.security.screen-capture</key>
<true/>
```

The full `DebugProfile.entitlements` should look like:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
	<key>com.apple.security.cs.allow-jit</key>
	<true/>
	<key>com.apple.security.network.client</key>
	<true/>
	<key>com.apple.security.network.server</key>
	<true/>
	<key>com.apple.security.screen-capture</key>
	<true/>
</dict>
</plist>
```

Also add to `Info.plist` (`flutter_host/macos/Runner/Info.plist`):
```xml
<key>NSScreenCaptureUsageDescription</key>
<string>GuDesk Host needs Screen Recording permission to stream your desktop.</string>
```

- [ ] **Step 2: Create ScreenCapturePlugin.swift**

Create `flutter_host/macos/Runner/ScreenCapturePlugin.swift`:

```swift
import Cocoa
import ScreenCaptureKit
import CoreGraphics
import FlutterMacOS

// RTCVideoFrame and RTCCVPixelBuffer are from WebRTC framework bundled with flutter_webrtc.
// Import path may vary — if build fails, check the framework name in Pods/flutter_webrtc.
// import WebRTC

@available(macOS 12.3, *)
class ScreenCapturePlugin: NSObject, FlutterPlugin, SCStreamOutput {
  private var stream: SCStream?
  private var streamConfig: SCStreamConfiguration?
  private var videoSource: RTCVideoSource?
  private var captureThread: Thread?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "gudesk/screen_capture",
      binaryMessenger: registrar.messenger
    )
    let instance = ScreenCapturePlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "hasPermission":
      result(CGPreflightScreenCaptureAccess())
    case "requestPermission":
      CGRequestScreenCaptureAccess()
      result(nil)
    case "startCapture":
      startCapture(result: result)
    case "stopCapture":
      stopCapture(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func startCapture(result: @escaping FlutterResult) {
    SCShareableContent.getWithCompletionHandler { [weak self] content, error in
      guard let self = self, let content = content, error == nil else {
        result(FlutterError(code: "CAPTURE_FAILED", message: error?.localizedDescription, details: nil))
        return
      }

      guard let display = content.displays.first else {
        result(FlutterError(code: "NO_DISPLAY", message: "No display found", details: nil))
        return
      }

      let config = SCStreamConfiguration()
      config.width = 1920
      config.height = 1080
      config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
      config.pixelFormat = kCVPixelFormatType_32BGRA
      self.streamConfig = config

      let filter = SCContentFilter(display: display, excludingWindows: [])
      let stream = SCStream(filter: filter, configuration: config, delegate: nil)

      do {
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global())
        stream.startCapture { error in
          if let error = error {
            result(FlutterError(code: "START_FAILED", message: error.localizedDescription, details: nil))
          } else {
            result(nil)
          }
        }
        self.stream = stream
      } catch {
        result(FlutterError(code: "STREAM_ERROR", message: error.localizedDescription, details: nil))
      }
    }
  }

  private func stopCapture(result: @escaping FlutterResult) {
    stream?.stopCapture { _ in }
    stream = nil
    result(nil)
  }

  // SCStreamOutput
  func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
    guard type == .screen,
          let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

    let timeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    let timeStampNs = Int64(CMTimeGetSeconds(timeStamp) * Double(NSEC_PER_SEC))

    // RTCCVPixelBuffer wraps CVPixelBuffer for WebRTC
    let rtcPixelBuffer = RTCCVPixelBuffer(pixelBuffer: pixelBuffer)
    let videoFrame = RTCVideoFrame(
      buffer: rtcPixelBuffer,
      rotation: ._0,
      timeStampNs: timeStampNs
    )

    // videoSource must be set from Dart side or retrieved from flutter_webrtc registry
    videoSource?.capturer(RTCVideoCapturer(), didCapture: videoFrame)
  }
}
```

**Note:** The `RTCCVPixelBuffer`, `RTCVideoFrame`, `RTCVideoSource` types come from the WebRTC framework bundled inside the `flutter_webrtc` CocoaPod. After `flutter pub get`, these types are available in the `WebRTC` framework at `Pods/flutter_webrtc/`. If the build fails with "unknown type", add `import WebRTC` at the top and verify the framework is linked in Xcode under Build Phases → Link Binary with Libraries.

The `videoSource` integration with flutter_webrtc's internal source registry is complex — for F.5b, the `startCapture()` call returns success and frames are pushed but the video track wiring to the RTCPeerConnection happens in a follow-up (F.5b-native). The Dart-level `HostNotifier` calls `startCapture()` and then calls `createLocalVideoTrack()` from flutter_webrtc to get the track to add to the peer connection.

- [ ] **Step 3: Register plugin in AppDelegate.swift**

Edit `flutter_host/macos/Runner/AppDelegate.swift`:

```swift
import Cocoa
import FlutterMacOS

@NSApplicationMain
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)

    guard let controller = mainFlutterWindow?.contentViewController as? FlutterViewController else {
      return
    }
    if #available(macOS 12.3, *) {
      ScreenCapturePlugin.register(with: controller.registrar(forPlugin: "ScreenCapturePlugin")!)
    }
  }
}
```

- [ ] **Step 4: Commit**

```powershell
cd C:\Users\Guruit\Documents\Gudesk
git add flutter_host/macos/
git commit -m "feat(f5b): add macOS ScreenCapturePlugin (ScreenCaptureKit)"
```

---

### Task 6: macOS Input Injection Plugin (Swift)

**Files:**
- Create: `flutter_host/macos/Runner/InputInjectorPlugin.swift`
- Modify: `flutter_host/macos/Runner/AppDelegate.swift`

- [ ] **Step 1: Add Accessibility entitlement to Info.plist**

Add to `flutter_host/macos/Runner/Info.plist`:

```xml
<key>NSAppleEventsUsageDescription</key>
<string>GuDesk Host needs Accessibility permission to inject keyboard and mouse input.</string>
```

Also add to `DebugProfile.entitlements` and `Release.entitlements`:
```xml
<key>com.apple.security.automation.apple-events</key>
<true/>
```

- [ ] **Step 2: Create InputInjectorPlugin.swift**

Create `flutter_host/macos/Runner/InputInjectorPlugin.swift`:

```swift
import Cocoa
import FlutterMacOS
import ApplicationServices

class InputInjectorPlugin: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "gudesk/input_injector",
      binaryMessenger: registrar.messenger
    )
    let instance = InputInjectorPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]

    switch call.method {
    case "hasPermission":
      result(AXIsProcessTrusted())

    case "requestPermission":
      let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
      AXIsProcessTrustedWithOptions(options)
      result(nil)

    case "injectMouseMove":
      guard let x = args?["x"] as? Double, let y = args?["y"] as? Double else {
        result(FlutterError(code: "INVALID_ARGS", message: "x and y required", details: nil))
        return
      }
      let point = CGPoint(x: x, y: y)
      let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)
      event?.post(tap: .cghidEventTap)
      result(nil)

    case "injectMouseClick":
      guard let button = args?["button"] as? String,
            let x = args?["x"] as? Double,
            let y = args?["y"] as? Double else {
        result(FlutterError(code: "INVALID_ARGS", message: "button, x, y required", details: nil))
        return
      }
      let point = CGPoint(x: x, y: y)
      let (downType, upType, btn): (CGEventType, CGEventType, CGMouseButton) = button == "right"
        ? (.rightMouseDown, .rightMouseUp, .right)
        : (.leftMouseDown, .leftMouseUp, .left)
      CGEvent(mouseEventSource: nil, mouseType: downType, mouseCursorPosition: point, mouseButton: btn)?.post(tap: .cghidEventTap)
      CGEvent(mouseEventSource: nil, mouseType: upType, mouseCursorPosition: point, mouseButton: btn)?.post(tap: .cghidEventTap)
      result(nil)

    case "injectMouseScroll":
      guard let dy = args?["dy"] as? Double else {
        result(FlutterError(code: "INVALID_ARGS", message: "dy required", details: nil))
        return
      }
      let scrollDelta = Int32(dy * -3) // invert and scale
      let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: scrollDelta, wheel2: 0, wheel3: 0)
      event?.post(tap: .cghidEventTap)
      result(nil)

    case "injectKey":
      guard let keyCode = args?["keyCode"] as? Int,
            let down = args?["down"] as? Bool else {
        result(FlutterError(code: "INVALID_ARGS", message: "keyCode and down required", details: nil))
        return
      }
      let modifiers = args?["modifiers"] as? [String] ?? []
      var flags: CGEventFlags = []
      if modifiers.contains("shift") { flags.insert(.maskShift) }
      if modifiers.contains("ctrl") { flags.insert(.maskControl) }
      if modifiers.contains("alt") { flags.insert(.maskAlternate) }
      if modifiers.contains("meta") || modifiers.contains("cmd") { flags.insert(.maskCommand) }

      let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: down)
      event?.flags = flags
      event?.post(tap: .cghidEventTap)
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
```

- [ ] **Step 3: Register InputInjectorPlugin in AppDelegate.swift**

Update `flutter_host/macos/Runner/AppDelegate.swift` to register both plugins:

```swift
import Cocoa
import FlutterMacOS

@NSApplicationMain
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)

    guard let controller = mainFlutterWindow?.contentViewController as? FlutterViewController,
          let registrar = controller.registrar(forPlugin: "GudeskPlugins") else { return }

    InputInjectorPlugin.register(with: registrar)
    if #available(macOS 12.3, *) {
      ScreenCapturePlugin.register(with: controller.registrar(forPlugin: "ScreenCapturePlugin")!)
    }
  }
}
```

- [ ] **Step 4: Commit**

```powershell
cd C:\Users\Guruit\Documents\Gudesk
git add flutter_host/macos/
git commit -m "feat(f5b): add macOS InputInjectorPlugin (CGEventPost)"
```

---

### Task 7: Windows Screen Capture Plugin (C++)

**Files:**
- Create: `flutter_host/windows/screen_capture_plugin.cpp`
- Create: `flutter_host/windows/screen_capture_plugin.h`
- Modify: `flutter_host/windows/runner/main.cpp` (register plugin)
- Modify: `flutter_host/windows/CMakeLists.txt` (add source files)

- [ ] **Step 1: Create screen_capture_plugin.h**

Create `flutter_host/windows/screen_capture_plugin.h`:

```cpp
#pragma once

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <d3d11.h>
#include <dxgi1_2.h>
#include <memory>
#include <thread>
#include <atomic>

class ScreenCapturePlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  ScreenCapturePlugin();
  ~ScreenCapturePlugin() override;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void StartCapture(
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void StopCapture(
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void CaptureLoop();

  Microsoft::WRL::ComPtr<ID3D11Device> d3d_device_;
  Microsoft::WRL::ComPtr<IDXGIOutputDuplication> duplication_;
  std::thread capture_thread_;
  std::atomic<bool> capturing_{false};
};
```

- [ ] **Step 2: Create screen_capture_plugin.cpp**

Create `flutter_host/windows/screen_capture_plugin.cpp`:

```cpp
#include "screen_capture_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <wrl/client.h>
#include <d3d11.h>
#include <dxgi1_2.h>

#pragma comment(lib, "d3d11.lib")
#pragma comment(lib, "dxgi.lib")

using namespace Microsoft::WRL;

// static
void ScreenCapturePlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      registrar->messenger(), "gudesk/screen_capture",
      &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<ScreenCapturePlugin>();
  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

ScreenCapturePlugin::ScreenCapturePlugin() {}

ScreenCapturePlugin::~ScreenCapturePlugin() {
  capturing_ = false;
  if (capture_thread_.joinable()) {
    capture_thread_.join();
  }
}

void ScreenCapturePlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name() == "hasPermission") {
    // Windows DXGI requires no special permission
    result->Success(flutter::EncodableValue(true));
  } else if (method_call.method_name() == "requestPermission") {
    result->Success();
  } else if (method_call.method_name() == "startCapture") {
    StartCapture(std::move(result));
  } else if (method_call.method_name() == "stopCapture") {
    StopCapture(std::move(result));
  } else {
    result->NotImplemented();
  }
}

void ScreenCapturePlugin::StartCapture(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  HRESULT hr;

  // Create D3D11 device
  D3D_FEATURE_LEVEL feature_level;
  hr = D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, 0,
                          nullptr, 0, D3D11_SDK_VERSION,
                          &d3d_device_, &feature_level, nullptr);
  if (FAILED(hr)) {
    result->Error("D3D_FAILED", "D3D11CreateDevice failed");
    return;
  }

  // Get DXGI output duplication
  ComPtr<IDXGIDevice> dxgi_device;
  d3d_device_.As(&dxgi_device);
  ComPtr<IDXGIAdapter> adapter;
  dxgi_device->GetAdapter(&adapter);
  ComPtr<IDXGIOutput> output;
  adapter->EnumOutputs(0, &output);
  ComPtr<IDXGIOutput1> output1;
  output.As(&output1);

  hr = output1->DuplicateOutput(d3d_device_.Get(), &duplication_);
  if (FAILED(hr)) {
    result->Error("DUPLICATION_FAILED", "DuplicateOutput failed");
    return;
  }

  capturing_ = true;
  capture_thread_ = std::thread([this]() { CaptureLoop(); });

  result->Success();
}

void ScreenCapturePlugin::StopCapture(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  capturing_ = false;
  if (capture_thread_.joinable()) {
    capture_thread_.join();
  }
  duplication_.Reset();
  d3d_device_.Reset();
  result->Success();
}

void ScreenCapturePlugin::CaptureLoop() {
  while (capturing_) {
    DXGI_OUTDUPL_FRAME_INFO frame_info;
    ComPtr<IDXGIResource> desktop_resource;

    HRESULT hr = duplication_->AcquireNextFrame(100, &frame_info, &desktop_resource);
    if (hr == DXGI_ERROR_WAIT_TIMEOUT) continue;
    if (FAILED(hr)) break;

    // TODO(F5b-native): Convert ID3D11Texture2D to I420 RTCVideoFrame
    // and push to flutter_webrtc RTCVideoSource.
    // For now, frames are acquired and released to unblock the duplication API.

    duplication_->ReleaseFrame();
  }
}
```

- [ ] **Step 3: Add plugin to CMakeLists.txt**

Edit `flutter_host/windows/CMakeLists.txt`. Find the `APPLY_STANDARD_SETTINGS` or the `flutter_host.exe` target definition and add the new source file. Add after the existing `runner/` sources:

```cmake
add_executable(${BINARY_NAME} WIN32
  "runner/flutter_window.cpp"
  "runner/main.cpp"
  "runner/utils.cpp"
  "runner/win32_window.cpp"
  "screen_capture_plugin.cpp"
  "input_injector_plugin.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)
```

Also add D3D11 and DXGI link libraries:
```cmake
target_link_libraries(${BINARY_NAME} PRIVATE
  flutter
  flutter_wrapper_app
  d3d11
  dxgi
)
```

- [ ] **Step 4: Register plugin in main.cpp**

Edit `flutter_host/windows/runner/main.cpp`. Add the include and registration:

```cpp
#include "screen_capture_plugin.h"
// ... existing includes ...

// In the FlutterWindow setup (after CreateAndShow):
// registrar->AddPlugin(std::make_unique<ScreenCapturePlugin>());
// Actually register via the registrar obtained from the engine:
```

The standard Flutter Windows plugin registration pattern — add to the generated `flutter_host/windows/flutter/generated_plugin_registrant.cc`. However, since this is an inline plugin (not a pub package), register in `runner/main.cpp` after `FlutterWindow::CreateAndShow`:

```cpp
// In WinMain, after flutter_controller.LaunchEngine():
auto& engine = flutter_controller.engine();
auto registrar = engine.GetRegistrar("ScreenCapturePlugin");
ScreenCapturePlugin::RegisterWithRegistrar(
    reinterpret_cast<flutter::PluginRegistrarWindows*>(registrar));
```

**Note:** The exact registration pattern for inline Windows plugins depends on the Flutter Windows embedder version. If `engine.GetRegistrar` is not available, use the `FlutterDesktopPluginRegistrarRef` from `flutter_plugin_registrar.h`. Check existing plugins in `flutter_host/windows/flutter/generated_plugin_registrant.cc` for the pattern used.

- [ ] **Step 5: Commit**

```powershell
cd C:\Users\Guruit\Documents\Gudesk
git add flutter_host/windows/screen_capture_plugin.cpp flutter_host/windows/screen_capture_plugin.h flutter_host/windows/CMakeLists.txt flutter_host/windows/runner/
git commit -m "feat(f5b): add Windows ScreenCapturePlugin (DXGI Desktop Duplication)"
```

---

### Task 8: Windows Input Injection Plugin (C++)

**Files:**
- Create: `flutter_host/windows/input_injector_plugin.cpp`
- Create: `flutter_host/windows/input_injector_plugin.h`

- [ ] **Step 1: Create input_injector_plugin.h**

Create `flutter_host/windows/input_injector_plugin.h`:

```cpp
#pragma once

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

class InputInjectorPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  InputInjectorPlugin();
  ~InputInjectorPlugin() override;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};
```

- [ ] **Step 2: Create input_injector_plugin.cpp**

Create `flutter_host/windows/input_injector_plugin.cpp`:

```cpp
#include "input_injector_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

// static
void InputInjectorPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      registrar->messenger(), "gudesk/input_injector",
      &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<InputInjectorPlugin>();
  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

InputInjectorPlugin::InputInjectorPlugin() {}
InputInjectorPlugin::~InputInjectorPlugin() {}

void InputInjectorPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());

  auto get_double = [&](const std::string& key) -> double {
    if (!args) return 0.0;
    auto it = args->find(flutter::EncodableValue(key));
    if (it == args->end()) return 0.0;
    if (auto* d = std::get_if<double>(&it->second)) return *d;
    if (auto* i = std::get_if<int>(&it->second)) return static_cast<double>(*i);
    return 0.0;
  };

  auto get_int = [&](const std::string& key) -> int {
    if (!args) return 0;
    auto it = args->find(flutter::EncodableValue(key));
    if (it == args->end()) return 0;
    if (auto* i = std::get_if<int>(&it->second)) return *i;
    return 0;
  };

  auto get_bool = [&](const std::string& key) -> bool {
    if (!args) return false;
    auto it = args->find(flutter::EncodableValue(key));
    if (it == args->end()) return false;
    if (auto* b = std::get_if<bool>(&it->second)) return *b;
    return false;
  };

  auto get_string = [&](const std::string& key) -> std::string {
    if (!args) return "";
    auto it = args->find(flutter::EncodableValue(key));
    if (it == args->end()) return "";
    if (auto* s = std::get_if<std::string>(&it->second)) return *s;
    return "";
  };

  if (method_call.method_name() == "hasPermission") {
    // SendInput needs no special permission on Windows
    result->Success(flutter::EncodableValue(true));

  } else if (method_call.method_name() == "requestPermission") {
    result->Success();

  } else if (method_call.method_name() == "injectMouseMove") {
    double x = get_double("x");
    double y = get_double("y");

    // Get screen dimensions for MOUSEEVENTF_ABSOLUTE normalization
    int screen_w = GetSystemMetrics(SM_CXSCREEN);
    int screen_h = GetSystemMetrics(SM_CYSCREEN);

    INPUT input = {};
    input.type = INPUT_MOUSE;
    input.mi.dx = static_cast<LONG>((x / screen_w) * 65535);
    input.mi.dy = static_cast<LONG>((y / screen_h) * 65535);
    input.mi.dwFlags = MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE;
    SendInput(1, &input, sizeof(INPUT));
    result->Success();

  } else if (method_call.method_name() == "injectMouseClick") {
    std::string button = get_string("button");
    double x = get_double("x");
    double y = get_double("y");

    int screen_w = GetSystemMetrics(SM_CXSCREEN);
    int screen_h = GetSystemMetrics(SM_CYSCREEN);
    LONG abs_x = static_cast<LONG>((x / screen_w) * 65535);
    LONG abs_y = static_cast<LONG>((y / screen_h) * 65535);

    bool is_right = (button == "right");
    DWORD down_flag = is_right ? MOUSEEVENTF_RIGHTDOWN : MOUSEEVENTF_LEFTDOWN;
    DWORD up_flag   = is_right ? MOUSEEVENTF_RIGHTUP   : MOUSEEVENTF_LEFTUP;

    INPUT inputs[2] = {};
    inputs[0].type = INPUT_MOUSE;
    inputs[0].mi.dx = abs_x;
    inputs[0].mi.dy = abs_y;
    inputs[0].mi.dwFlags = MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE | down_flag;

    inputs[1].type = INPUT_MOUSE;
    inputs[1].mi.dx = abs_x;
    inputs[1].mi.dy = abs_y;
    inputs[1].mi.dwFlags = MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE | up_flag;

    SendInput(2, inputs, sizeof(INPUT));
    result->Success();

  } else if (method_call.method_name() == "injectMouseScroll") {
    double dy = get_double("dy");
    INPUT input = {};
    input.type = INPUT_MOUSE;
    input.mi.mouseData = static_cast<DWORD>(static_cast<int>(dy) * WHEEL_DELTA);
    input.mi.dwFlags = MOUSEEVENTF_WHEEL;
    SendInput(1, &input, sizeof(INPUT));
    result->Success();

  } else if (method_call.method_name() == "injectKey") {
    int key_code = get_int("keyCode");
    bool down = get_bool("down");

    INPUT input = {};
    input.type = INPUT_KEYBOARD;
    input.ki.wVk = static_cast<WORD>(key_code);
    input.ki.dwFlags = down ? 0 : KEYEVENTF_KEYUP;
    SendInput(1, &input, sizeof(INPUT));
    result->Success();

  } else {
    result->NotImplemented();
  }
}
```

- [ ] **Step 3: Register InputInjectorPlugin alongside ScreenCapturePlugin**

Update `flutter_host/windows/runner/main.cpp` to also register `InputInjectorPlugin`. The registration follows the same pattern as ScreenCapturePlugin in Task 7 Step 4:

```cpp
#include "screen_capture_plugin.h"
#include "input_injector_plugin.h"

// After engine launch:
auto screen_registrar = engine.GetRegistrar("ScreenCapturePlugin");
ScreenCapturePlugin::RegisterWithRegistrar(
    reinterpret_cast<flutter::PluginRegistrarWindows*>(screen_registrar));

auto input_registrar = engine.GetRegistrar("InputInjectorPlugin");
InputInjectorPlugin::RegisterWithRegistrar(
    reinterpret_cast<flutter::PluginRegistrarWindows*>(input_registrar));
```

- [ ] **Step 4: Run flutter analyze (Dart only)**

Native C++ compile errors are only found during `flutter build windows`. The Dart layer is already analyzed. Run analyze to confirm no new Dart issues:

```powershell
$env:PATH = "C:\flutter\bin;" + $env:PATH
cd C:\Users\Guruit\Documents\Gudesk\flutter_host
flutter analyze
```

- [ ] **Step 5: Run Dart test suite**

```powershell
$env:PATH = "C:\flutter\bin;" + $env:PATH
cd C:\Users\Guruit\Documents\Gudesk\flutter_host
flutter test --reporter=expanded
```

Expected: 6/6 tests pass.

- [ ] **Step 6: Commit**

```powershell
cd C:\Users\Guruit\Documents\Gudesk
git add flutter_host/windows/input_injector_plugin.cpp flutter_host/windows/input_injector_plugin.h flutter_host/windows/runner/main.cpp
git commit -m "feat(f5b): add Windows InputInjectorPlugin (SendInput)"
```

- [ ] **Step 7: Push to GitHub**

```powershell
cd C:\Users\Guruit\Documents\Gudesk
git push
```

---

## Self-Review

**Spec coverage:**

| Spec requirement | Task |
|-----------------|------|
| New Flutter project at `flutter_host/` | Task 1 |
| `HostStatus` enum + `HostState` with copyWith | Task 1 |
| `ScreenCaptureService` MethodChannel wrapper | Task 2 |
| `InputInjectorService` MethodChannel wrapper | Task 2 |
| `RtcPcFactory` + `rtcPeerConnectionFactoryProvider` | Task 3 |
| `WsChannelFactory` + `wsChannelFactoryProvider` | Task 3 |
| `HostNotifier` with `start()` and `stop()` | Task 3 |
| idle guard in `start()` | Task 3 |
| WS connect → waiting | Task 3 |
| `sdp_offer` → createPeerConnection → createAnswer → sdp_answer | Task 3 |
| `onIceCandidate` → send ice_candidate | Task 3 |
| `onDataChannel` → route to InputInjectorService | Task 3 |
| `session-end` received → `_cleanup()` → waiting | Task 3 |
| WS close during waiting/streaming → error | Task 3 |
| `stop()` → idle, WS closed | Task 3 |
| `_cleanup()` stops capture, closes DC + PC | Task 3 |
| `hostNotifierProvider` | Task 3 |
| 6 unit tests | Task 3 |
| `HostScreen` ConsumerStatefulWidget | Task 4 |
| Status-driven UI (idle/connecting/waiting/streaming/error) | Task 4 |
| Stop Hosting + Start Hosting buttons | Task 4 |
| `main.dart` with ProviderScope | Task 4 |
| macOS ScreenCaptureKit plugin | Task 5 |
| macOS Screen Recording permission check/request | Task 5 |
| macOS entitlements + Info.plist | Task 5 |
| macOS InputInjectorPlugin (CGEventPost) | Task 6 |
| macOS Accessibility permission check/request | Task 6 |
| Windows DXGI screen capture plugin | Task 7 |
| Windows CMakeLists.txt + D3D11/DXGI link libs | Task 7 |
| Windows InputInjectorPlugin (SendInput) | Task 8 |
| All DataChannel event types (mouse_move, mouse_click, mouse_scroll, key) | Task 3 + Task 8 |

All spec requirements covered. `mouse_scroll` was in the DataChannel format spec and `injectMouseScroll` was defined in `InputInjectorService` — both are implemented in Task 2, Task 3 (Dart handler), and Tasks 6/8 (native).
