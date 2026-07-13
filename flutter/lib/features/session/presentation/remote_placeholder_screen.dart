import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../data/signaling_repository.dart';
import '../domain/session_state.dart';

class RemotePlaceholderScreen extends ConsumerWidget {
  const RemotePlaceholderScreen({super.key, required this.sessionInfo});

  final SessionInfo sessionInfo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text('Remote — ${sessionInfo.hostname}')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.computer, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('Remote session active — rendering not yet implemented'),
            const SizedBox(height: 8),
            Text('Device: ${sessionInfo.deviceId}',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 24),
            FilledButton.tonal(
              onPressed: () async {
                await ref.read(signalingNotifierProvider.notifier).cancel();
                if (context.mounted) context.go('/home');
              },
              child: const Text('Disconnect'),
            ),
          ],
        ),
      ),
    );
  }
}
