import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/session/presentation/connecting_screen.dart';
import '../../features/session/presentation/remote_placeholder_screen.dart';
import '../../features/session/domain/session_state.dart';
import '../storage/secure_storage.dart';
import '../api/api_client.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) async {
      try {
        final jwt = await secureStorage.readJwt();
        if (jwt != null) {
          apiClient.setJwt(jwt);
          ref.read(jwtProvider.notifier).state = jwt;
        }
        final isLoggedIn = jwt != null;
        final isLoggingIn = state.matchedLocation == '/login';
        if (!isLoggedIn && !isLoggingIn) return '/login';
        if (isLoggedIn && isLoggingIn) return '/home';
        return null;
      } catch (_) {
        return '/login';
      }
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
      GoRoute(
        path: '/connecting',
        builder: (_, state) {
          final deviceId = state.uri.queryParameters['deviceId'] ?? '';
          final hostname = state.uri.queryParameters['hostname'] ?? deviceId;
          return ConnectingScreen(deviceId: deviceId, hostname: hostname);
        },
      ),
      GoRoute(
        path: '/remote',
        builder: (_, state) {
          final info = state.extra as SessionInfo;
          return RemotePlaceholderScreen(sessionInfo: info);
        },
      ),
    ],
  );
});
