import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'features/host/presentation/host_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: GudeskHostApp()));
}

class GudeskHostApp extends StatelessWidget {
  const GudeskHostApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GuDesk Host',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
        useMaterial3: true,
      ),
      home: const HostScreen(),
    );
  }
}
