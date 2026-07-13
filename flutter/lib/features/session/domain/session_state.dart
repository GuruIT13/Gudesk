import 'package:web_socket_channel/web_socket_channel.dart';

enum SignalingStatus { idle, connecting, waitingForPeer, connected, error, timeout }

class SessionInfo {
  const SessionInfo({
    required this.deviceId,
    required this.hostname,
    required this.wsChannel,
  });

  final String deviceId;
  final String hostname;
  final WebSocketChannel wsChannel;
}

class SignalingState {
  const SignalingState({
    required this.status,
    this.sessionInfo,
    this.errorReason,
  });

  final SignalingStatus status;
  final SessionInfo? sessionInfo;
  final String? errorReason;

  static const idle = SignalingState(status: SignalingStatus.idle);

  SignalingState copyWith({
    SignalingStatus? status,
    SessionInfo? sessionInfo,
    String? errorReason,
  }) =>
      SignalingState(
        status: status ?? this.status,
        sessionInfo: sessionInfo ?? this.sessionInfo,
        errorReason: errorReason ?? this.errorReason,
      );
}
