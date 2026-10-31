#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter_windows.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {

// Brings an already running Mothball to the front. Returns false when there
// is none (or it has no window yet), so this copy carries on starting.
bool FocusRunningInstance() {
  HWND existing = ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"Mothball");
  if (existing == nullptr) {
    return false;
  }
  if (::IsIconic(existing)) {
    ::ShowWindow(existing, SW_RESTORE);
  } else {
    ::ShowWindow(existing, SW_SHOW);
  }
  ::SetForegroundWindow(existing);
  return true;
}

// Places the window in the middle of the primary screen's work area.
Win32Window::Point CenteredOrigin(const Win32Window::Size& size) {
  RECT work;
  if (!::SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0)) {
    return Win32Window::Point(10, 10);
  }
  HMONITOR monitor = ::MonitorFromPoint(POINT{work.left, work.top},
                                        MONITOR_DEFAULTTOPRIMARY);
  double scale = FlutterDesktopGetDpiForMonitor(monitor) / 96.0;
  int width = static_cast<int>((work.right - work.left) / scale);
  int height = static_cast<int>((work.bottom - work.top) / scale);
  int x = static_cast<int>(work.left / scale) + (width - static_cast<int>(size.width)) / 2;
  int y = static_cast<int>(work.top / scale) + (height - static_cast<int>(size.height)) / 2;
  return Win32Window::Point(x > 0 ? x : 0, y > 0 ? y : 0);
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // One Mothball at a time: opening it again (from the Start menu or the
  // tray's "Open Mothball") brings the open window forward.
  HANDLE single = ::CreateMutexW(nullptr, TRUE, L"Local\\MothballDesktopApp");
  if (single != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    if (FocusRunningInstance()) {
      return EXIT_SUCCESS;
    }
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Size size(1100, 820);
  RECT work;
  if (::SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0)) {
    // Smaller screens: fit inside the work area.
    HMONITOR monitor = ::MonitorFromPoint(POINT{work.left, work.top},
                                          MONITOR_DEFAULTTOPRIMARY);
    double scale = FlutterDesktopGetDpiForMonitor(monitor) / 96.0;
    unsigned int max_w = static_cast<unsigned int>((work.right - work.left) / scale) - 40;
    unsigned int max_h = static_cast<unsigned int>((work.bottom - work.top) / scale) - 40;
    if (size.width > max_w) size.width = max_w;
    if (size.height > max_h) size.height = max_h;
  }
  Win32Window::Point origin = CenteredOrigin(size);
  if (!window.Create(L"Mothball", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (single != nullptr) {
    ::ReleaseMutex(single);
    ::CloseHandle(single);
  }
  return EXIT_SUCCESS;
}
