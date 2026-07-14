import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
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
              state = HostState(status: HostStatus.waiting);
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
    // Close any pre-existing PC before creating a new one
    await _pc?.close();
    _pc = null;

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
        } catch (e) {
          // injection errors are non-fatal; swallow to keep DataChannel alive
          debugPrint('DataChannel inject error: $e');
        }
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

    if (_pc != null) { // _pc is null if stop() was called during the await chain
      state = state.copyWith(status: HostStatus.streaming);
    }
  }

  Future<void> _cleanup() async {
    if (_pc == null) return;
    final pc = _pc;
    _pc = null; // null before any await to prevent concurrent double-cleanup
    await ref.read(screenCaptureServiceProvider).stopCapture();
    await _dataChannel?.close();
    _dataChannel = null;
    await pc!.close();
  }

  Future<void> stop() async {
    if (state.status == HostStatus.idle) return;
    final wasStreaming = state.status == HostStatus.streaming;
    state = HostState.idle; // set idle first to prevent onDone race, also clears stale errorReason
    if (wasStreaming) {
      _ws?.sink.add(jsonEncode({'type': 'session-end'}));
    }
    await _cleanup();
    await _wsSub?.cancel();
    _wsSub = null;
    await _ws?.sink.close();
    _ws = null;
  }
}

final hostNotifierProvider =
    NotifierProvider<HostNotifier, HostState>(HostNotifier.new);
