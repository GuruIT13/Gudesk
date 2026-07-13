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
