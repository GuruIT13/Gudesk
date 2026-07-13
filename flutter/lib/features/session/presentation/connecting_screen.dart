import 'package:flutter/material.dart';

class ConnectingScreen extends StatelessWidget {
  const ConnectingScreen({super.key, required this.deviceId, required this.hostname});
  final String deviceId;
  final String hostname;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Text('Connecting to $hostname...')));
  }
}
