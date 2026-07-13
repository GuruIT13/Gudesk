import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gudesk_controller/core/api/api_client.dart';

void main() {
  group('ApiClient', () {
    test('adds Authorization header when jwt is provided', () {
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

      // The interceptor calls handler.next(opts) which modifies opts in place
      expect(opts.headers['Authorization'], equals('Bearer test.jwt.token'));
    });

    test('does not add Authorization header when jwt is null', () {
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
}
