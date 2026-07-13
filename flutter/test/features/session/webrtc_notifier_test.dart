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

// VideoRenderer is the abstract interface; RTCVideoRenderer is the native impl
// that extends ValueNotifier — we mock the abstract interface instead.
class MockVideoRenderer extends Mock implements VideoRenderer {}

class MockMediaStream extends Mock implements MediaStream {}

class MockMediaStreamTrack extends Mock implements MediaStreamTrack {}

// Fakes for registerFallbackValue
class FakeRTCIceCandidate extends Fake implements RTCIceCandidate {}

class FakeRTCSessionDescription extends Fake implements RTCSessionDescription {}

class FakeMediaStream extends Fake implements MediaStream {}

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
  late MockVideoRenderer mockRenderer;

  setUpAll(() {
    registerFallbackValue(FakeRTCIceCandidate());
    registerFallbackValue(FakeRTCSessionDescription());
    registerFallbackValue(FakeMediaStream());
  });

  setUp(() {
    mockPc = MockRTCPeerConnection();
    mockRenderer = MockVideoRenderer();

    // VideoRenderer stubs
    when(() => mockRenderer.initialize()).thenAnswer((_) async {});
    when(() => mockRenderer.dispose()).thenAnswer((_) async {});
    when(() => mockRenderer.srcObject = any()).thenReturn(null);

    // RTCPeerConnection stubs
    when(() => mockPc.onIceCandidate = any()).thenReturn(null);
    when(() => mockPc.onTrack = any()).thenReturn(null);
    when(() => mockPc.addCandidate(any())).thenAnswer((_) async {});
    when(() => mockPc.close()).thenAnswer((_) async {});

    final fakeDesc = RTCSessionDescription('v=0\r\n', 'offer');
    when(() => mockPc.createOffer(any())).thenAnswer((_) async => fakeDesc);
    when(() => mockPc.setLocalDescription(any())).thenAnswer((_) async {});
    when(() => mockPc.setRemoteDescription(any())).thenAnswer((_) async {});
  });

  ProviderContainer buildContainer() {
    return ProviderContainer(
      overrides: [
        rtcPeerConnectionFactoryProvider.overrideWithValue(
          (config, constraints) async => mockPc,
        ),
      ],
    );
  }

  group('WebRtcNotifier', () {
    test('start() transitions to negotiating', () async {
      final ctrl = StreamController<dynamic>();
      final container = buildContainer();
      addTearDown(container.dispose);
      addTearDown(ctrl.close);

      final channel = buildMockChannel(stream: ctrl.stream);

      expect(
        container.read(webRtcNotifierProvider).status,
        equals(WebRtcStatus.idle),
      );

      await container.read(webRtcNotifierProvider.notifier).start(
            wsChannel: channel,
            deviceId: 'dev-1',
            rendererFactory: () => mockRenderer,
          );

      expect(
        container.read(webRtcNotifierProvider).status,
        equals(WebRtcStatus.negotiating),
      );
    });

    test('sdp_answer + onTrack transitions to streaming', () async {
      final ctrl = StreamController<dynamic>();
      final container = buildContainer();
      addTearDown(container.dispose);
      addTearDown(ctrl.close);

      // Capture onTrack setter
      Function(RTCTrackEvent)? capturedOnTrack;
      when(() => mockPc.onTrack = any()).thenAnswer((inv) {
        capturedOnTrack =
            inv.positionalArguments[0] as Function(RTCTrackEvent)?;
        return null;
      });

      final channel = buildMockChannel(stream: ctrl.stream);
      await container.read(webRtcNotifierProvider.notifier).start(
            wsChannel: channel,
            deviceId: 'dev-1',
            rendererFactory: () => mockRenderer,
          );

      // Send sdp_answer
      ctrl.add(jsonEncode({'type': 'sdp_answer', 'sdp': 'v=0\r\n'}));
      await Future.delayed(const Duration(milliseconds: 50));

      // Fire onTrack with a fake video stream
      final mockStream = MockMediaStream();
      final mockTrack = MockMediaStreamTrack();
      when(() => mockTrack.kind).thenReturn('video');
      capturedOnTrack?.call(RTCTrackEvent(
        track: mockTrack,
        streams: [mockStream],
        transceiver: null,
        receiver: null,
      ));
      await Future.delayed(const Duration(milliseconds: 50));

      expect(
        container.read(webRtcNotifierProvider).status,
        equals(WebRtcStatus.streaming),
      );
    });

    test(
        'WS closes during negotiating transitions to error with connection_closed',
        () async {
      final ctrl = StreamController<dynamic>();
      final container = buildContainer();
      addTearDown(container.dispose);

      final channel = buildMockChannel(stream: ctrl.stream);
      await container.read(webRtcNotifierProvider.notifier).start(
            wsChannel: channel,
            deviceId: 'dev-1',
            rendererFactory: () => mockRenderer,
          );

      await ctrl.close();
      await Future.delayed(const Duration(milliseconds: 50));

      final state = container.read(webRtcNotifierProvider);
      expect(state.status, equals(WebRtcStatus.error));
      expect(state.errorReason, equals('connection_closed'));
    });

    test('disconnect() sends session-end over WS sink and closes it', () async {
      final ctrl = StreamController<dynamic>();
      final container = buildContainer();
      addTearDown(container.dispose);
      addTearDown(ctrl.close);

      final channel = buildMockChannel(stream: ctrl.stream);
      final sink = channel.sink as MockWebSocketSink;

      await container.read(webRtcNotifierProvider.notifier).start(
            wsChannel: channel,
            deviceId: 'dev-1',
            rendererFactory: () => mockRenderer,
          );

      await container.read(webRtcNotifierProvider.notifier).disconnect();

      verify(() => sink.add(jsonEncode({'type': 'session-end'}))).called(1);
      verify(() => sink.close()).called(1);
    });

    test('disconnect() closes peer connection', () async {
      final ctrl = StreamController<dynamic>();
      final container = buildContainer();
      addTearDown(container.dispose);
      addTearDown(ctrl.close);

      final channel = buildMockChannel(stream: ctrl.stream);
      await container.read(webRtcNotifierProvider.notifier).start(
            wsChannel: channel,
            deviceId: 'dev-1',
            rendererFactory: () => mockRenderer,
          );

      await container.read(webRtcNotifierProvider.notifier).disconnect();

      verify(() => mockPc.close()).called(1);
    });
  });
}
