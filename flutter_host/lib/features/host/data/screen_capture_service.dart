import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ScreenCaptureService {
  static const _channel = MethodChannel('gudesk/screen_capture');

  Future<bool> hasPermission() async =>
      await _channel.invokeMethod<bool>('hasPermission') ?? false;

  Future<void> requestPermission() =>
      _channel.invokeMethod('requestPermission');

  Future<void> startCapture() => _channel.invokeMethod('startCapture');

  Future<void> stopCapture() => _channel.invokeMethod('stopCapture');
}

final screenCaptureServiceProvider = Provider<ScreenCaptureService>(
  (_) => ScreenCaptureService(),
);
