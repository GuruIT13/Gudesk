#include "screen_capture_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <wrl/client.h>
#include <d3d11.h>
#include <dxgi1_2.h>

#pragma comment(lib, "d3d11.lib")
#pragma comment(lib, "dxgi.lib")

using namespace Microsoft::WRL;

void ScreenCapturePlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "gudesk/screen_capture",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<ScreenCapturePlugin>();
  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

ScreenCapturePlugin::ScreenCapturePlugin() {}

ScreenCapturePlugin::~ScreenCapturePlugin() {
  capturing_ = false;
  if (capture_thread_.joinable()) {
    capture_thread_.join();
  }
}

void ScreenCapturePlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name() == "hasPermission") {
    result->Success(flutter::EncodableValue(true));
  } else if (method_call.method_name() == "requestPermission") {
    result->Success();
  } else if (method_call.method_name() == "startCapture") {
    StartCapture(std::move(result));
  } else if (method_call.method_name() == "stopCapture") {
    StopCapture(std::move(result));
  } else {
    result->NotImplemented();
  }
}

void ScreenCapturePlugin::StartCapture(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (capturing_) {
    result->Success();
    return;
  }

  D3D_FEATURE_LEVEL feature_level;
  HRESULT hr = D3D11CreateDevice(
      nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, 0,
      nullptr, 0, D3D11_SDK_VERSION,
      &d3d_device_, &feature_level, nullptr);
  if (FAILED(hr)) {
    result->Error("D3D_FAILED", "D3D11CreateDevice failed");
    return;
  }

  ComPtr<IDXGIDevice> dxgi_device;
  hr = d3d_device_.As(&dxgi_device);
  if (FAILED(hr) || !dxgi_device) {
    result->Error("DXGI_FAILED", "Failed to get IDXGIDevice");
    return;
  }

  ComPtr<IDXGIAdapter> adapter;
  hr = dxgi_device->GetAdapter(&adapter);
  if (FAILED(hr) || !adapter) {
    result->Error("DXGI_FAILED", "Failed to get IDXGIAdapter");
    return;
  }

  ComPtr<IDXGIOutput> output;
  hr = adapter->EnumOutputs(0, &output);
  if (FAILED(hr) || !output) {
    result->Error("DXGI_FAILED", "No display output found");
    return;
  }

  ComPtr<IDXGIOutput1> output1;
  hr = output.As(&output1);
  if (FAILED(hr) || !output1) {
    result->Error("DXGI_FAILED", "Failed to get IDXGIOutput1");
    return;
  }

  hr = output1->DuplicateOutput(d3d_device_.Get(), &duplication_);
  if (FAILED(hr)) {
    result->Error("DUPLICATION_FAILED", "DuplicateOutput failed");
    return;
  }

  capturing_ = true;
  capture_thread_ = std::thread([this]() { CaptureLoop(); });

  result->Success();
}

void ScreenCapturePlugin::StopCapture(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  capturing_ = false;
  if (capture_thread_.joinable()) {
    capture_thread_.join();
  }
  duplication_.Reset();
  d3d_device_.Reset();
  result->Success();
}

void ScreenCapturePlugin::CaptureLoop() {
  while (capturing_) {
    DXGI_OUTDUPL_FRAME_INFO frame_info;
    ComPtr<IDXGIResource> desktop_resource;

    HRESULT hr =
        duplication_->AcquireNextFrame(16, &frame_info, &desktop_resource);
    if (hr == DXGI_ERROR_WAIT_TIMEOUT) {
      continue;
    }
    if (FAILED(hr)) {
      break;
    }

    // Frame acquired. WebRTC video track integration (converting ID3D11Texture2D
    // to RTCVideoFrame and pushing to RTCVideoSource) is completed when
    // flutter_webrtc's native source API is wired up.
    duplication_->ReleaseFrame();
  }
}
