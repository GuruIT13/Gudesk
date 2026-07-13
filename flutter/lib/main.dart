import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/api/api_client.dart';
import 'core/router/app_router.dart';
import 'core/storage/secure_storage.dart';
import 'features/auth/presentation/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final jwt = await secureStorage.readJwt();
  if (jwt != null) {
    apiClient.setJwt(jwt);
  }
  runApp(ProviderScope(
    overrides: [
      jwtProvider.overrideWith((ref) => jwt),
    ],
    child: const GudeskApp(),
  ));
}

class GudeskApp extends ConsumerWidget {
  const GudeskApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'GuDesk',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
        useMaterial3: true,
      ),
      routerConfig: router,
    );
  }
}
