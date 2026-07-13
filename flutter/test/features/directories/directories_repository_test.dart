import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:gudesk_controller/features/directories/data/directories_repository.dart';
import 'package:gudesk_controller/features/directories/domain/directory.dart';

class MockDio extends Mock implements Dio {}

void main() {
  late MockDio mockDio;
  late DirectoriesRepository repo;

  setUp(() {
    mockDio = MockDio();
    repo = DirectoriesRepository(dio: mockDio);
  });

  group('DirectoriesRepository', () {
    test('fetchTree returns list of Directory with children', () async {
      when(() => mockDio.get('/api/directories')).thenAnswer((_) async => Response(
            requestOptions: RequestOptions(path: '/api/directories'),
            statusCode: 200,
            data: [
              {
                'id': 'dir-1',
                'name': 'Root',
                'parent_id': null,
                'children': [
                  {'id': 'dir-2', 'name': 'BKK', 'parent_id': 'dir-1', 'children': []},
                ],
              },
            ],
          ));

      final dirs = await repo.fetchTree();
      expect(dirs.length, equals(1));
      expect(dirs.first.name, equals('Root'));
      expect(dirs.first.children.length, equals(1));
      expect(dirs.first.children.first.name, equals('BKK'));
    });

    test('fetchTree returns empty list when org has no directories', () async {
      when(() => mockDio.get('/api/directories')).thenAnswer((_) async => Response(
            requestOptions: RequestOptions(path: '/api/directories'),
            statusCode: 200,
            data: [],
          ));

      final dirs = await repo.fetchTree();
      expect(dirs, isEmpty);
    });
  });
}
