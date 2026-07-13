import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:gudesk_controller/features/session/data/signaling_repository.dart';
import 'package:gudesk_controller/features/session/domain/session_state.dart';

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
  group('SignalingNotifier', () {
    test('transitions to waitingForPeer on connect', () async {
      final ctrl = StreamController<dynamic>();
      final channel = buildMockChannel(stream: ctrl.stream);

      final container = ProviderContainer(
        overrides: [
          wsChannelFactoryProvider.overrideWithValue((uri) => channel),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(signalingNotifierProvider.notifier);
      expect(container.read(signalingNotifierProvider).status, equals(SignalingStatus.idle));

      notifier.connect(deviceId: 'dev-1', hostname: 'DESKTOP-1', jwt: 'tok', baseWsUrl: 'ws://localhost:3000');

      await Future.microtask(() {});
      expect(container.read(signalingNotifierProvider).status, equals(SignalingStatus.waitingForPeer));

      ctrl.close();
    });

    test('transitions to connected on peer-joined message', () async {
      final ctrl = StreamController<dynamic>();
      final channel = buildMockChannel(stream: ctrl.stream);

      final container = ProviderContainer(
        overrides: [wsChannelFactoryProvider.overrideWithValue((uri) => channel)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(signalingNotifierProvider.notifier);
      notifier.connect(deviceId: 'dev-1', hostname: 'DESKTOP-1', jwt: 'tok', baseWsUrl: 'ws://localhost:3000');

      await Future.microtask(() {});
      ctrl.add(jsonEncode({'type': 'peer-joined'}));
      await Future.delayed(const Duration(milliseconds: 50));

      expect(container.read(signalingNotifierProvider).status, equals(SignalingStatus.connected));
      ctrl.close();
    });

    test('transitions to error on error message', () async {
      final ctrl = StreamController<dynamic>();
      final channel = buildMockChannel(stream: ctrl.stream);

      final container = ProviderContainer(
        overrides: [wsChannelFactoryProvider.overrideWithValue((uri) => channel)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(signalingNotifierProvider.notifier);
      notifier.connect(deviceId: 'dev-1', hostname: 'DESKTOP-1', jwt: 'tok', baseWsUrl: 'ws://localhost:3000');

      await Future.microtask(() {});
      ctrl.add(jsonEncode({'type': 'error', 'reason': 'device_busy'}));
      await Future.delayed(const Duration(milliseconds: 50));

      final state = container.read(signalingNotifierProvider);
      expect(state.status, equals(SignalingStatus.error));
      expect(state.errorReason, equals('device_busy'));
      ctrl.close();
    });

    test('transitions to timeout after timeout duration', () async {
      final ctrl = StreamController<dynamic>();
      final channel = buildMockChannel(stream: ctrl.stream);

      final container = ProviderContainer(
        overrides: [wsChannelFactoryProvider.overrideWithValue((uri) => channel)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(signalingNotifierProvider.notifier);
      notifier.connect(
        deviceId: 'dev-1',
        hostname: 'DESKTOP-1',
        jwt: 'tok',
        baseWsUrl: 'ws://localhost:3000',
        timeoutDuration: const Duration(milliseconds: 100),
      );

      await Future.delayed(const Duration(milliseconds: 200));

      expect(container.read(signalingNotifierProvider).status, equals(SignalingStatus.timeout));
      ctrl.close();
    });

    test('cancel sends session-end and closes channel', () async {
      final ctrl = StreamController<dynamic>();
      final channel = buildMockChannel(stream: ctrl.stream);
      final sink = channel.sink as MockWebSocketSink;

      final container = ProviderContainer(
        overrides: [wsChannelFactoryProvider.overrideWithValue((uri) => channel)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(signalingNotifierProvider.notifier);
      notifier.connect(deviceId: 'dev-1', hostname: 'DESKTOP-1', jwt: 'tok', baseWsUrl: 'ws://localhost:3000');
      await Future.microtask(() {});

      await notifier.cancel();

      verify(() => sink.add(jsonEncode({'type': 'session-end'}))).called(1);
      verify(() => sink.close()).called(1);
      ctrl.close();
    });
  });
}
