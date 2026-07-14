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
    when(() => mockInjector.injectMouseScroll(any(), any())).thenAnswer((_) async {});
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

      final calls = verify(() => sink.add(captureAny())).captured;
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
      addTearDown(() async { if (!ctrl.isClosed) await ctrl.close(); });
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
