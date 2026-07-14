#pragma once

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <wrl/client.h>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <memory>
#include <thread>
#include <atomic>

class ScreenCapturePlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  ScreenCapturePlugin();
  ~ScreenCapturePlugin() override;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void StartCapture(
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void StopCapture(
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void CaptureLoop();

  Microsoft::WRL::ComPtr<ID3D11Device> d3d_device_;
  Microsoft::WRL::ComPtr<IDXGIOutputDuplication> duplication_;
  std::thread capture_thread_;
  std::atomic<bool> capturing_{false};
};
