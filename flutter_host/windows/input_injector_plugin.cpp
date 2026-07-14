#include "input_injector_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <cmath>

void InputInjectorPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "gudesk/input_injector",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<InputInjectorPlugin>();
  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

InputInjectorPlugin::InputInjectorPlugin() {}
InputInjectorPlugin::~InputInjectorPlugin() {}

void InputInjectorPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* args =
      std::get_if<flutter::EncodableMap>(method_call.arguments());

  auto get_double = [&](const std::string& key) -> double {
    if (!args) return 0.0;
    auto it = args->find(flutter::EncodableValue(key));
    if (it == args->end()) return 0.0;
    if (auto* d = std::get_if<double>(&it->second)) return *d;
    if (auto* i = std::get_if<int>(&it->second))
      return static_cast<double>(*i);
    return 0.0;
  };

  auto get_int = [&](const std::string& key) -> int {
    if (!args) return 0;
    auto it = args->find(flutter::EncodableValue(key));
    if (it == args->end()) return 0;
    if (auto* i = std::get_if<int>(&it->second)) return *i;
    if (auto* l = std::get_if<int64_t>(&it->second))
      return static_cast<int>(
          std::max((int64_t)INT_MIN, std::min((int64_t)INT_MAX, *l)));
    return 0;
  };

  auto get_bool = [&](const std::string& key) -> bool {
    if (!args) return false;
    auto it = args->find(flutter::EncodableValue(key));
    if (it == args->end()) return false;
    if (auto* b = std::get_if<bool>(&it->second)) return *b;
    return false;
  };

  auto get_string = [&](const std::string& key) -> std::string {
    if (!args) return "";
    auto it = args->find(flutter::EncodableValue(key));
    if (it == args->end()) return "";
    if (auto* s = std::get_if<std::string>(&it->second)) return *s;
    return "";
  };

  if (method_call.method_name() == "hasPermission") {
    result->Success(flutter::EncodableValue(true));

  } else if (method_call.method_name() == "requestPermission") {
    result->Success();

  } else if (method_call.method_name() == "injectMouseMove") {
    double x = get_double("x");
    double y = get_double("y");
    if (!std::isfinite(x) || !std::isfinite(y)) {
      result->Error("INVALID_ARGS", "Coordinates must be finite");
      return;
    }
    int screen_w = GetSystemMetrics(SM_CXSCREEN);
    int screen_h = GetSystemMetrics(SM_CYSCREEN);
    if (screen_w <= 0 || screen_h <= 0) {
      result->Error("SYSTEM_ERROR", "Failed to get screen metrics");
      return;
    }

    INPUT input = {};
    input.type = INPUT_MOUSE;
    input.mi.dx = static_cast<LONG>((x / screen_w) * 65535.0);
    input.mi.dy = static_cast<LONG>((y / screen_h) * 65535.0);
    input.mi.dwFlags = MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE;
    SendInput(1, &input, sizeof(INPUT));
    result->Success();

  } else if (method_call.method_name() == "injectMouseClick") {
    std::string button = get_string("button");
    double x = get_double("x");
    double y = get_double("y");
    if (!std::isfinite(x) || !std::isfinite(y)) {
      result->Error("INVALID_ARGS", "Coordinates must be finite");
      return;
    }
    int screen_w = GetSystemMetrics(SM_CXSCREEN);
    int screen_h = GetSystemMetrics(SM_CYSCREEN);
    if (screen_w <= 0 || screen_h <= 0) {
      result->Error("SYSTEM_ERROR", "Failed to get screen metrics");
      return;
    }
    LONG abs_x = static_cast<LONG>((x / screen_w) * 65535.0);
    LONG abs_y = static_cast<LONG>((y / screen_h) * 65535.0);

    bool is_right = (button == "right");
    DWORD down_flag = is_right ? MOUSEEVENTF_RIGHTDOWN : MOUSEEVENTF_LEFTDOWN;
    DWORD up_flag   = is_right ? MOUSEEVENTF_RIGHTUP   : MOUSEEVENTF_LEFTUP;

    INPUT inputs[3] = {};
    // Move to position first
    inputs[0].type = INPUT_MOUSE;
    inputs[0].mi.dx = abs_x;
    inputs[0].mi.dy = abs_y;
    inputs[0].mi.dwFlags = MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE;
    // Button down (no position flags)
    inputs[1].type = INPUT_MOUSE;
    inputs[1].mi.dwFlags = down_flag;
    // Button up (no position flags)
    inputs[2].type = INPUT_MOUSE;
    inputs[2].mi.dwFlags = up_flag;

    SendInput(3, inputs, sizeof(INPUT));
    result->Success();

  } else if (method_call.method_name() == "injectMouseScroll") {
    double dy = get_double("dy");
    double dx = get_double("dx");

    if (dy != 0.0) {
      INPUT input = {};
      input.type = INPUT_MOUSE;
      // clamp to DWORD range; WHEEL_DELTA = 120 per notch, invert sign
      double raw_v = dy * -static_cast<double>(WHEEL_DELTA);
      input.mi.mouseData = static_cast<DWORD>(
          static_cast<LONG>(std::max(-32768.0, std::min(32767.0, raw_v))));
      input.mi.dwFlags = MOUSEEVENTF_WHEEL;
      SendInput(1, &input, sizeof(INPUT));
    }

    if (dx != 0.0) {
      INPUT input = {};
      input.type = INPUT_MOUSE;
      double raw_h = dx * static_cast<double>(WHEEL_DELTA);
      input.mi.mouseData = static_cast<DWORD>(
          static_cast<LONG>(std::max(-32768.0, std::min(32767.0, raw_h))));
      input.mi.dwFlags = MOUSEEVENTF_HWHEEL;
      SendInput(1, &input, sizeof(INPUT));
    }

    result->Success();

  } else if (method_call.method_name() == "injectKey") {
    int key_code = get_int("keyCode");
    bool down = get_bool("down");

    if (key_code < 0 || key_code > 0xFFFF) {
      result->Error("INVALID_ARGS", "keyCode out of range");
      return;
    }

    INPUT input = {};
    input.type = INPUT_KEYBOARD;
    input.ki.wVk = static_cast<WORD>(key_code);
    input.ki.dwFlags = down ? 0 : KEYEVENTF_KEYUP;
    SendInput(1, &input, sizeof(INPUT));
    result->Success();

  } else {
    result->NotImplemented();
  }
}
