import 'package:dio/dio.dart';

class ApiClient {
  ApiClient({required String baseUrl}) {
    dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Content-Type': 'application/json'},
    ));

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (_jwt != null) {
          options.headers['Authorization'] = 'Bearer $_jwt';
        }
        handler.next(options);
      },
    ));
  }

  late final Dio dio;
  String? _jwt;

  void setJwt(String? jwt) => _jwt = jwt;
}

final apiClient = ApiClient(baseUrl: 'http://localhost:3000');
