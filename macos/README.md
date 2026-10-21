# Zalo Switcher cho macOS

Ứng dụng macOS và công cụ dòng lệnh, trong cùng một Swift package. Cách cài và dùng có trong [README chính](../README.md); các quy tắc mà chúng tuân theo có trong [docs/how-it-works.md](../docs/how-it-works.md).

## Build và kiểm thử

Bạn cần macOS 13 trở lên và Xcode hoặc Command Line Tools. Chạy các lệnh sau trong thư mục này:

```bash
swift build
swift test            # chạy logic hồ sơ với một Zalo giả trong thư mục tạm
scripts/build.sh      # build "Zalo Switcher.app" và zalo-profiles vào build/
scripts/install.sh    # build, cài vào ~/Applications và ~/.local/bin, rồi mở ứng dụng
scripts/release.sh    # build và đóng gói các tệp zip cùng mã kiểm tra cho một bản phát hành GitHub vào build/release/
```

Tệp chạy là bản universal (chip Apple và Intel). Ứng dụng có chữ ký ad-hoc nên chạy được trên máy Mac đã build nó. Ứng dụng không được ký bằng Developer ID hay công chứng, nên bản tải về sẽ hiện cảnh báo bảo mật ở lần mở đầu tiên ([README chính](../README.md#cảnh-báo-bảo-mật-ở-lần-mở-đầu-tiên) có giải thích).

Giao diện chỉ có tiếng Việt. `scripts/build.sh` khai báo ứng dụng là tiếng Việt (`CFBundleDevelopmentRegion` và `vi.lproj`), nên các hộp thoại của hệ thống như hộp chọn thư mục cũng hiện bằng tiếng Việt.

## Bản demo và ảnh chụp màn hình

```bash
open -n "build/Zalo Switcher.app" --args --demo    # chạy thử với bốn tài khoản giả lập
../docs/screenshots/make-screenshots.sh           # tạo lại mọi ảnh của README từ dữ liệu giả lập
```

## Phát hành

1. Tăng `VERSION` và `BUILD` ở đầu `scripts/build.sh`.
2. Chạy `scripts/release.sh`.
3. Commit, push, và đăng các tệp: `gh release create v<phiên bản> build/release/* --title "Zalo Switcher <phiên bản>" --notes-file <ghi chú>`.

## Mã nguồn

- `Sources/ZaloProfilesCore`: lưu trữ hồ sơ, chuyển tài khoản, sao lưu, điều khiển tiến trình Zalo, và dữ liệu giả lập cho bản demo.
- `Sources/zalo-profiles`: công cụ dòng lệnh.
- `Sources/ZaloSwitcher`: ứng dụng AppKit với giao diện SwiftUI: cửa sổ chính (`MainView`), cài đặt (`SettingsView`), biểu tượng thanh menu và menu Dock (`Menus.swift`), và phần vẽ ảnh chụp màn hình (`Screenshots.swift`).
- `Tests/ZaloProfilesCoreTests`: kiểm thử cho phần lõi.
- `Resources/AppIcon.icns`: biểu tượng ứng dụng, xuất từ [`assets/icon/AppIcon.svg`](../assets/icon/AppIcon.svg) bằng `assets/icon/make-icons.sh`. Hãy sửa tệp SVG, không sửa tệp này.
