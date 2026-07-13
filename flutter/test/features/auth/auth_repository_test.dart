import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:gudesk_controller/core/api/api_client.dart';
import 'package:gudesk_controller/features/auth/data/auth_repository.dart';
import 'package:gudesk_controller/features/auth/domain/user.dart';

class MockDio extends Mock implements Dio {}

void main() {
  group('ApiClient', () {
    test('adds Authorization header when jwt is provided', () async {
      final client = ApiClient(baseUrl: 'http://localhost:3000');
      client.setJwt('test.jwt.token');

      final interceptors = client.dio.interceptors;
      expect(interceptors.length, greaterThan(0));

      final opts = RequestOptions(path: '/api/devices');
      final handler = RequestInterceptorHandler();
      interceptors
          .whereType<InterceptorsWrapper>()
          .first
          .onRequest(opts, handler);

      expect(opts.headers['Authorization'], equals('Bearer test.jwt.token'));
    });

    test('does not add Authorization header when jwt is null', () async {
      final client = ApiClient(baseUrl: 'http://localhost:3000');

      final opts = RequestOptions(path: '/api/devices');
      final handler = RequestInterceptorHandler();
      final interceptors = client.dio.interceptors;
      interceptors
          .whereType<InterceptorsWrapper>()
          .first
          .onRequest(opts, handler);

      expect(opts.headers.containsKey('Authorization'), isFalse);
    });
  });

  group('AuthRepository', () {
    late MockDio mockDio;
    late AuthRepository repo;

    setUp(() {
      mockDio = MockDio();
      repo = AuthRepository(dio: mockDio);
    });

    test('login returns LoginResult with token and user on 200', () async {
      when(() => mockDio.post(
            '/api/auth/login',
            data: {'email': 'alice@alpha.com', 'password': 'plaintext_alice'},
          )).thenAnswer((_) async => Response(
            requestOptions: RequestOptions(path: '/api/auth/login'),
            statusCode: 200,
            data: {
              'token': 'jwt.token.here',
              'user': {
                'id': 'uuid-1',
                'email': 'alice@alpha.com',
                'display_name': 'Alice',
              },
            },
          ));

      final result = await repo.login('alice@alpha.com', 'plaintext_alice');
      expect(result.token, equals('jwt.token.here'));
      expect(result.user.email, equals('alice@alpha.com'));
      expect(result.user.displayName, equals('Alice'));
    });

    test('login throws AuthException on 401', () async {
      when(() => mockDio.post(any(), data: any(named: 'data')))
          .thenThrow(DioException(
            requestOptions: RequestOptions(path: '/api/auth/login'),
            response: Response(
              requestOptions: RequestOptions(path: '/api/auth/login'),
              statusCode: 401,
              data: {'error': 'invalid_credentials'},
            ),
            type: DioExceptionType.badResponse,
          ));

      expect(
        () => repo.login('bad@email.com', 'wrong'),
        throwsA(isA<AuthException>()),
      );
    });
  });
}
