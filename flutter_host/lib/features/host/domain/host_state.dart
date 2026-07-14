enum HostStatus { idle, connecting, waiting, streaming, error }

class HostState {
  const HostState({required this.status, this.errorReason});

  final HostStatus status;
  final String? errorReason;

  static const idle = HostState(status: HostStatus.idle);

  static const Object _unset = Object();

  HostState copyWith({HostStatus? status, Object? errorReason = _unset}) =>
      HostState(
        status: status ?? this.status,
        errorReason: identical(errorReason, _unset)
            ? this.errorReason
            : errorReason as String?,
      );
}
