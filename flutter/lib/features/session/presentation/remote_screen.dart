import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';
import '../data/webrtc_notifier.dart';
import '../domain/session_state.dart';
import '../domain/webrtc_state.dart';

class RemoteScreen extends ConsumerStatefulWidget {
  const RemoteScreen({super.key, required this.sessionInfo});

  final SessionInfo sessionInfo;

  @override
  ConsumerState<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends ConsumerState<RemoteScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startSession());
  }

  Future<void> _startSession() async {
    await ref.read(webRtcNotifierProvider.notifier).start(
          wsChannel: widget.sessionInfo.wsChannel,
          deviceId: widget.sessionInfo.deviceId,
        );
  }

  Future<void> _disconnect() async {
    await ref.read(webRtcNotifierProvider.notifier).disconnect();
    if (mounted) context.go('/home'); // ignore: use_build_context_synchronously
  }

  @override
  void dispose() {
    final status = ref.read(webRtcNotifierProvider).status;
    if (status != WebRtcStatus.ended && status != WebRtcStatus.error) {
      ref.read(webRtcNotifierProvider.notifier).disconnect();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final webRtcState = ref.watch(webRtcNotifierProvider);
    final renderer = ref.read(webRtcNotifierProvider.notifier).renderer;

    ref.listen(webRtcNotifierProvider, (_, next) {
      if (!mounted) return;
      if (next.status == WebRtcStatus.ended) {
        context.go('/home');
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text('Remote — ${widget.sessionInfo.hostname}'),
        actions: [
          TextButton(
            onPressed: _disconnect,
            child: const Text('Disconnect'),
          ),
        ],
      ),
      body: _buildBody(webRtcState, renderer),
    );
  }

  Widget _buildBody(WebRtcState webRtcState, RTCVideoRenderer? renderer) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Video layer (always present — black when no stream)
        if (renderer != null)
          RTCVideoView(
            renderer,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            mirror: false,
          )
        else
          const ColoredBox(color: Colors.black),

        // Overlay layer
        if (webRtcState.status == WebRtcStatus.negotiating)
          const ColoredBox(
            color: Colors.black,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text(
                    'Connecting...',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ],
              ),
            ),
          )
        else if (webRtcState.status == WebRtcStatus.error)
          ColoredBox(
            color: Colors.black87,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    webRtcState.errorReason ?? 'Connection failed',
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => context.go('/home'),
                    child: const Text('Back'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
