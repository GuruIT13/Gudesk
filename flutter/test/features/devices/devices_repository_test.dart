import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:gudesk_controller/features/devices/data/devices_repository.dart';
import 'package:gudesk_controller/features/devices/domain/device.dart';

class MockDio extends Mock implements Dio {}

void main() {
  late MockDio mockDio;
  late DevicesRepository repo;

  setUp(() {
    mockDio = MockDio();
    repo = DevicesRepository(dio: mockDio);
  });

  group('DevicesRepository', () {
    test('fetchByDirectory returns list of Device', () async {
      when(() => mockDio.get('/api/devices', queryParameters: {'directory_id': 'dir-1'}))
          .thenAnswer((_) async => Response(
                requestOptions: RequestOptions(path: '/api/devices'),
                statusCode: 200,
                data: [
                  {
                    'id': 'dev-1',
                    'hostname': 'DESKTOP-ABC',
                    'status': 'online',
                    'directory_id': 'dir-1',
                    'os_type': 'windows',
                    'os_version': '11',
                  },
                ],
              ));

      final devices = await repo.fetchByDirectory('dir-1');
      expect(devices.length, equals(1));
      expect(devices.first.hostname, equals('DESKTOP-ABC'));
      expect(devices.first.status, equals(DeviceStatus.online));
    });

    test('fetchByDirectory returns empty list when directory has no devices', () async {
      when(() => mockDio.get('/api/devices', queryParameters: {'directory_id': 'dir-empty'}))
          .thenAnswer((_) async => Response(
                requestOptions: RequestOptions(path: '/api/devices'),
                statusCode: 200,
                data: [],
              ));

      final devices = await repo.fetchByDirectory('dir-empty');
      expect(devices, isEmpty);
    });
  });
}
