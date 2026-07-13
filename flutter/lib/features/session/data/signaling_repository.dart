import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../domain/session_state.dart';

typedef WsChannelFactory = WebSocketChannel Function(Uri uri);

final wsChannelFactoryProvider = Provider<WsChannelFactory>(
  (_) => (uri) => WebSocketChannel.connect(uri),
);

class SignalingNotifier extends Notifier<SignalingState> {
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _timeout;

  @override
  SignalingState build() => SignalingState.idle;

  void connect({
    required String deviceId,
    required String hostname,
    required String jwt,
    required String baseWsUrl,
    Duration timeoutDuration = const Duration(seconds: 10),
  }) {
    final factory = ref.read(wsChannelFactoryProvider);
    final uri = Uri.parse('$baseWsUrl/signal?token=$jwt&device_id=$deviceId');
    _channel = factory(uri);

    state = state.copyWith(status: SignalingStatus.waitingForPeer);

    _timeout = Timer(timeoutDuration, () {
      if (state.status == SignalingStatus.waitingForPeer) {
        state = state.copyWith(status: SignalingStatus.timeout);
        _cleanup();
      }
    });

    _sub = _channel!.stream.listen(
      (raw) {
        final msg = jsonDecode(raw as String) as Map<String, dynamic>;
        _timeout?.cancel();

        if (msg['type'] == 'peer-joined') {
          state = state.copyWith(
            status: SignalingStatus.connected,
            sessionInfo: SessionInfo(
              deviceId: deviceId,
              hostname: hostname,
              wsChannel: _channel!,
            ),
          );
        } else if (msg['type'] == 'error') {
          state = state.copyWith(
            status: SignalingStatus.error,
            errorReason: msg['reason'] as String?,
          );
          _cleanup();
        }
      },
      onDone: () {
        if (state.status == SignalingStatus.waitingForPeer) {
          state = state.copyWith(status: SignalingStatus.error, errorReason: 'connection_closed');
        }
      },
    );
  }

  Future<void> cancel() async {
    _timeout?.cancel();
    _channel?.sink.add(jsonEncode({'type': 'session-end'}));
    await _channel?.sink.close();
    await _sub?.cancel();
    _channel = null;
    _sub = null;
    state = SignalingState.idle;
  }

  void _cleanup() {
    _timeout?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    _channel = null;
    _sub = null;
  }
}

final signalingNotifierProvider =
    NotifierProvider<SignalingNotifier, SignalingState>(SignalingNotifier.new);
