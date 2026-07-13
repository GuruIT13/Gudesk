import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../domain/directory.dart';

class DirectoriesRepository {
  const DirectoriesRepository({required Dio dio}) : _dio = dio;

  final Dio _dio;

  Future<List<Directory>> fetchTree() async {
    final res = await _dio.get('/api/directories');
    return (res.data as List<dynamic>)
        .map((j) => Directory.fromJson(j as Map<String, dynamic>))
        .toList();
  }
}

final directoriesRepositoryProvider = Provider<DirectoriesRepository>(
  (ref) => DirectoriesRepository(dio: apiClient.dio),
);

final directoriesProvider = FutureProvider<List<Directory>>((ref) {
  return ref.watch(directoriesRepositoryProvider).fetchTree();
});

final selectedDirectoryProvider = StateProvider<String?>((ref) => null);
