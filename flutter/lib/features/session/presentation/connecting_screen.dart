import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../data/signaling_repository.dart';
import '../domain/session_state.dart';
import '../../../core/storage/secure_storage.dart';

class ConnectingScreen extends ConsumerStatefulWidget {
  const ConnectingScreen({
    super.key,
    required this.deviceId,
    required this.hostname,
  });

  final String deviceId;
  final String hostname;

  @override
  ConsumerState<ConnectingScreen> createState() => _ConnectingScreenState();
}

class _ConnectingScreenState extends ConsumerState<ConnectingScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startConnect());
  }

  Future<void> _startConnect() async {
    final jwt = await secureStorage.readJwt();
    if (!mounted || jwt == null) {
      if (mounted) context.go('/login');
      return;
    }
    ref.read(signalingNotifierProvider.notifier).connect(
      deviceId: widget.deviceId,
      hostname: widget.hostname,
      jwt: jwt,
      baseWsUrl: 'ws://localhost:3000',
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(signalingNotifierProvider, (_, next) {
      if (!mounted) return;
      if (next.status == SignalingStatus.connected && next.sessionInfo != null) {
        context.pushReplacement('/remote', extra: next.sessionInfo);
      } else if (next.status == SignalingStatus.error || next.status == SignalingStatus.timeout) {
        final msg = next.status == SignalingStatus.timeout
            ? 'Connection timed out'
            : 'Error: ${next.errorReason ?? 'unknown'}';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        context.go('/home');
      }
    });

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text('Connecting to ${widget.hostname}...'),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () async {
                await ref.read(signalingNotifierProvider.notifier).cancel();
                if (mounted) context.go('/home');
              },
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}
