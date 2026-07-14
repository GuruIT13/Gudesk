import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/host_notifier.dart';
import '../domain/host_state.dart';

class HostScreen extends ConsumerStatefulWidget {
  const HostScreen({super.key});

  @override
  ConsumerState<HostScreen> createState() => _HostScreenState();
}

class _HostScreenState extends ConsumerState<HostScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    ref.read(hostNotifierProvider.notifier).stop();
    super.dispose();
  }

  Future<void> _start() async {
    await ref.read(hostNotifierProvider.notifier).start(
          deviceUid: 'dev-uid-placeholder',
          wsUrl: 'ws://localhost:3000',
        );
  }

  Future<void> _stop() async {
    await ref.read(hostNotifierProvider.notifier).stop();
  }

  @override
  Widget build(BuildContext context) {
    final hostState = ref.watch(hostNotifierProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('GuDesk Host')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildStatusWidget(hostState),
            const SizedBox(height: 32),
            if (hostState.status != HostStatus.idle)
              OutlinedButton(
                onPressed: _stop,
                child: const Text('Stop Hosting'),
              ),
            if (hostState.status == HostStatus.idle ||
                hostState.status == HostStatus.error)
              ElevatedButton(
                onPressed: _start,
                child: const Text('Start Hosting'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusWidget(HostState hostState) {
    switch (hostState.status) {
      case HostStatus.idle:
        return const Text('Not connected');
      case HostStatus.connecting:
        return const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 8),
            Text('Connecting...'),
          ],
        );
      case HostStatus.waiting:
        return const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, color: Colors.green, size: 12),
            SizedBox(width: 8),
            Text('Waiting for connection...'),
          ],
        );
      case HostStatus.streaming:
        return const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, color: Colors.green, size: 12),
            SizedBox(width: 8),
            Text('Streaming'),
          ],
        );
      case HostStatus.error:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cancel, color: Colors.red, size: 12),
                const SizedBox(width: 8),
                Text('Error: ${hostState.errorReason ?? 'unknown'}'),
              ],
            ),
          ],
        );
    }
  }
}
