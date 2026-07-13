import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../domain/device.dart';

class DevicesRepository {
  const DevicesRepository({required Dio dio}) : _dio = dio;

  final Dio _dio;

  Future<List<Device>> fetchByDirectory(String directoryId) async {
    final res = await _dio.get(
      '/api/devices',
      queryParameters: {'directory_id': directoryId},
    );
    return (res.data as List<dynamic>)
        .map((j) => Device.fromJson(j as Map<String, dynamic>))
        .toList();
  }
}

final devicesRepositoryProvider = Provider<DevicesRepository>(
  (ref) => DevicesRepository(dio: apiClient.dio),
);

final devicesProvider = StreamProvider.family<List<Device>, String>((ref, directoryId) async* {
  final repo = ref.watch(devicesRepositoryProvider);
  while (true) {
    try {
      yield await repo.fetchByDirectory(directoryId);
    } on DioException catch (_) {
      // Swallow transient network errors; grid retains last good data.
    }
    await Future.delayed(const Duration(seconds: 30));
  }
});
