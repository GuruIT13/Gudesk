import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../domain/user.dart';

class AuthRepository {
  const AuthRepository({required Dio dio}) : _dio = dio;

  final Dio _dio;

  Future<LoginResult> login(String email, String password) async {
    try {
      final res = await _dio.post(
        '/api/auth/login',
        data: {'email': email, 'password': password},
      );
      return LoginResult(
        token: res.data['token'] as String,
        user: User.fromJson(res.data['user'] as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw const AuthException('Invalid email or password');
      }
      throw AuthException(e.message ?? 'Network error');
    }
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(dio: apiClient.dio),
);
