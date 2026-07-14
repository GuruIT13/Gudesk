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
