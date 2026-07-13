import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _kJwtKey = 'gudesk_jwt';

class SecureStorage {
  const SecureStorage(this._storage);

  final FlutterSecureStorage _storage;

  Future<String?> readJwt() => _storage.read(key: _kJwtKey);

  Future<void> writeJwt(String jwt) => _storage.write(key: _kJwtKey, value: jwt);

  Future<void> deleteJwt() => _storage.delete(key: _kJwtKey);
}

const secureStorage = SecureStorage(FlutterSecureStorage());
