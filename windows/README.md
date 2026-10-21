# Zalo Switcher cho Windows

Ứng dụng Windows và công cụ dòng lệnh, trong cùng một solution .NET 8. Cách dùng giống bản macOS và có trong [README chính](../README.md#windows); các quy tắc mà chúng tuân theo có trong [docs/how-it-works.md](../docs/how-it-works.md), cùng mục [Trên Windows](../docs/how-it-works.md#trên-windows) nói những chỗ khác macOS.

<p align="center"><img src="../docs/screenshots/cua-so-chinh-windows.png" width="640" alt="Cửa sổ Zalo Switcher trên Windows với bốn tài khoản giả lập"></p>
<p align="center"><sub>Minh họa với dữ liệu giả lập.</sub></p>

## Build và kiểm thử

Bạn cần Windows 10 trở lên và [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0). Chạy các lệnh sau trong thư mục này (PowerShell):

```powershell
dotnet build                          # build cả solution
dotnet test tests\ZaloProfiles.Core.Tests     # chạy logic hồ sơ với một Zalo giả trong thư mục tạm
.\scripts\build.ps1                   # build ZaloSwitcher.exe và zalo-profiles.exe vào build\publish\Zalo Switcher\
.\scripts\build.ps1 -Installer        # ...và tệp cài đặt build\ZaloSwitcher-Setup-<phiên bản>.exe
.\scripts\release.ps1                 # kiểm thử, build, rồi đặt tệp cài đặt, tệp zip và mã kiểm tra vào build\release\
```

Nếu PowerShell chặn script, chạy `powershell -ExecutionPolicy Bypass -File .\scripts\build.ps1`.

Hai tệp chạy là bản x64 tự chứa (self-contained, một tệp), nên máy dùng không cần cài .NET.

Tệp cài đặt (`src/ZaloSwitcherSetup`) viết cho .NET Framework 4.8, có sẵn trong Windows 10 và 11, và mang theo cả hai chương trình trong một thư mục dùng chung một bộ .NET. Nó cài cho riêng người dùng vào `%LOCALAPPDATA%\Programs\Zalo Switcher` (không cần quyền quản trị), tạo lối tắt trong menu Start (và trên màn hình nền nếu chọn), và thêm mục vào Cài đặt → Ứng dụng. Gỡ cài đặt chạy `ZaloSwitcher.exe --uninstall`: xóa chương trình, lối tắt và mục mở cùng Windows, nhưng không đụng tới Zalo hay các tài khoản đã lưu. `ZaloSwitcher-Setup-<phiên bản>.exe /S` cài mà không hỏi gì.

Các tệp không được ký số, nên Windows SmartScreen có thể hiện cảnh báo “Windows đã bảo vệ máy tính của bạn” ở lần mở đầu tiên: bấm **Thông tin khác** rồi **Vẫn chạy**.

### Kiểm thử với Zalo thật

Bài kiểm thử `RealZaloTests` mở một Zalo thật trong một thư mục nhà riêng, trống (Zalo hiện màn hình đăng nhập), tìm ra nó, đưa nó lên trước rồi bảo nó thoát. Zalo và dữ liệu của bạn không bị đụng tới. Nó chỉ chạy khi bạn bật:

```powershell
$env:ZALO_INTEGRATION = "1"; dotnet test tests\ZaloProfiles.Core.Tests --filter RealZaloTests
```

## Bản demo và ảnh chụp màn hình

```powershell
& "build\publish\Zalo Switcher\ZaloSwitcher.exe" --demo                        # chạy thử với bốn tài khoản giả lập
& "build\publish\Zalo Switcher\ZaloSwitcher.exe" --render-screenshots <thư mục> # vẽ cửa sổ với dữ liệu giả lập ra tệp PNG
```

## Phát hành

Bản Windows và bản macOS dùng chung số phiên bản và chung một bản phát hành `v<phiên bản>`, nên người dùng tìm thấy cả hai trong [bản phát hành mới nhất](https://github.com/ducngfi/zalo-multi-accounts/releases/latest).

1. Đặt `Version` trong `Directory.Build.props` bằng `VERSION` trong [`macos/scripts/build.sh`](../macos/scripts/build.sh), commit và push.
2. Phát hành bản macOS như trong [macos/README.md](../macos/README.md#phát-hành). Lệnh `gh release create v<phiên bản>` tạo thẻ, và GitHub Actions ([`.github/workflows/windows-release.yml`](../.github/workflows/windows-release.yml)) chạy `scripts\release.ps1` trên một máy Windows của GitHub rồi thêm tệp cài đặt, tệp zip và mã kiểm tra vào cùng bản phát hành đó, sau vài phút.
3. Ghi chú của bản phát hành nói về cả hai bản, và mục **Tải về** liệt kê tệp của từng hệ điều hành.

Nếu thẻ được push mà chưa có bản phát hành, workflow tạo một bản nháp với các tệp Windows. Muốn build thử mà không phát hành, chạy workflow bằng tay (Actions → Windows release → Run workflow) và để trống ô thẻ: các tệp nằm trong mục Artifacts của lần chạy đó; điền thẻ (ví dụ `v1.2.0`) để thêm các tệp vào bản phát hành đó. Trên máy Windows của bạn, `scripts\release.ps1` vẫn build mọi thứ vào `build\release\`.

## Mã nguồn

- `src/ZaloProfiles.Core`: lưu trữ hồ sơ, mở và đóng từng tài khoản trong Zalo riêng, đặt Zalo chính, sao lưu, điều khiển tiến trình Zalo (`ZaloControl.cs`), các lời gọi Windows API (`Native.cs`), và dữ liệu giả lập cho bản demo.
- `src/zalo-profiles`: công cụ dòng lệnh.
- `src/ZaloSwitcherSetup`: tệp cài đặt. `src/Shared/Installation.cs` (nơi cài, lối tắt, mục gỡ cài đặt) dùng chung giữa tệp cài đặt và phần gỡ cài đặt của ứng dụng (`Uninstall.cs`).
- `src/ZaloSwitcher`: ứng dụng WPF: cửa sổ chính (`MainWindow`), cài đặt (`SettingsWindow`), biểu tượng ở khay hệ thống (`Tray.cs`), hộp thoại tiếng Việt (`Dialogs.cs`), và phần vẽ ảnh chụp màn hình (`Screenshots.cs`).
- `tests/ZaloProfiles.Core.Tests`: kiểm thử cho phần lõi, chuyển từ bộ kiểm thử của bản macOS, thêm các trường hợp riêng của Windows.
- Biểu tượng là [`assets/icon/AppIcon.ico`](../assets/icon/AppIcon.ico), xuất từ `AppIcon.svg` bằng `assets/icon/make-icons.sh`.

Giao diện chỉ có tiếng Việt. Các hộp thoại xác nhận được vẽ riêng (không dùng MessageBox của Windows) để nút bấm có chữ tiếng Việt trên mọi máy.
