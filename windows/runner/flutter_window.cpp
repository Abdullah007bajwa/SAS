#include <windows.h>

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include "flutter_window.h"

#include <memory>
#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"

namespace {

std::shared_ptr<flutter::MethodChannel<flutter::EncodableValue>> g_zk_channel;
bool g_zk_connected = false;
bool g_use_simulation = true;

bool ReadSimulationFlag(const flutter::EncodableMap* args) {
  if (!args) return true;
  auto it = args->find(flutter::EncodableValue("simulation"));
  if (it == args->end()) return true;
  if (const auto* value = std::get_if<bool>(&it->second)) {
    return *value;
  }
  return true;
}

std::string ReadStringArg(const flutter::EncodableMap* args,
                          const char* key,
                          const std::string& fallback) {
  if (!args) return fallback;
  auto it = args->find(flutter::EncodableValue(key));
  if (it == args->end()) return fallback;
  if (const auto* value = std::get_if<std::string>(&it->second)) {
    return *value;
  }
  return fallback;
}

int ReadIntArg(const flutter::EncodableMap* args, const char* key, int fallback) {
  if (!args) return fallback;
  auto it = args->find(flutter::EncodableValue(key));
  if (it == args->end()) return fallback;
  if (const auto* value = std::get_if<int32_t>(&it->second)) {
    return static_cast<int>(*value);
  }
  if (const auto* value64 = std::get_if<int64_t>(&it->second)) {
    return static_cast<int>(*value64);
  }
  return fallback;
}

// Attempt real device connect via ZKEMKEEPER.dll when present.
// Requires matching-bitness DLL beside the executable.
bool TryConnectZkDll(const std::string& ip, int port) {
  HMODULE dll = LoadLibraryA("ZKEMKEEPER.dll");
  if (!dll) {
    return false;
  }
  // DLL present — full COM wiring depends on installed SDK headers.
  // Return false so callers can surface a clear setup message.
  FreeLibrary(dll);
  return false;
}

void RegisterZkDeviceChannel(flutter::FlutterEngine* engine) {
  g_zk_channel = std::make_shared<flutter::MethodChannel<flutter::EncodableValue>>(
      engine->messenger(), "com.mastercity.gym/zk_device",
      &flutter::StandardMethodCodec::GetInstance());

  g_zk_channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        const std::string& method = call.method_name();
        const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());

        if (method == "connect") {
          g_use_simulation = ReadSimulationFlag(args);
          if (g_use_simulation) {
            g_zk_connected = true;
            result->Success(flutter::EncodableValue(true));
            return;
          }
          const std::string ip = ReadStringArg(args, "ip", "");
          const int port = ReadIntArg(args, "port", 4370);
          const bool ok = TryConnectZkDll(ip, port);
          g_zk_connected = ok;
          result->Success(flutter::EncodableValue(ok));
          return;
        }

        if (!g_zk_connected && !g_use_simulation) {
          result->Success(flutter::EncodableValue(false));
          return;
        }

        if (method == "enrollFingerprint") {
          std::string userId = ReadStringArg(args, "userId", "unknown");
          result->Success(flutter::EncodableValue(
              std::string(g_use_simulation ? "win_template_" : "dll_template_") +
              userId));
          return;
        }
        if (method == "deleteFingerprint" || method == "enableUser" ||
            method == "disableUser" || method == "pushAllUsers") {
          result->Success(flutter::EncodableValue(true));
          return;
        }
        if (method == "pullAttendanceLogs") {
          result->Success(flutter::EncodableValue(flutter::EncodableList{}));
          return;
        }

        result->NotImplemented();
      });
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  RegisterZkDeviceChannel(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
