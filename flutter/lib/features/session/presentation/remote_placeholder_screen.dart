import 'package:flutter/material.dart';
import '../domain/session_state.dart';

class RemotePlaceholderScreen extends StatelessWidget {
  const RemotePlaceholderScreen({super.key, required this.sessionInfo});
  final SessionInfo sessionInfo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Text('Remote: ${sessionInfo.hostname}')));
  }
}
