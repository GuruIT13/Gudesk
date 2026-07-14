import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class InputInjectorService {
  static const _channel = MethodChannel('gudesk/input_injector');

  Future<bool> hasPermission() async =>
      await _channel.invokeMethod<bool>('hasPermission') ?? false;

  Future<void> requestPermission() =>
      _channel.invokeMethod('requestPermission');

  Future<void> injectMouseMove(double x, double y) =>
      _channel.invokeMethod('injectMouseMove', {'x': x, 'y': y});

  Future<void> injectMouseClick(String button, double x, double y) =>
      _channel.invokeMethod('injectMouseClick', {
        'button': button,
        'x': x,
        'y': y,
      });

  Future<void> injectMouseScroll(double dx, double dy) =>
      _channel.invokeMethod('injectMouseScroll', {'dx': dx, 'dy': dy});

  Future<void> injectKey(int keyCode, List<String> modifiers, bool down) =>
      _channel.invokeMethod('injectKey', {
        'keyCode': keyCode,
        'modifiers': modifiers,
        'down': down,
      });
}

final inputInjectorServiceProvider = Provider<InputInjectorService>(
  (_) => InputInjectorService(),
);
