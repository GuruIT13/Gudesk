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
  VideoRenderer? _renderer;
  WebSocketChannel? _ws;
  StreamSubscription<dynamic>? _wsSub;

  @override
  WebRtcState build() => WebRtcState.idle;

  RTCVideoRenderer? get renderer => _renderer as RTCVideoRenderer?;

  Future<void> start({
    required WebSocketChannel wsChannel,
    required String deviceId,
    VideoRenderer Function()? rendererFactory,
  }) async {
    if (state.status != WebRtcStatus.idle) return;
    _ws = wsChannel;

    _renderer =
        rendererFactory != null ? rendererFactory() : RTCVideoRenderer();
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
      if (event.streams.isNotEmpty && event.track.kind == 'video') {
        _renderer?.srcObject = event.streams[0];
        state = state.copyWith(status: WebRtcStatus.streaming);
      }
    };

    _wsSub = wsChannel.stream.listen(
      (raw) async {
        try {
          final msg = jsonDecode(raw as String) as Map<String, dynamic>;
          switch (msg['type']) {
            case 'sdp_answer':
              await _pc?.setRemoteDescription(
                RTCSessionDescription(msg['sdp'] as String, 'answer'),
              );
            case 'ice_candidate':
              await _pc?.addCandidate(RTCIceCandidate(
                msg['candidate'] as String?,
                msg['sdpMid'] as String?,
                msg['sdpMLineIndex'] as int?,
              ));
          }
        } catch (e) {
          state = state.copyWith(
            status: WebRtcStatus.error,
            errorReason: e.toString(),
          );
        }
      },
      onDone: () {
        _wsSub = null;
        _ws = null;
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
